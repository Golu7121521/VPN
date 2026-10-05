package com.example.musify;

import java.io.UnsupportedEncodingException;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;

/**
 * Compatibility wrapper for URL encoding/decoding.
 *
 * Some Android/library combinations reference the
 * Charset-based URLEncoder/URLDecoder APIs. These wrappers
 * keep compatibility with older Android API levels.
 */
public final class UrlCompat {

    private UrlCompat() {
        // Utility class.
    }

    public static String encode(
            String value,
            String encoding
    ) throws UnsupportedEncodingException {

        return URLEncoder.encode(value, encoding);
    }

    public static String encode(
            String value,
            Charset charset
    ) {

        try {
            return URLEncoder.encode(
                    value,
                    charset.name()
            );
        } catch (UnsupportedEncodingException e) {
            throw new RuntimeException(e);
        }
    }

    public static String encode(String value) {

        return encode(
                value,
                StandardCharsets.UTF_8
        );
    }

    public static String decode(
            String value,
            String encoding
    ) throws UnsupportedEncodingException {

        return URLDecoder.decode(
                value,
                encoding
        );
    }

    public static String decode(
            String value,
            Charset charset
    ) {

        try {
            return URLDecoder.decode(
                    value,
                    charset.name()
            );
        } catch (UnsupportedEncodingException e) {
            throw new RuntimeException(e);
        }
    }

    public static String decode(String value) {

        return decode(
                value,
                StandardCharsets.UTF_8
        );
    }
}