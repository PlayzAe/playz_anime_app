import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/stream.dart';
import 'cache.dart';
import 'hls.dart';
import 'log.dart';
import 'net.dart';

/// Desktop Chrome UA, same string the Electron build sends (`http.ts`).
const String kChromeUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36';

/// Turns an episode embed page into a playable HLS stream.
///
/// Port of `src/main/extractor.ts`. The desktop build loads the embed in a
/// hidden BrowserWindow and watches its network requests; here a
/// [HeadlessInAppWebView] does the same job. The embed's own player decrypts
/// its sources and requests the playlist, and we catch that request.
///
/// The embed must be loaded with a Referer (megaplay answers 410 without one)
/// and every segment request must carry the same Referer + Origin.
class StreamResolver {
  StreamResolver._();

  static final StreamResolver i = StreamResolver._();

  final _cache = TtlCache<ResolvedStream>(100);
  final _log = Log('stream');

  static const _ttl = 4 * 60 * 1000;
  static const _resolveTimeout = Duration(seconds: 25);
  static const _graceAfterPlaylist = Duration(milliseconds: 900);
  static const _maxParallel = 2;

  int _running = 0;
  final List<Completer<void>> _waiting = [];

  Future<T> _gate<T>(Future<T> Function() fn) async {
    if (_running >= _maxParallel) {
      final ticket = Completer<void>();
      _waiting.add(ticket);
      await ticket.future;
    }
    _running++;
    try {
      return await fn();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  void clearCache() => _cache.clear();

  /// Headers ExoPlayer must send for every playlist, key and segment request.
  static Map<String, String> headersFor(ResolvedStream s) => {
        'Referer': s.referer,
        'Origin': Uri.parse(s.referer).origin,
        'User-Agent': kChromeUa,
      };

  Future<ResolvedStream> resolve(String embedUrl, {bool force = false}) =>
      _cache.wrap('stream:$embedUrl', _ttl, () => _gate(() => _resolve(embedUrl)), force);

  Future<ResolvedStream> _resolve(String embedUrl) async {
    final started = DateTime.now();
    final referer = '${Uri.parse(embedUrl).origin}/';
    final cap = await _capture(embedUrl, referer);

    // Prefer a master playlist over a media playlist when both were requested.
    final master = cap.playlists.firstWhere(
      (u) => RegExp('master|playlist|index', caseSensitive: false).hasMatch(u),
      orElse: () => cap.playlists.first,
    );

    final sources = cap.getSources == null ? null : await _readSources(cap.getSources!, embedUrl);
    final variants = await masterVariants(master, referer);

    final subtitles = <SubtitleTrack>[];
    final seen = <String>{};
    for (final t in (sources?['tracks'] as List? ?? const [])) {
      if (t is! Map) continue;
      final file = t['file']?.toString();
      final kind = t['kind']?.toString();
      if (file == null || file.isEmpty) continue;
      if (kind != null && kind != 'captions' && kind != 'subtitles') continue;
      final raw = t['label']?.toString().trim() ?? '';
      final generic = raw.isEmpty || const {'subtitles', 'default', 'cc', 'caption'}.contains(raw.toLowerCase());
      subtitles.add(SubtitleTrack(
        label: uniqueLabel(seen, generic ? labelFromUrl(file) : raw),
        url: file,
        isDefault: t['default'] == true,
      ));
    }
    for (final u in cap.subtitles) {
      if (subtitles.any((s) => s.url == u)) continue;
      subtitles.add(SubtitleTrack(label: uniqueLabel(seen, labelFromUrl(u)), url: u));
    }

    _log.info('resolved $embedUrl in ${DateTime.now().difference(started).inMilliseconds}ms '
        '(${variants.length} variants, ${subtitles.length} subs)');

    return ResolvedStream(
      embedUrl: embedUrl,
      master: master,
      referer: referer,
      host: Uri.parse(master).host,
      variants: variants,
      subtitles: subtitles,
      intro: _range(sources?['intro']),
      outro: _range(sources?['outro']),
      resolvedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  // ── Capture ───────────────────────────────────────────────────────────────

  Future<_Captured> _capture(String embedUrl, String referer) async {
    final found = _Captured();
    final done = Completer<_Captured>();
    Timer? grace;
    HeadlessInAppWebView? view;

    void finish([Object? err]) {
      if (done.isCompleted) return;
      grace?.cancel();
      if (err != null) {
        done.completeError(err);
      } else {
        done.complete(found);
      }
    }

    void seen(String u) {
      if (u.contains('ping.gif')) return;
      if (RegExp(r'\.m3u8(\?|$)', caseSensitive: false).hasMatch(u)) {
        if (!found.playlists.contains(u)) found.playlists.add(u);
        grace ??= Timer(_graceAfterPlaylist, finish);
      } else if (RegExp('getSources', caseSensitive: false).hasMatch(u)) {
        found.getSources ??= u;
      } else if (RegExp(r'\.(vtt|srt)(\?|$)', caseSensitive: false).hasMatch(u)) {
        if (!found.subtitles.contains(u)) found.subtitles.add(u);
      }
    }

    view = HeadlessInAppWebView(
      initialSize: const Size(960, 540),
      initialUrlRequest: URLRequest(url: WebUri(embedUrl), headers: {'Referer': referer}),
      initialSettings: InAppWebViewSettings(
        userAgent: kChromeUa,
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        useShouldInterceptRequest: true,
        blockNetworkImage: true,
        supportMultipleWindows: false,
        javaScriptCanOpenWindowsAutomatically: false,
        cacheEnabled: false,
        incognito: true,
      ),
      shouldInterceptRequest: (controller, req) async {
        seen(req.url.toString());
        return null;
      },
      onLoadResource: (controller, res) {
        final u = res.url?.toString();
        if (u != null) seen(u);
      },
      onReceivedError: (controller, req, err) {
        if (req.isForMainFrame == true) finish(StreamException('Embed page failed to load (${err.description}).', embedUrl: embedUrl));
      },
      onReceivedHttpError: (controller, req, res) {
        if (req.isForMainFrame == true && (res.statusCode ?? 200) >= 400) {
          finish(StreamException('The episode host answered ${res.statusCode}. It may have been taken down.', embedUrl: embedUrl));
        }
      },
      onCreateWindow: (controller, action) async => false,
      // MegaPlay answers missing episodes with a 200 page titled "Error - MegaPlay".
      // Fail at once instead of waiting out the timeout.
      onTitleChanged: (controller, title) {
        if (found.playlists.isEmpty && RegExp(r'^\s*(error|404|not found)\b', caseSensitive: false).hasMatch(title ?? '')) {
          finish(StreamException('This episode isn’t on the source yet.', embedUrl: embedUrl));
        }
      },
    );

    final timeout = Timer(_resolveTimeout, () {
      finish(found.playlists.isNotEmpty
          ? null
          : StreamException('The player did not start a stream in time.', embedUrl: embedUrl));
    });

    try {
      await view.run();
      return await done.future;
    } finally {
      timeout.cancel();
      grace?.cancel();
      await view.dispose();
    }
  }

  Future<Map<String, dynamic>?> _readSources(String url, String embedUrl) async {
    try {
      final text = await Net.i.getText(
        url,
        NetOptions(
          headers: {'Referer': embedUrl, 'X-Requested-With': 'XMLHttpRequest', 'User-Agent': kChromeUa},
          timeout: const Duration(seconds: 8),
        ),
      );
      final json = jsonDecode(text);
      return json is Map<String, dynamic> ? json : null;
    } catch (err) {
      _log.debug('getSources failed', err);
      return null;
    }
  }

  // ── Playlist + labels ─────────────────────────────────────────────────────

  Future<List<StreamVariant>> masterVariants(String master, String referer) async {
    final auto = [StreamVariant(label: 'Auto', height: 0, bandwidth: 0, url: master)];
    try {
      final text = await Net.i.getText(
        master,
        NetOptions(
          headers: {'Referer': referer, 'Origin': Uri.parse(referer).origin, 'User-Agent': kChromeUa},
          timeout: const Duration(seconds: 12),
        ),
      );
      final variants = Hls.parseMaster(text, master);
      return variants.isEmpty ? auto : variants;
    } catch (err) {
      _log.warn('master parse failed', err);
      return auto;
    }
  }

  static TimeRange? _range(Object? r) {
    if (r is! Map) return null;
    final s = r['start'], e = r['end'];
    if (s is! num || e is! num || e <= s) return null;
    return TimeRange(start: s.toDouble(), end: e.toDouble());
  }

  static String uniqueLabel(Set<String> seen, String label) {
    final tidy = tidyLabel(label);
    var candidate = tidy;
    var n = 2;
    while (seen.contains(candidate)) {
      candidate = '$tidy ${n++}';
    }
    seen.add(candidate);
    return candidate;
  }

  /// `Portuguese (- Portuguese(Brazil))` → `Portuguese (Brazil)`
  static String tidyLabel(String label) => label
      .replaceAllMapped(RegExp(r'\(\s*-\s*[^()]*\(([^)]+)\)\s*\)'), (m) => '(${m.group(1)})')
      .replaceAllMapped(RegExp(r'\s+-\s+\w+\s*\(([^)]+)\)$'), (m) => ' (${m.group(1)})')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  static const _langs = {
    'eng': 'English', 'en': 'English', 'spa': 'Spanish', 'es': 'Spanish', 'ger': 'German', 'deu': 'German',
    'de': 'German', 'ita': 'Italian', 'it': 'Italian', 'por': 'Portuguese', 'pt': 'Portuguese',
    'rus': 'Russian', 'ru': 'Russian', 'ara': 'Arabic', 'ar': 'Arabic', 'fra': 'French', 'fre': 'French',
    'fr': 'French', 'jpn': 'Japanese', 'ja': 'Japanese', 'ind': 'Indonesian', 'id': 'Indonesian',
    'tha': 'Thai', 'vie': 'Vietnamese', 'may': 'Malay', 'msa': 'Malay',
  };

  static String labelFromUrl(String url) {
    final m = RegExp(r'/([a-z]{2,3})(?:-\d+)?\.(?:vtt|srt)').firstMatch(url.toLowerCase());
    return (m != null ? _langs[m.group(1)] : null) ?? 'English';
  }
}

class _Captured {
  final List<String> playlists = [];
  final List<String> subtitles = [];
  String? getSources;
}

class StreamException implements Exception {
  StreamException(this.message, {this.embedUrl});

  final String message;
  final String? embedUrl;

  @override
  String toString() => message;
}
