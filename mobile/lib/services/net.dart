import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'cookies.dart';
import 'log.dart';

/// A desktop Chrome user agent. Several providers reject requests that carry a
/// Dart/Flutter UA or no UA at all, and the sites we scrape serve their
/// desktop markup to this string.
///
/// On a phone a mobile UA would be *more* honest, but the scrapers match the
/// desktop DOM, so we keep presenting as desktop Chrome. This is also the UA
/// Mihon uses for its `Mozilla` sources.
const String chromeUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36';

const String mobileUa =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Mobile Safari/537.36';

class HttpError implements Exception {
  HttpError(this.status, this.url, this.body, [this.retryAfter = 0]);

  final int status;
  final String url;
  final String body;

  /// Seconds from a `Retry-After` header, 0 when absent.
  final int retryAfter;

  bool get isRateLimit => status == 429 || status == 503;

  bool get isCloudflare =>
      status == 403 && (body.contains('Just a moment') || body.contains('cf-browser-verification') || body.contains('Attention Required'));

  @override
  String toString() => 'HTTP $status for $url';
}

/// Thrown when a request cannot be made at all (no network, DNS, timeout).
class NetFailure implements Exception {
  NetFailure(this.url, this.cause);

  final String url;
  final Object cause;

  @override
  String toString() => 'Could not reach $url ($cause)';
}

class NetOptions {
  const NetOptions({
    this.headers,
    this.timeout = const Duration(seconds: 15),
    this.method = 'GET',
    this.body,
    this.cancelToken,
    this.userAgent,
    this.referer,
    this.followRedirects = true,
    this.noCookies = false,
  });

  final Map<String, String>? headers;
  final Duration timeout;
  final String method;
  final String? body;
  final CancelToken? cancelToken;
  final String? userAgent;

  /// Set for image CDNs that 403 without it. Usually the source's own base URL.
  final String? referer;
  final bool followRedirects;

  /// True for image fetches that must not carry session cookies across hosts.
  final bool noCookies;
}

/// The app's single HTTP entry point.
///
/// Everything the scrapers do goes through here so that headers, the cookie jar
/// and the retry policy stay in one place — the same job `src/main/http.ts`
/// did in the main process.
class Net {
  Net._();

  static final Net i = Net._();

  late final Dio _dio = _build();
  final CookieJar jar = CookieJar();
  final Log _log = Log('net');

  /// When set, every request is rewritten to go through this prefix.
  ///
  /// This exists for the web build: a browser will not let the app read a
  /// response from a third-party origin that does not send
  /// `Access-Control-Allow-Origin`. Running the same requests through a
  /// permissive proxy is the only way to make the scrapers work in a tab.
  String proxyUrl = '';

  /// Called whenever the jar changes, so the caller can persist it.
  void Function()? onCookiesChanged;

