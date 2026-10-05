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
import org.schabi.newpipe.extractor.channel.ChannelInfoItem
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.playlist.PlaylistInfo
import org.schabi.newpipe.extractor.playlist.PlaylistInfoItem
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import org.schabi.newpipe.extractor.stream.VideoStream
import java.util.concurrent.TimeUnit

private const val UA =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/128.0.0.0 Safari/537.36"

private const val CHANNEL = "musify/newpipe"

private class MusifyDownloader : Downloader() {

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    override fun execute(request: Request): Response {
        val method = request.httpMethod().uppercase()

        var body = request.dataToSend()?.toRequestBody()

        if (body == null && (method == "POST" || method == "PUT")) {
            body = ByteArray(0).toRequestBody()
        }

        val builder = okhttp3.Request.Builder()
            .url(request.url())
            .method(method, body)
            .header("User-Agent", UA)

        request.headers().forEach { (key, values) ->
            builder.removeHeader(key)

            values.forEach { value ->
                builder.addHeader(key, value)
            }
        }

        client.newCall(builder.build()).execute().use { response ->

            if (response.code == 429) {
                throw ReCaptchaException(
                    "Rate limited",
                    request.url()
                )
            }

            val responseBody = response.body?.string()

            return Response(
                response.code,
                response.message,
                response.headers.toMultimap(),
                responseBody,
                response.request.url.toString()
            )
        }
    }
}

class MainActivity : AudioServiceActivity() {

    private val mainHandler = Handler(Looper.getMainLooper())

    private val supportedMethods = setOf(
        "search",
        "stream",
        "video",
        "playlist",
        "suggest",
        "artistImage"
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        /*
         * Initialize NewPipe once when the Flutter engine starts.
         */
        try {
            NewPipe.init(MusifyDownloader())
        } catch (_: Throwable) {
            // NewPipe may already be initialized.
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            if (call.method !in supportedMethods) {
                result.notImplemented()
                return@setMethodCallHandler
            }

            Thread {
                try {
                    val output: Any? = when (call.method) {

                        "search" -> {
                            val query =
                                call.argument<String>("query") ?: ""

                            val filter =
                                call.argument<String>("filter")
                                    ?: "music_songs"

                            search(query, filter)
                        }

                        "stream" -> {
                            val url =
                                call.argument<String>("url") ?: ""

                            stream(url)
                        }

                        "video" -> {
                            val url =
                                call.argument<String>("url") ?: ""

                            video(url)
                        }

                        "playlist" -> {
                            val url =
                                call.argument<String>("url") ?: ""

                            playlist(url)
                        }

                        "suggest" -> {
                            val query =
                                call.argument<String>("query") ?: ""

                            suggest(query)
                        }

                        "artistImage" -> {
                            val name =
                                call.argument<String>("name") ?: ""

                            artistImage(name)
                        }

                        else -> null
                    }

                    mainHandler.post {
                        result.success(output)
                    }

                } catch (error: Throwable) {

                    mainHandler.post {
                        result.error(
                            "NEWPIPE_ERROR",
                            error.message ?: error.toString(),
                            null
                        )
                    }
                }
            }.start()
        }
    }

    private fun toMap(item: InfoItem): Map<String, Any?>? {

        return when (item) {

            is StreamInfoItem -> {
                mapOf(
                    "type" to "stream",
                    "url" to item.url,
                    "title" to item.name,
                    "artist" to (item.uploaderName ?: ""),
                    "thumb" to item.thumbnails
                        .maxByOrNull { thumbnail ->
                            thumbnail.height
                        }
                        ?.url,
                    "duration" to item.duration.toInt()
                )
            }

            is PlaylistInfoItem -> {
                mapOf(
                    "type" to "playlist",
                    "url" to item.url,
                    "title" to item.name,
                    "artist" to (item.uploaderName ?: ""),
                    "thumb" to item.thumbnails
                        .maxByOrNull { thumbnail ->
                            thumbnail.height
                        }
                        ?.url,
                    "count" to item.streamCount.toInt()
                )
            }

            is ChannelInfoItem -> {
                mapOf(
                    "type" to "channel",
                    "url" to item.url,
                    "title" to item.name,
                    "thumb" to item.thumbnails
                        .maxByOrNull { thumbnail ->
                            thumbnail.height
                        }
                        ?.url
                )
            }

            else -> null
        }
    }

