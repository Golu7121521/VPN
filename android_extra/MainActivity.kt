package com.example.musify

import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NewPipe.init(DL())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "musify/newpipe")
            .setMethodCallHandler { call, result ->
                Thread {
                    try {
                        val out: Any? = when (call.method) {
                            "search" -> search(call.argument<String>("query") ?: "")
                            "stream" -> stream(call.argument<String>("url") ?: "")
                            else -> null
                        }
                        main.post {
                            if (call.method == "search" || call.method == "stream") result.success(out)
                            else result.notImplemented()
                        }
                    } catch (e: Throwable) {
                        main.post { result.error("NEWPIPE", e.toString(), null) }
                    }
                }.start()
            }
    }

    private fun search(q: String): List<Map<String, Any?>> {
        val yt = ServiceList.YouTube
        val ex = yt.getSearchExtractor(q, listOf("music_songs"), "")
        ex.fetchPage()
        var items = ex.initialPage.items.filterIsInstance<StreamInfoItem>()
        if (items.isEmpty()) {
            val ex2 = yt.getSearchExtractor(q)
            ex2.fetchPage()
            items = ex2.initialPage.items.filterIsInstance<StreamInfoItem>()
        }
        return items.map {
            mapOf(
                "url" to it.url,
                "title" to it.name,
                "artist" to (it.uploaderName ?: ""),
                "thumb" to it.thumbnails.maxByOrNull { x -> x.height }?.url,
                "duration" to it.duration.toInt(),
            )
        }
    }

    private fun stream(url: String): Map<String, Any?> {
        val info = StreamInfo.getInfo(ServiceList.YouTube, url)
        val audio = info.audioStreams
            .filter { it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP }
            .maxByOrNull { it.averageBitrate }
            ?: throw Exception("No audio stream found")
        return mapOf("audio" to audio.content)
    }
}
