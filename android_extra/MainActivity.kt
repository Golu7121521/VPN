package com.roxify

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Debug
import java.io.File
import java.io.RandomAccessFile
import java.lang.reflect.Proxy
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.InfoItem
import org.schabi.newpipe.extractor.MediaFormat
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.channel.ChannelInfoItem
import org.schabi.newpipe.extractor.playlist.PlaylistInfo
import org.schabi.newpipe.extractor.playlist.PlaylistInfoItem
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import org.schabi.newpipe.extractor.stream.StreamType
import org.schabi.newpipe.extractor.stream.VideoStream
import java.util.concurrent.TimeUnit

const val UA = "Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0"

class DL : Downloader() {
    private val client = OkHttpClient.Builder().readTimeout(30, TimeUnit.SECONDS).build()
    override fun execute(request: Request): Response {
        val m = request.httpMethod()
        var body = request.dataToSend()?.toRequestBody()
        if (body == null && (m == "POST" || m == "PUT")) body = ByteArray(0).toRequestBody()
        val b = okhttp3.Request.Builder().url(request.url()).method(m, body).header("User-Agent", UA)
        request.headers().forEach { (k, v) ->
            b.removeHeader(k)
            v.forEach { b.addHeader(k, it) }
        }
        val r = client.newCall(b.build()).execute()
        if (r.code == 429) { r.close(); throw ReCaptchaException("Rate limited", request.url()) }
        val text = r.body?.string()
        return Response(r.code, r.message, r.headers.toMultimap(), text, r.request.url.toString())
    }
}