  Dio _build() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 20),
        followRedirects: true,
        maxRedirects: 6,
        validateStatus: (code) => code != null && code < 400,
        responseType: ResponseType.plain,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final ua = options.headers['X-Pz-Ua'] as String? ?? chromeUa;
          options.headers.remove('X-Pz-Ua');
          options.headers['User-Agent'] = ua;
          options.headers['Accept-Language'] = 'en-US,en;q=0.9';
          if (options.headers['Accept'] == null) {
            options.headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8';
          }

          final referer = options.headers.remove('X-Pz-Referer') as String?;
          if (referer != null) options.headers['Referer'] = referer;

          if (options.extra['noCookies'] != true) {
            final cookie = jar.headerFor(options.uri.toString());
            if (cookie != null) options.headers['Cookie'] = cookie;
          }

          if (proxyUrl.isNotEmpty && !options.uri.toString().startsWith(proxyUrl)) {
            final target = options.uri.toString();
            options.path = '$proxyUrl$target';
            options.extra['proxied'] = target;
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          if (response.extra['noCookies'] != true) {
            _absorb(response.headers.map.map((k, v) => MapEntry(k, v)), response.realUri.toString());
          }
          handler.next(response);
        },
        onError: (err, handler) {
          final res = err.response;
          if (res != null) {
            _absorb(res.headers.map.map((k, v) => MapEntry(k, v)), res.realUri.toString());
            handler.next(
              DioException(
                requestOptions: err.requestOptions,
                response: res,
                type: err.type,
                error: HttpError(
                  res.statusCode ?? 0,
                  err.requestOptions.uri.toString(),
                  _errorSnippet(res.data),
                  int.tryParse(res.headers.value('retry-after') ?? '') ?? 0,
                ),
              ),
            );
          } else {
            handler.next(err);
          }
        },
      ),
    );

    return dio;
  }

  void _absorb(Map<String, List<String>> headers, String url) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'set-cookie') {
        jar.absorb(url, entry.value);
        onCookiesChanged?.call();
      }
    }
  }

  static String _bodyString(Object? data) {
    if (data == null) return '';
    return data is String ? data : data.toString();
  }

  static String _errorSnippet(Object? data, [int max = 2000]) {
    final s = _bodyString(data);
    return s.length > max ? s.substring(0, max) : s;
  }

  // ── Requests ──────────────────────────────────────────────────────────────

  Future<Response<dynamic>> request(String url, [NetOptions opts = const NetOptions()]) async {
    try {
      return await _dio.request<dynamic>(
        url,
        data: opts.body,
        cancelToken: opts.cancelToken,
        options: Options(
          method: opts.method,
          followRedirects: opts.followRedirects,
          receiveTimeout: opts.timeout,
          sendTimeout: opts.timeout,
          headers: {
            ...?opts.headers,
            if (opts.userAgent != null) 'X-Pz-Ua': opts.userAgent!,
            if (opts.referer != null) 'X-Pz-Referer': opts.referer!,
          },
          extra: {if (opts.noCookies) 'noCookies': true},
        ),
      );
    } on DioException catch (e) {
      final mapped = e.error;
      if (mapped is HttpError) throw mapped;
      throw NetFailure(url, e.type == DioExceptionType.cancel ? 'cancelled' : (e.message ?? e.type.name));
    }
  }

  Future<String> getText(String url, [NetOptions opts = const NetOptions()]) async {
    final res = await request(url, opts);
    return _bodyString(res.data);
  }

  Future<Map<String, dynamic>> getJson(String url, [NetOptions opts = const NetOptions()]) async {
    final text = await getText(
      url,
      NetOptions(
        headers: {...?opts.headers, 'Accept': 'application/json, text/plain, */*'},
        timeout: opts.timeout,
        cancelToken: opts.cancelToken,
        userAgent: opts.userAgent,
        referer: opts.referer,
        noCookies: opts.noCookies,
      ),
    );
    final decoded = jsonDecode(text);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw FormatException('Expected a JSON object from $url');
  }

  /// POSTs a GraphQL document and returns the `data` object.
  Future<Map<String, dynamic>> postJson(
    String url,
    Object payload, [
    NetOptions opts = const NetOptions(),
  ]) async {
    final res = await request(
      url,
      NetOptions(
        method: 'POST',
        body: jsonEncode(payload),
        timeout: opts.timeout,
        cancelToken: opts.cancelToken,
        headers: {...?opts.headers, 'Content-Type': 'application/json', 'Accept': 'application/json'},
      ),
    );
    final text = _bodyString(res.data);
    final decoded = jsonDecode(text);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw FormatException('Expected a JSON object from $url');
  }

  Future<Uint8List> getBytes(String url, [NetOptions opts = const NetOptions()]) async {
    final res = await _dio.request<List<int>>(
      url,
      cancelToken: opts.cancelToken,
      options: Options(
        method: opts.method,
        responseType: ResponseType.bytes,
        headers: {
          'User-Agent': opts.userAgent ?? chromeUa,
          ...?opts.headers,
          if (opts.referer != null) 'Referer': opts.referer!,
        },
        extra: {if (opts.noCookies) 'noCookies': true},
        receiveTimeout: opts.timeout,
        followRedirects: opts.followRedirects,
      ),
    );
    final data = res.data ?? const <int>[];
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  /// Streams a URL to disk with progress. Used by the download queue.
  Future<Response<dynamic>> download(
    String url,
    String savePath, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
    Map<String, String>? headers,
    String? referer,
    bool resume = false,
  }) async {
    var startAt = 0;
    if (resume && !kIsWeb) {
      startAt = await _fileLength(savePath);
    }
    return _dio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      deleteOnError: false,
      onReceiveProgress: onProgress,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'User-Agent': chromeUa,
          ...?headers,
          'Referer': ?referer,
          if (startAt > 0) 'Range': 'bytes=$startAt-',
        },
      ),
    );
  }

  static Future<int> _fileLength(String path) async {
    try {
      // Avoids importing dart:io at the top level so the web build still compiles.
      // ignore: avoid_dynamic_calls
      return await _lengthViaIO(path);
    } catch (_) {
      return 0;
    }
  }

  // ── Retry ─────────────────────────────────────────────────────────────────

  /// Retries transient failures (network errors, 429, 5xx).
  ///
  /// "Too many requests" gets a real pause: the server's `Retry-After`, else an
  /// exponential wait up to 30 s, because hammering a rate-limited CDN only
  /// extends the ban. Ported from `retry()` in `src/main/http.ts`.
  Future<T> retry<T>(
    Future<T> Function() fn, {
    int attempts = 3,
    CancelToken? cancelToken,
    void Function()? onRateLimit,
  }) async {
    Object? last;
    for (var i = 0; i < attempts; i++) {
      if (cancelToken?.isCancelled ?? false) throw const _Cancelled();
      try {
        return await fn();
      } catch (err) {
        last = err;
        if (cancelToken?.isCancelled ?? false) rethrow;
        if (err is FormatException || err is TypeError || err is ArgumentError) rethrow;
        final status = err is HttpError ? err.status : 0;
        if (status != 0 && status < 500 && status != 429) rethrow;
        if (i == attempts - 1) break;

        var waitMs = 400 * (i + 1) * (i + 1);
        if (status == 429 || status == 503) {
          onRateLimit?.call();
          final after = err is HttpError ? err.retryAfter * 1000 : 0;
          final exponential = 1500 * (1 << i);
          waitMs = (after != 0 ? (after < 30000 ? after : 30000) : (exponential < 30000 ? exponential : 30000)) +
              (DateTime.now().microsecondsSinceEpoch % 500);
        }
        _log.debug('retry ${i + 1}/$attempts in ${waitMs}ms (status $status)');
        await Future<void>.delayed(Duration(milliseconds: waitMs));
      }
    }
    throw last!;
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Overridden per platform in `net_io.dart` / `net_web.dart` so `dart:io` never
/// reaches the web compiler.
Future<int> Function(String path) _lengthViaIO = _noLength;

Future<int> _noLength(String path) async => 0;

/// Wires the platform-specific file-length probe. Called from `main()` before
/// anything downloads.
void installPlatformProbes({required Future<int> Function(String path) fileLength}) {
  _lengthViaIO = fileLength;
}
