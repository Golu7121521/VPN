package com.roxify;

import java.io.UnsupportedEncodingException;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.nio.charset.Charset;

/** Android < 13 lacks URLEncoder/URLDecoder (String, Charset); library jars are redirected here. */
public final class UrlCompat {
    public static String encode(String s, String enc) throws UnsupportedEncodingException {
        return URLEncoder.encode(s, enc);
    }
    public static String encode(String s, Charset c) {
        try { return URLEncoder.encode(s, c.name()); }
        catch (UnsupportedEncodingException e) { throw new RuntimeException(e); }
    }
    public static String encode(String s) {
        return encode(s, Charset.forName("UTF-8"));
    }
    public static String decode(String s, String enc) throws UnsupportedEncodingException {
        return URLDecoder.decode(s, enc);
    }
    public static String decode(String s, Charset c) {
        try { return URLDecoder.decode(s, c.name()); }
        catch (UnsupportedEncodingException e) { throw new RuntimeException(e); }
    }
    public static String decode(String s) {
        return decode(s, Charset.forName("UTF-8"));
    }
}
