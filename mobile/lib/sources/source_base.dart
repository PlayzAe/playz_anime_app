import 'package:html/dom.dart' as dom;

import '../models/manga.dart';
import '../services/cache.dart';
import '../services/log.dart';
import '../services/net.dart';
import 'html_util.dart';

/// The shared plumbing every source needs: cached fetches, a consistent UA and
/// Referer, and the small conveniences the engines would otherwise repeat.
///
/// This is the Dart equivalent of Tachiyomi's `HttpSource`. Every engine
/// (`MadaraEngine`, `MangaStreamEngine`, …) extends it, and so does every
/// bespoke source, so the download queue and the detail screens only ever talk
/// to [MangaSource].
abstract class HttpSource implements MangaSource {
  HttpSource({this.userAgent = chromeUa, this.refererMode = RefererMode.base});

  @override
  String get baseUrl;

  /// Most sites serve the same markup to a browser and a bot; a few sniff.
  final String userAgent;

  /// Whether image and page requests should carry the source's own origin.
  ///
  /// Almost all CDNs 403 without it. A handful reject a same-origin Referer
  /// because they sit behind a different domain, hence the switch.
  final RefererMode refererMode;

  final _cache = TtlCache<Object>(60);
  final log = Log('source');

  /// Page fetches are cheap to repeat but not free; 5 minutes keeps a reader
  /// paging back and forth off the network.
  static const int pageTtl = 5 * 60 * 1000;
  static const int listTtl = 10 * 60 * 1000;

  String get _referer => switch (refererMode) {
    RefererMode.base => baseUrl,
    RefererMode.none => '',
    RefererMode.custom => refererUrlOverride ?? baseUrl,
  };

  String? refererUrlOverride;

  Map<String, String> headers({String? referer}) => {
    if ((referer ?? _referer).isNotEmpty) 'Referer': referer ?? _referer,
  };

  // ── Fetching ──────────────────────────────────────────────────────────────

  Future<dom.Document> doc(String url, {String? referer, bool force = false}) async {
    final html = await body(url, referer: referer, force: force);
    return H.parse(html);
  }

  Future<String> body(String url, {String? referer, bool force = false, int ttl = pageTtl}) async {
    final key = 'body:$url';
    if (force) _cache.clear();
    return _cache.wrap(key, ttl, () async {
      final text = await Net.i.getText(
        url,
        NetOptions(headers: headers(referer: referer), userAgent: userAgent, referer: _effective(referer)),
      );
      if (_looksBlocked(text)) {
        throw HttpError(403, url, text.substring(0, text.length.clamp(0, 400)));
      }
      return text;
    }, force);
  }

  String? _effective(String? referer) {
    final r = referer ?? _referer;
    return r.isEmpty ? null : r;
  }

  /// Cloudflare's interstitial and the common "enable JavaScript" walls.
  ///
  /// Detecting them here means a source fails loudly with a useful message
  /// instead of silently returning zero chapters.
  static bool _looksBlocked(String body) {
    if (body.length > 60000) return false; // a real page, whatever it contains
    final head = body.length > 4000 ? body.substring(0, 4000) : body;
    final lower = head.toLowerCase();
    return lower.contains('just a moment') ||
        lower.contains('cf-browser-verification') ||
        lower.contains('attention required') ||
        lower.contains('enable javascript and cookies to continue') ||
        lower.contains('checking your browser before accessing');
  }

  /// Fetches bytes with the source's Referer, for page images the reader
  /// downloads directly.
  Future<List<int>> bytes(String url, {String? referer}) async {
    final data = await Net.i.getBytes(
      url,
      NetOptions(headers: headers(referer: referer), referer: _effective(referer), userAgent: userAgent),
    );
    return data;
  }

  // ── Liveness ──────────────────────────────────────────────────────────────

  @override
  Future<bool> ping() async {
    try {
      final text = await body(baseUrl, force: true, ttl: 0);
      return text.length > 500;
    } catch (err) {
      log.debug('ping failed for $id', err);
      return false;
    }
  }

  // ── Helpers the engines lean on ───────────────────────────────────────────

  /// Turns an anchor into an [SManga], leaving detail fields blank.
  SManga mangaFromAnchor(dom.Element a, {String? titleSel, String? imgSel}) => SManga(
    url: H.absolute(a.attributes['href'], baseUrl),
    title: H.decodeEntities(H.text(a, titleSel ?? '.post-title, .entry-title, .manga-title, h3, h4') ?? a.text.trim()),
    thumbnail: H.absolute(H.img(H.first(a, imgSel ?? 'img')), baseUrl),
  );

  /// Sorts a chapter list newest-first, the way every reader screen shows it.
  ///
  /// Sources are wildly inconsistent: some list oldest-first, some interleave
  /// specials, and the number is sometimes only in the label. Sorting on the
  /// parsed number and falling back to source order keeps it stable.
  static List<SChapter> sortChapters(List<SChapter> chapters, {bool descending = true}) {
    final indexed = <({SChapter chapter, int index})>[];
    for (var i = 0; i < chapters.length; i++) {
      indexed.add((chapter: chapters[i], index: i));
    }
    indexed.sort((a, b) {
      final ka = _keyOf(a.chapter);
      final kb = _keyOf(b.chapter);
      if (ka != kb) return descending ? kb.compareTo(ka) : ka.compareTo(kb);
      // Same number: keep the source's order so a re-fetch is not shuffled.
      return a.index.compareTo(b.index);
    });
    return [for (final e in indexed) e.chapter];
  }

  static double _keyOf(SChapter c) {
    final raw = c.chapterNumber ?? c.name;
    return H.chapterSortKey(raw);
  }

  @override
  List<SourceFilter> get filters => const [];

  @override
  set appliedFilters(List<SourceFilter> value) {}

  @override
  bool get enabled => true;

  @override
  bool get cloudflareGated => false;
}

enum RefererMode {
  /// Send the source's own origin — the default, and what most CDNs expect.
  base,

  /// Send nothing. Some image hosts reject a cross-origin Referer outright.
  none,

  /// Send [HttpSource.refererUrlOverride].
  custom,
}
