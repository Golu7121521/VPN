package com.example.musify

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
    private val known = listOf("search", "stream", "video", "playlist", "suggest", "artistImage")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NewPipe.init(DL())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "musify/newpipe")
            .setMethodCallHandler { call, result ->
                Thread {
                    try {
                        val out: Any? = when (call.method) {
                            "search" -> search(call.argument<String>("query") ?: "", call.argument<String>("filter") ?: "music_songs")
                            "stream" -> stream(call.argument<String>("url") ?: "")
                            "video" -> video(call.argument<String>("url") ?: "")
                            "playlist" -> playlist(call.argument<String>("url") ?: "")
                            "suggest" -> suggest(call.argument<String>("query") ?: "")
                            "artistImage" -> artistImage(call.argument<String>("name") ?: "")
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
        if (sources.isEmpty()) throw Exception("No audio stream found")
        return mapOf("sources" to sources)
    }

    // Video-only stream (the app mutes it and keeps the audio player as the clock).
    private fun video(url: String): String? {
        val info = StreamInfo.getInfo(ServiceList.YouTube, url)
        val best = info.videoOnlyStreams
            .filter { it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP && it.height in 1..720 }
            .sortedWith(
                compareByDescending<VideoStream> { it.height }.thenByDescending { it.format == MediaFormat.MPEG_4 }
            ).firstOrNull()
        if (best != null) return best.content
        return info.videoStreams.filter { it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP }
            .maxByOrNull { it.height }?.content
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
