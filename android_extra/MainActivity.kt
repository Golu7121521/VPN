package com.roxyfy

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Debug
import java.io.File
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
    private val known = listOf("search", "stream", "playlist", "suggest", "artistImage", "info", "initialShare", "integrity")
    private var channel: MethodChannel? = null
    private var pendingShare: String? = null
    private var dartReady = false

    // YouTube "Share" -> Roxyfy: pull the first link out of the shared text.
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
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "roxyfy/newpipe")
        channel!!.setMethodCallHandler { call, result ->
                if (call.method == "initialShare") {
                    dartReady = true
                    result.success(pendingShare)
                    pendingShare = null
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val out: Any? = when (call.method) {
                            "search" -> search(call.argument<String>("query") ?: "", call.argument<String>("filter") ?: "music_songs")
                            "stream" -> stream(call.argument<String>("url") ?: "")
                            "playlist" -> playlist(call.argument<String>("url") ?: "")
                            "suggest" -> suggest(call.argument<String>("query") ?: "")
                            "artistImage" -> artistImage(call.argument<String>("name") ?: "")
                            "info" -> info(call.argument<String>("url") ?: "")
                            "integrity" -> integrity()
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
        val info = StreamInfo.getInfo(ServiceList.YouTube, url)
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
        if (all2.isEmpty()) throw Exception("No audio stream found")
        return mapOf("sources" to all2)
    }

    // Signing certificate hash + simple debugger / hooking-framework detection.
    @Suppress("DEPRECATION")
    private fun integrity(): Map<String, Any?> {
        var sig = ""
        try {
            val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
            val pi = packageManager.getPackageInfo(packageName, flags)
            val sigs = if (Build.VERSION.SDK_INT >= 28) pi.signingInfo?.apkContentsSigners else pi.signatures
            val first = sigs?.firstOrNull()
            if (first != null) {
                sig = MessageDigest.getInstance("SHA-256").digest(first.toByteArray()).joinToString("") { "%02x".format(it) }
            }
        } catch (_: Throwable) {}
        var tampered = Debug.isDebuggerConnected()
        try {
            val maps = File("/proc/self/maps").readText().lowercase()
            if (maps.contains("frida") || maps.contains("xposed") || maps.contains("substrate")) tampered = true
        } catch (_: Throwable) {}
        return mapOf("sig" to sig, "tampered" to tampered)
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