class MainActivity : AudioServiceActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val known = listOf("search", "stream", "videoStream", "playlist", "suggest", "artistImage", "info", "initialShare")
    private var channel: MethodChannel? = null
    private var expectedSig: String? = null
    private val integrityHandler = Handler(Looper.getMainLooper())
    private var pendingShare: String? = null
    private var dartReady = false

    // YouTube "Share" -> Roxify: pull the first link out of the shared text.
    private fun handleIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
        val url = Regex("https?://\\S+").find(text)?.value ?: text
        if (dartReady) channel?.invokeMethod("shared", url) else pendingShare = url
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NewPipe.init(DL())
        handleIntent(intent)
        checkIntegrityOnce()
        integrityHandler.postDelayed(object : Runnable {
            override fun run() {
                checkIntegrityOnce()
                integrityHandler.postDelayed(this, 45_000)
            }
        }, 45_000)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "roxify/newpipe")
        channel!!.setMethodCallHandler { call, result ->
                if (call.method == "initialShare") {
                    dartReady = true
                    result.success(pendingShare)
                    pendingShare = null
                    return@setMethodCallHandler
                }
                if (call.method == "setExpected") {
                    expectedSig = call.argument<String>("sig")
                    result.success(null)
                    checkIntegrityOnce() // check immediately with the now-known expected signature
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val out: Any? = when (call.method) {
                            "search" -> search(call.argument<String>("query") ?: "", call.argument<String>("filter") ?: "music_songs")
                            "stream" -> stream(call.argument<String>("url") ?: "")
                            "videoStream" -> videoStream(call.argument<String>("url") ?: "")
                            "playlist" -> playlist(call.argument<String>("url") ?: "")
                            "suggest" -> suggest(call.argument<String>("query") ?: "")
                            "artistImage" -> artistImage(call.argument<String>("name") ?: "")
                            "info" -> info(call.argument<String>("url") ?: "")
                            else -> null
                        }
                        main.post {
                            if (call.method in known) result.success(out) else result.notImplemented()
                        }
                    } catch (e: Throwable) {
                        main.post { result.error("NEWPIPE", e.toString(), null) }
                    }
                }.start()
            }
    }

    private fun toMap(i: InfoItem): Map<String, Any?>? = when (i) {
        is StreamInfoItem -> mapOf(
            "type" to "stream", "url" to i.url, "title" to i.name, "artist" to (i.uploaderName ?: ""),
            "thumb" to i.thumbnails.maxByOrNull { x -> x.height }?.url, "duration" to i.duration.toInt(),
        )
        is PlaylistInfoItem -> mapOf(
            "type" to "playlist", "url" to i.url, "title" to i.name, "artist" to (i.uploaderName ?: ""),
            "thumb" to i.thumbnails.maxByOrNull { x -> x.height }?.url, "count" to i.streamCount.toInt(),
        )
        is ChannelInfoItem -> mapOf(
            "type" to "channel", "url" to i.url, "title" to i.name,
            "thumb" to i.thumbnails.maxByOrNull { x -> x.height }?.url,
        )
        else -> null
    }

    private fun search(q: String, filter: String): List<Map<String, Any?>> {
        val yt = ServiceList.YouTube
        val ex = yt.getSearchExtractor(q, listOf(filter), "")
        ex.fetchPage()
        var items = ex.initialPage.items
        if (items.isEmpty() && filter == "music_songs") {
            val ex2 = yt.getSearchExtractor(q)
            ex2.fetchPage()
            items = ex2.initialPage.items
        }
        return items.mapNotNull { toMap(it) }
    }

    private fun playlist(url: String): Map<String, Any?> {
        val info = PlaylistInfo.getInfo(ServiceList.YouTube, url)
        return mapOf(
            "name" to info.name,
            "artist" to (info.uploaderName ?: ""),
            "thumb" to info.thumbnails.maxByOrNull { it.height }?.url,
            "items" to info.relatedItems.filterIsInstance<StreamInfoItem>().mapNotNull { toMap(it) },
        )
    }

    private fun stream(url: String): Map<String, Any?> {
        val info = streamInfo(url)
        val all = info.audioStreams
        // AAC (m4a) first, highest bitrate first: plays everywhere. webm/opus and HLS/DASH are fallbacks.
        val prog = all.filter { it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP }.sortedWith(
            compareByDescending<AudioStream> { it.format == MediaFormat.M4A }.thenByDescending { it.averageBitrate }
        )
        val other = all.filter {
            (it.deliveryMethod == DeliveryMethod.HLS || it.deliveryMethod == DeliveryMethod.DASH) && it.isUrl
        }.sortedByDescending { it.averageBitrate }
        val sources = prog.map { mapOf("url" to it.content, "method" to "progressive") } +
            other.map { mapOf("url" to it.content, "method" to it.deliveryMethod.name.lowercase()) }
        val live = info.streamType == StreamType.LIVE_STREAM || info.streamType == StreamType.AUDIO_LIVE_STREAM
        val hls = info.hlsUrl
        val all2 = if (hls != null && hls.isNotEmpty()) {
            val h = mapOf("url" to hls, "method" to "hls")
            if (live) listOf(h) + sources else sources + h
        } else sources
        if (all2.isNotEmpty()) return mapOf("sources" to all2)
        // Last resort: some videos have no standalone audio stream, only muxed video+audio.
        // Use the smallest muxed stream purely as an audio source (ExoPlayer still decodes it).
        val muxed = info.videoStreams
            .filter { it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP && !it.isVideoOnly }
            .sortedBy { it.height }
        if (muxed.isNotEmpty()) {
            return mapOf("sources" to listOf(mapOf("url" to muxed.first().content, "method" to "progressive")))
        }
        throw Exception("No audio stream found")
    }

    // One YouTube fetch per song: audio and video both read from this cache (15 min).
    private val infoCache = HashMap<String, Pair<Long, StreamInfo>>()
    private val infoLocks = java.util.concurrent.ConcurrentHashMap<String, Any>()

    private fun streamInfo(url: String): StreamInfo {
        synchronized(infoLocks.computeIfAbsent(url) { Any() }) {
            val now = System.currentTimeMillis()
            synchronized(infoCache) {
                val c = infoCache[url]
                if (c != null && now - c.first < 15 * 60_000L) return c.second
            }
            val i = StreamInfo.getInfo(ServiceList.YouTube, url)
            synchronized(infoCache) {
                if (infoCache.size > 16) infoCache.keys.firstOrNull()?.let { infoCache.remove(it) }
                infoCache[url] = now to i
            }
            return i
        }
    }

    private fun seg(st: org.schabi.newpipe.extractor.stream.Stream): Map<String, Any?> {
        val t = st.itagItem!!
        return mapOf(
            "url" to st.content, "mime" to (st.format?.mimeType ?: ""), "codec" to (t.codec ?: ""),
            "bitrate" to t.bitrate, "fps" to t.fps, "sampleRate" to t.sampleRate,
            "initStart" to t.initStart, "initEnd" to t.initEnd, "indexStart" to t.indexStart, "indexEnd" to t.indexEnd,
        )
    }

    /**
     * Video options for the Song/Video switch, best first:
     * 1) "dash": separate video-only + audio streams (up to 720p) that ExoPlayer merges via a DASH manifest,
     * 2) "muxed": ready-made video+audio progressive streams.
     */
    private fun videoStream(url: String): Map<String, Any?> {
        val info = streamInfo(url)
        val out = ArrayList<Map<String, Any?>>()
        fun hasRanges(st: org.schabi.newpipe.extractor.stream.Stream) =
            st.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP && st.isUrl && (st.itagItem?.let { it.indexEnd > 0 } == true)
        val vOnly = info.videoOnlyStreams.filter { hasRanges(it) }
        val aud = info.audioStreams.filter { hasRanges(it) }
        if (vOnly.isNotEmpty() && aud.isNotEmpty()) {
            val mp4 = vOnly.filter { it.format == MediaFormat.MPEG_4 }
            val pool = if (mp4.isNotEmpty()) mp4 else vOnly
            val fit = pool.filter { it.height <= 720 }.ifEmpty { pool }
            val v = fit.sortedWith(
                compareByDescending<VideoStream> { it.height }.thenByDescending { (it.itagItem?.codec ?: "").startsWith("avc1") }
            ).first()
            val a = aud.sortedWith(
                compareByDescending<AudioStream> { it.format == MediaFormat.M4A }.thenByDescending { it.averageBitrate }
            ).first()
            out.add(mapOf("kind" to "dash", "height" to v.height, "duration" to info.duration.toInt(), "v" to seg(v), "a" to seg(a)))
        }
        info.videoStreams
            .filter { it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP && !it.isVideoOnly && it.isUrl }
            .sortedWith(compareByDescending<VideoStream> { it.format == MediaFormat.MPEG_4 }.thenByDescending { it.height })
            .forEach { out.add(mapOf("kind" to "muxed", "url" to it.content, "height" to it.height)) }
        val hls = info.hlsUrl
        if (out.isEmpty() && hls != null && hls.isNotEmpty()) out.add(mapOf("kind" to "hls", "url" to hls, "height" to 0))
        return mapOf("sources" to out)
    }

    private fun sha256hex(b: ByteArray) =
        MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }

    /**
     * Reads the signing certificate straight from the APK file (v2/v3 signing block), so it still
     * works even if PackageManager has been hooked to lie about the signature.
     */
    private fun apkSignerHash(path: String): String? = try {
        val le = ByteOrder.LITTLE_ENDIAN
        RandomAccessFile(path, "r").use { f ->
            val len = f.length()
            val back = minOf(len, 65557L).toInt()
            val tail = ByteArray(back)
            f.seek(len - back)
            f.readFully(tail)
            var eocd = -1
            for (i in back - 22 downTo 0) {
                if (tail[i] == 0x50.toByte() && tail[i + 1] == 0x4b.toByte() && tail[i + 2] == 0x05.toByte() && tail[i + 3] == 0x06.toByte()) {
                    eocd = i
                    break
                }
            }
            if (eocd < 0) return@use null
            val cdOffset = ByteBuffer.wrap(tail).order(le).getInt(eocd + 16).toLong() and 0xffffffffL
            val footer = ByteArray(24)
            f.seek(cdOffset - 24)
            f.readFully(footer)
            if (String(footer, 8, 16, Charsets.ISO_8859_1) != "APK Sig Block 42") return@use null
            val blockSize = ByteBuffer.wrap(footer, 0, 8).order(le).long
            val pairs = ByteArray((blockSize - 24).toInt())
            f.seek(cdOffset - blockSize - 8 + 8)
            f.readFully(pairs)
            val pb = ByteBuffer.wrap(pairs).order(le)
            var out: String? = null
            while (out == null && pb.remaining() >= 12) {
                val pairLen = pb.long
                val id = pb.int
                val value = ByteArray((pairLen - 4).toInt())
                pb.get(value)
                if (id == 0x7109871a || id == 0xf05368c0.toInt()) {
                    val v = ByteBuffer.wrap(value).order(le)
                    v.int // signers sequence length
                    val signer = ByteArray(v.int)
                    v.get(signer)
                    val s = ByteBuffer.wrap(signer).order(le)
                    val signedData = ByteArray(s.int)
                    s.get(signedData)
                    val d = ByteBuffer.wrap(signedData).order(le)
                    val digestsLen = d.int
                    d.position(d.position() + digestsLen) // skip digests
                    d.int // certificates sequence length
                    val cert = ByteArray(d.int)
                    d.get(cert)
                    out = sha256hex(cert)
                }
            }
            out
        }
    } catch (_: Throwable) {
        null
    }

    /**
     * Runs entirely on the native side: a tampered copy (wrong signing key, re-signed APK,
     * debugger, Frida/Xposed, a "signature killer" tool, or a wrong package name) is killed
     * immediately and silently - no Flutter UI, no message. Safe to call before `expectedSig`
     * is known; it only acts once it has something to compare against or finds a tamper signal.
     */
    @Suppress("DEPRECATION")
    private fun checkIntegrityOnce() {
        Thread {
            var bad = false
            try {
                val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                val pi = packageManager.getPackageInfo(packageName, flags)
                val sigs = if (Build.VERSION.SDK_INT >= 28) pi.signingInfo?.apkContentsSigners else pi.signatures
                val sig = sigs?.firstOrNull()?.let { sha256hex(it.toByteArray()) }
                val expected = expectedSig
                if (!expected.isNullOrEmpty()) {
                    if (sig != expected) bad = true
                    val apkSig = apkSignerHash(applicationInfo.sourceDir)
                    if (apkSig != null && apkSig != expected) bad = true
                }
            } catch (_: Throwable) {}
            if (Debug.isDebuggerConnected()) bad = true
            try {
                val maps = File("/proc/self/maps").readText().lowercase()
                if (maps.contains("frida") || maps.contains("xposed") || maps.contains("substrate")) bad = true
            } catch (_: Throwable) {}
            val appName = application.javaClass.name.lowercase()
            if (appName.contains("bin.mt") || appName.contains("killer") || appName.contains("signature") || appName.contains("hook")) bad = true
            if (packageName != "com.roxify") bad = true
            if (Proxy.isProxyClass(packageManager.javaClass)) bad = true
            try {
                Class.forName("bin.mt.signature.KillerApplication")
                bad = true
            } catch (_: Throwable) {}
            try {
                val f = Class.forName("android.app.ActivityThread").getDeclaredField("sPackageManager")
                f.isAccessible = true
                val o = f.get(null)
                if (o != null && Proxy.isProxyClass(o.javaClass)) bad = true
            } catch (_: Throwable) {}
            if (bad) {
                android.os.Process.killProcess(android.os.Process.myPid())
                Runtime.getRuntime().exit(0)
            }
        }.start()
    }

    private fun info(url: String): Map<String, Any?> {
        val i = StreamInfo.getInfo(ServiceList.YouTube, url)
        val live = i.streamType == StreamType.LIVE_STREAM || i.streamType == StreamType.AUDIO_LIVE_STREAM
        return mapOf(
            "type" to "stream", "url" to i.url, "title" to i.name, "artist" to (i.uploaderName ?: ""),
            "thumb" to i.thumbnails.maxByOrNull { x -> x.height }?.url, "duration" to (if (live) 0 else i.duration.toInt()),
            "live" to live,
        )
    }

    private fun suggest(q: String): List<String> =
        ServiceList.YouTube.suggestionExtractor.suggestionList(q)

    private fun artistImage(name: String): String? {
        val ex = ServiceList.YouTube.getSearchExtractor(name, listOf("music_artists"), "")
        ex.fetchPage()
        val ch = ex.initialPage.items.filterIsInstance<ChannelInfoItem>().firstOrNull() ?: return null
        return ch.thumbnails.maxByOrNull { it.height }?.url
    }
}