    private fun search(
        query: String,
        filter: String
    ): List<Map<String, Any?>> {

        if (query.isBlank()) {
            return emptyList()
        }

        val youtube = ServiceList.YouTube

        val extractor = youtube.getSearchExtractor(
            query,
            listOf(filter),
            ""
        )

        extractor.fetchPage()

        var items = extractor.initialPage.items

        /*
         * If music_songs returns nothing, fall back to normal
         * YouTube search.
         */
        if (items.isEmpty() && filter == "music_songs") {

            val fallback = youtube.getSearchExtractor(query)

            fallback.fetchPage()

            items = fallback.initialPage.items
        }

        return items.mapNotNull { item ->
            toMap(item)
        }
    }

    private fun playlist(url: String): Map<String, Any?> {

        if (url.isBlank()) {
            throw IllegalArgumentException("Playlist URL is empty")
        }

        val info = PlaylistInfo.getInfo(
            ServiceList.YouTube,
            url
        )

        val items = info.relatedItems
            .filterIsInstance<StreamInfoItem>()
            .mapNotNull { item ->
                toMap(item)
            }

        return mapOf(
            "name" to info.name,
            "artist" to (info.uploaderName ?: ""),
            "thumb" to info.thumbnails
                .maxByOrNull { thumbnail ->
                    thumbnail.height
                }
                ?.url,
            "items" to items
        )
    }

    private fun stream(url: String): Map<String, Any?> {

        if (url.isBlank()) {
            throw IllegalArgumentException("Stream URL is empty")
        }

        val info = StreamInfo.getInfo(
            ServiceList.YouTube,
            url
        )

        val audioStreams = info.audioStreams

        /*
         * Prefer progressive M4A because it is generally easier
         * for Android audio playback.
         */
        val progressive = audioStreams
            .filter { audio ->
                audio.deliveryMethod ==
                    DeliveryMethod.PROGRESSIVE_HTTP
            }
            .sortedWith(
                compareByDescending<AudioStream> { audio ->
                    audio.format == MediaFormat.M4A
                }.thenByDescending { audio ->
                    audio.averageBitrate
                }
            )

        /*
         * HLS/DASH fallback streams.
         */
        val adaptive = audioStreams
            .filter { audio ->
                (
                    audio.deliveryMethod == DeliveryMethod.HLS ||
                        audio.deliveryMethod == DeliveryMethod.DASH
                    ) && audio.isUrl
            }
            .sortedByDescending { audio ->
                audio.averageBitrate
            }

        val sources =
            progressive.map { audio ->
                mapOf(
                    "url" to audio.content,
                    "method" to "progressive"
                )
            } +
            adaptive.map { audio ->
                mapOf(
                    "url" to audio.content,
                    "method" to audio.deliveryMethod
                        .name
                        .lowercase()
                )
            }

        if (sources.isEmpty()) {
            throw IllegalStateException(
                "No audio stream found"
            )
        }

        return mapOf(
            "sources" to sources
        )
    }

    /*
     * Returns a video URL.
     *
     * The Flutter side can use this together with the audio
     * player as the playback clock.
     */
    private fun video(url: String): String? {

        if (url.isBlank()) {
            throw IllegalArgumentException("Video URL is empty")
        }

        val info = StreamInfo.getInfo(
            ServiceList.YouTube,
            url
        )

        /*
         * First preference:
         * progressive video up to 720p.
         */
        val videoOnly = info.videoOnlyStreams
            .filter { video ->
                video.deliveryMethod ==
                    DeliveryMethod.PROGRESSIVE_HTTP &&
                    video.height in 1..720
            }
            .sortedWith(
                compareByDescending<VideoStream> { video ->
                    video.height
                }.thenByDescending { video ->
                    video.format == MediaFormat.MPEG_4
                }
            )
            .firstOrNull()

        if (videoOnly != null) {
            return videoOnly.content
        }

        /*
         * Fallback to progressive video streams.
         */
        return info.videoStreams
            .filter { video ->
                video.deliveryMethod ==
                    DeliveryMethod.PROGRESSIVE_HTTP
            }
            .maxByOrNull { video ->
                video.height
            }
            ?.content
    }

    private fun suggest(query: String): List<String> {

        if (query.isBlank()) {
            return emptyList()
        }

        return ServiceList.YouTube
            .suggestionExtractor
            .suggestionList(query)
    }

    private fun artistImage(name: String): String? {

        if (name.isBlank()) {
            return null
        }

        val extractor = ServiceList.YouTube
            .getSearchExtractor(
                name,
                listOf("music_artists"),
                ""
            )

        extractor.fetchPage()

        val channel = extractor.initialPage.items
            .filterIsInstance<ChannelInfoItem>()
            .firstOrNull()
            ?: return null

        return channel.thumbnails
            .maxByOrNull { thumbnail ->
                thumbnail.height
            }
            ?.url
    }
}