import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../services/log.dart';
import '../../services/native.dart';
import '../../services/net.dart';
import '../../services/prefs.dart';
import '../../services/store.dart';
import 'providers.dart' show MChapter, MPage, decodeEntities;

/// Mihon extensions, run for real.
///
/// The repo index is read exactly like Mihon reads it, and installing downloads
/// the extension APK and loads it in the native host (`ExtHost.kt`), so any
/// keiyoushi extension works — not just a few site themes. Hundreds can be
/// installed: their code is only loaded when one of their sources is used.

const kDefaultRepo = 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json';

/// Offered on the one-time setup and on the Extensions screen: big, reliable
/// English sources that cover most manga, manhwa and manhua between them.
const kRecommended = [
  'eu.kanade.tachiyomi.extension.en.asurascans',
  'eu.kanade.tachiyomi.extension.en.weebcentral',
  'eu.kanade.tachiyomi.extension.all.mangafire',
  'eu.kanade.tachiyomi.extension.en.manganelo',
  'eu.kanade.tachiyomi.extension.en.mangakakalot',
  'eu.kanade.tachiyomi.extension.en.flamecomics',
  'eu.kanade.tachiyomi.extension.en.manhuaus',
  'eu.kanade.tachiyomi.extension.en.comix',
  'eu.kanade.tachiyomi.extension.en.arvenscans',
  'eu.kanade.tachiyomi.extension.all.kagane',
];

enum ContentWarning { safe, mixed, nsfw }

class ExtSource {
  const ExtSource({required this.id, required this.name, required this.lang, required this.baseUrl});

  final String id;
  final String name;
  final String lang;
  final String baseUrl;
}

/// One entry of a repo index.
class Extension {
  const Extension({
    required this.name,
    required this.pkg,
    required this.version,
    required this.versionCode,
    required this.lang,
    required this.warning,
    this.icon,
    required this.apkUrl,
    required this.sources,
    required this.repo,
  });

  final String name;
  final String pkg;
  final String version;
  final int versionCode;
  final String lang;
  final ContentWarning warning;
  final String? icon;
  final String apkUrl;
  final List<ExtSource> sources;
  final String repo;

  bool get nsfw => warning == ContentWarning.nsfw;
}

/// One installed source (an extension can carry several, e.g. one per language).
class InstalledSource {
  const InstalledSource({
    required this.id,
    required this.name,
    required this.lang,
    required this.baseUrl,
    required this.pkg,
    required this.nsfw,
    required this.supportsLatest,
    this.icon,
  });

  final String id;
  final String name;
  final String lang;
  final String baseUrl;
  final String pkg;
  final bool nsfw;
  final bool supportsLatest;
  final String? icon;

  /// Provider id used in chapter ids and the auto-pick table. No colons.
  String get provider => 'x$id';
}

/// An installed package as the native host reports it.
class InstalledExt {
  const InstalledExt({required this.pkg, required this.name, required this.version, required this.versionCode, required this.nsfw, required this.sources});

  final String pkg;
  final String name;
  final String version;
  final int versionCode;
  final bool nsfw;
  final List<InstalledSource> sources;
}

class SManga {
  const SManga({required this.url, required this.title, this.thumbnail, this.description, this.author, this.genre, this.status});

  final String url;
  final String title;
  final String? thumbnail;
  final String? description;
  final String? author;
  final String? genre;
  final int? status;

  factory SManga.fromMap(Map m) => SManga(
        url: '${m['url']}',
        title: decodeEntities('${m['title'] ?? ''}'),
        thumbnail: (m['thumbnail'] as String?)?.trim().isEmpty == true ? null : m['thumbnail'] as String?,
        description: m['description'] as String?,
        author: m['author'] as String?,
        genre: m['genre'] as String?,
        status: m['status'] as int?,
      );
}

class Extensions extends ChangeNotifier {
  Extensions._() {
    final saved = Prefs.i.getJson('ext.v2');
    _repos = [...((saved?['repos'] as List?)?.map((e) => '$e') ?? const [kDefaultRepo])];
    _icons.addAll(((saved?['icons'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v')));
    _warnings.addAll(((saved?['warnings'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v')));
    _lastCheck = (saved?['lastCheck'] as int?) ?? 0;
    autoUpdate = saved?['autoUpdate'] as bool? ?? true;
    setupDone = saved?['setupDone'] as bool? ?? false;
  }

  static final Extensions i = Extensions._();
  final _log = Log('extensions');

  late List<String> _repos;
  final Map<String, String> _icons = {};

  /// pkg → repo content rating (safe / mixed / nsfw), kept from install time so
  /// "Hide adult content" works before the repo index is loaded.
  final Map<String, String> _warnings = {};
  final Map<String, InstalledExt> _installed = {};
  List<Extension>? _catalogue;
  int _lastCheck = 0;
  bool autoUpdate = true;
  bool setupDone = false;

  /// pkg → progress text while installing/updating, for the buttons.
  final Map<String, String> busy = {};
  /// pkg → last install error.
  final Map<String, String> errors = {};

  List<String> get repos => List.unmodifiable(_repos);
  List<Extension>? get catalogue => _catalogue;
  bool get hideAdult => Store.i.settings.hideAdult;

  /// Installed packages the user can currently see (NSFW ones hide with "Hide adult").
  List<InstalledExt> get packages => [for (final e in _installed.values) if (!(hideAdult && _isNsfw(e.pkg, e.nsfw))) e];

  /// Every runnable source, NSFW filtered the same way.
  List<InstalledSource> get installed => [for (final e in packages) ...e.sources];

  /// Sources used for search and auto-matching: the user's languages only.
  List<InstalledSource> get searchable => installed.where((s) => s.lang == 'en' || s.lang == 'all').toList();

  bool isInstalled(String pkg) => _installed.containsKey(pkg);
  InstalledExt? package(String pkg) => _installed[pkg];

  InstalledSource? byProvider(String provider) {
    final id = provider.startsWith('x') ? provider.substring(1) : provider;
    for (final e in _installed.values) {
      for (final s in e.sources) {
        if (s.id == id) return s;
      }
    }
    return null;
  }

  /// The repo entry that provides source [id] (to offer a reinstall).
  Extension? extensionForSource(String id) {
    final raw = id.startsWith('x') ? id.substring(1) : id;
    return _catalogue?.where((e) => e.sources.any((s) => s.id == raw)).firstOrNull;
  }

  /// Only extensions the repo rates NSFW hide with "Hide adult content".
  /// Mixed sites (MangaFire, Weeb Central…) carry mainstream titles and stay.
  /// The APK's own nsfw flag is the fallback when the repo rating is unknown,
  /// because older extensions set it for mixed sites too.
  bool _isNsfw(String pkg, bool flag) {
    final known = _warnings[pkg] ?? _catalogue?.where((e) => e.pkg == pkg).firstOrNull?.warning.name;
    return known != null ? known == ContentWarning.nsfw.name : flag;
  }

  bool isNsfw(String pkg) => _isNsfw(pkg, _installed[pkg]?.nsfw ?? false);

  Extension? _entry(String pkg) => _catalogue?.where((e) => e.pkg == pkg).firstOrNull;

  bool hasUpdate(String pkg) {
    final have = _installed[pkg];
    final repo = _entry(pkg);
    return have != null && repo != null && repo.versionCode > have.versionCode;
  }

  List<Extension> get updates => [
        for (final e in _catalogue ?? const <Extension>[])
          if (hasUpdate(e.pkg)) e,
      ];

  void _persist() {
    Prefs.i.setJson('ext.v2', {
      'repos': _repos,
      'icons': _icons,
      'warnings': _warnings,
      'lastCheck': _lastCheck,
      'autoUpdate': autoUpdate,
      'setupDone': setupDone,
    });
    notifyListeners();
  }

  void setAutoUpdate(bool on) {
    autoUpdate = on;
    _persist();
  }

  void markSetupDone() {
    setupDone = true;
    _persist();
  }

  /// Reloads what the native host has installed.
  Future<void> refresh() async {
    if (!Native.available) return;
    try {
      final list = await Native.ext<List>('installed');
      _installed
        ..clear()
        ..addEntries(list.cast<Map>().map((m) {
          final e = _parseInstalled(m);
          return MapEntry(e.pkg, e);
        }));
      notifyListeners();
      // Ratings missing (installed by an older build): read the repo once.
      if (_installed.keys.any((p) => !_warnings.containsKey(p)) && _catalogue == null) {
        unawaited(load().then((_) {}, onError: (_) {}));
      }
    } catch (e) {
      _log.warn('installed failed', e);
    }
  }

  InstalledExt _parseInstalled(Map m) {
    final pkg = '${m['pkg']}';
    final nsfw = m['nsfw'] == true;
    return InstalledExt(
      pkg: pkg,
      name: '${m['name']}',
      version: '${m['version']}',
      versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
      nsfw: nsfw,
      sources: [
        for (final s in (m['sources'] as List? ?? const []).cast<Map>())
          InstalledSource(
            id: '${s['id']}',
            name: '${s['name']}',
            lang: '${s['lang']}',
            baseUrl: '${s['baseUrl'] ?? ''}',
            pkg: pkg,
            nsfw: _isNsfw(pkg, nsfw),
            supportsLatest: s['supportsLatest'] == true,
            icon: _icons[pkg],
          ),
      ],
    );
  }

  void addRepo(String url) {
    var u = url.trim();
    if (u.isEmpty || _repos.contains(u)) return;
    if (!u.endsWith('.json')) u = '${u.replaceAll(RegExp(r'/+$'), '')}/index.json';
    _repos.add(u);
    _catalogue = null;
    _persist();
  }

  void removeRepo(String url) {
    _repos.remove(url);
    _catalogue = null;
    _persist();
  }

  /// Reads every repo index (Mihon index v2 `index.json`, or the legacy
  /// `index.min.json` array).
  Future<List<Extension>> load({bool force = false}) async {
    if (_catalogue != null && !force) return _catalogue!;
    final out = <Extension>[];
    for (final repo in _repos) {
      try {
        final raw = jsonDecode(await Net.i.getText(repo, const NetOptions(timeout: Duration(seconds: 30))));
        out.addAll(parseRepo(raw, repo));
      } catch (err) {
        _log.warn('repo $repo failed', err);
      }
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _catalogue = out;
    // Backfill ratings and icons for extensions installed before they were recorded.
    var changed = false;
    for (final e in out) {
      if (!_installed.containsKey(e.pkg)) continue;
      if (_warnings[e.pkg] != e.warning.name) {
        _warnings[e.pkg] = e.warning.name;
        changed = true;
      }
      if (e.icon != null && _icons[e.pkg] == null) {
        _icons[e.pkg] = e.icon!;
        changed = true;
      }
    }
    if (changed) {
      final again = [for (final x in _installed.values) x];
      for (final x in again) {
        _installed[x.pkg] = InstalledExt(
          pkg: x.pkg,
          name: x.name,
          version: x.version,
          versionCode: x.versionCode,
          nsfw: x.nsfw,
          sources: [
            for (final src in x.sources)
              InstalledSource(
                id: src.id,
                name: src.name,
                lang: src.lang,
                baseUrl: src.baseUrl,
                pkg: src.pkg,
                nsfw: _isNsfw(x.pkg, x.nsfw),
                supportsLatest: src.supportsLatest,
                icon: _icons[x.pkg],
              ),
          ],
        );
      }
      _persist();
    }
    notifyListeners();
    return out;
  }

  // ── Install, update, remove ───────────────────────────────────────────────

  /// Installs (or updates) one extension. Returns null on success, else a reason.
  Future<String?> install(Extension e) async {
    if (busy.containsKey(e.pkg)) return null;
    busy[e.pkg] = isInstalled(e.pkg) ? 'Updating' : 'Installing';
    errors.remove(e.pkg);
    notifyListeners();
    try {
      final m = await Native.ext<Map>('install', {'url': e.apkUrl, 'pkg': e.pkg});
      final got = _parseInstalled(m);
      if (e.icon != null) _icons[got.pkg] = e.icon!;
      _warnings[got.pkg] = e.warning.name;
      _installed[got.pkg] = _parseInstalled(m);
      _persist();
      return null;
    } catch (err) {
      final msg = '$err';
      errors[e.pkg] = msg;
      _log.warn('install ${e.pkg} failed', err);
      return msg;
    } finally {
      busy.remove(e.pkg);
      notifyListeners();
    }
  }

  /// Installs several at once, three in parallel. [onProgress] gets (done, total).
  Future<int> installMany(List<Extension> list, {void Function(int done, int total)? onProgress}) async {
    var done = 0;
    var ok = 0;
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < list.length) {
        final e = list[cursor++];
        if (await install(e) == null) ok++;
        done++;
        onProgress?.call(done, list.length);
      }
    }

    await Future.wait([for (var w = 0; w < 3; w++) worker()]);
    return ok;
  }

  Future<int> updateAll() => installMany(updates);

  Future<void> uninstall(String pkg) async {
    try {
      await Native.ext<void>('uninstall', {'pkg': pkg});
    } catch (_) {}
    _installed.remove(pkg);
    _persist();
  }

  /// Once a day: refresh the repo and update installed extensions (if allowed).
  Future<void> dailyCheck() async {
    await refresh();
    if (_installed.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCheck < const Duration(hours: 20).inMilliseconds) return;
    _lastCheck = now;
    _persist();
    await load(force: true);
    if (autoUpdate && updates.isNotEmpty) {
      final n = await updateAll();
      _log.info('auto-updated $n extensions');
    }
  }

  // ── Running a source ──────────────────────────────────────────────────────

  Future<({List<SManga> items, bool hasNext})> _page(String method, InstalledSource s, int page, [String? q]) async {
    final m = await Native.ext<Map>(method, {'id': s.id, 'page': page, 'query': ?q});
    return (
      items: [for (final x in (m['mangas'] as List? ?? const []).cast<Map>()) SManga.fromMap(x)],
      hasNext: m['hasNextPage'] == true,
    );
  }

  Future<List<SManga>> popular(InstalledSource s, int page) async => (await _page('popular', s, page)).items;

  Future<List<SManga>> latest(InstalledSource s, int page) async =>
      (await _page(s.supportsLatest ? 'latest' : 'popular', s, page)).items;

  Future<List<SManga>> search(InstalledSource s, String q, int page) async => (await _page('search', s, page, q)).items;

  Future<SManga> details(InstalledSource s, SManga m) async {
    final d = SManga.fromMap(await Native.ext<Map>('details', {'id': s.id, 'url': m.url, 'title': m.title}));
    return SManga(
      url: m.url,
      title: d.title.isEmpty ? m.title : d.title,
      thumbnail: d.thumbnail ?? m.thumbnail,
      description: d.description,
      author: d.author,
      genre: d.genre,
      status: d.status,
    );
  }

  /// Details and chapters together (one request to the extension).
  Future<({SManga manga, List<MChapter> chapters})> update(InstalledSource s, SManga m) async {
    final r = await Native.ext<Map>('update', {'id': s.id, 'url': m.url, 'title': m.title});
    final d = r['manga'] is Map ? SManga.fromMap(r['manga'] as Map) : m;
    return (
      manga: SManga(
        url: m.url,
        title: d.title.isEmpty ? m.title : d.title,
        thumbnail: d.thumbnail ?? m.thumbnail,
        description: d.description,
        author: d.author,
        genre: d.genre,
        status: d.status,
      ),
      chapters: _chapterList(s, (r['chapters'] as List? ?? const []).cast<Map>()),
    );
  }

  Future<List<MChapter>> chapters(InstalledSource s, String mangaUrl, {String? title}) async {
    final list = await Native.ext<List>('chapters', {'id': s.id, 'url': mangaUrl, 'title': title});
    return _chapterList(s, list.cast<Map>());
  }

  List<MChapter> _chapterList(InstalledSource s, List<Map> list) {
    final out = [
      for (final c in list)
        MChapter(
          id: '${s.provider}:${c['url']}',
          provider: s.provider,
          number: chapterNumber((c['number'] as num?)?.toDouble(), '${c['name'] ?? ''}'),
          title: _chapterTitle('${c['name'] ?? ''}'),
          group: (c['scanlator'] as String?)?.trim().isEmpty == true ? null : c['scanlator'] as String?,
          publishedAt: (c['date'] as num?)?.toInt() == 0 ? null : (c['date'] as num?)?.toInt(),
        ),
    ];
    // Sources list newest first; the app wants oldest first.
    out.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return out;
  }

  Future<List<MPage>> pages(InstalledSource s, String chapterUrl) async {
    final list = await Native.ext<List>('pages', {'id': s.id, 'url': chapterUrl});
    return [
      for (final p in list.cast<Map>())
        MPage(
          '${p['imageUrl'] ?? p['url'] ?? ''}',
          ext: s.id,
          index: (p['index'] as num?)?.toInt() ?? 0,
          pageUrl: p['url'] as String?,
          imageUrl: p['imageUrl'] as String?,
        ),
    ];
  }

  /// A page image as a local file, fetched through the extension.
  Future<String> image(MPage p) => Native.ext<String>('image', {'id': p.ext, 'index': p.index, 'url': p.pageUrl, 'imageUrl': p.imageUrl});

  /// A cover image as a local file, fetched with the source's headers.
  Future<String> cover(String sourceId, String url) => Native.ext<String>('fetch', {'id': sourceId, 'url': url});
}

/// Parses a repo index (v2 object or legacy array). Pure, unit tested.
List<Extension> parseRepo(Object? raw, String repo) {
  final list = raw is Map ? (raw['extensionList']?['extensions'] as List? ?? const []) : (raw as List? ?? const []);
  final base = repo.substring(0, repo.lastIndexOf('/') + 1);
  final out = <Extension>[];
  for (final e in list.cast<Map>()) {
    final pkg = '${e['packageName'] ?? e['pkg']}';
    final res = e['resources'] as Map?;
    final apk = res?['apkUrl']?.toString() ?? (e['apk'] != null ? '${base}apk/${e['apk']}' : '');
    if (apk.isEmpty) continue;
    final sources = [
      for (final s in (e['sources'] as List? ?? const []).cast<Map>())
        ExtSource(
          id: '${s['id']}',
          name: '${s['name']}',
          lang: '${s['language'] ?? s['lang'] ?? ''}',
          baseUrl: '${s['homeUrl'] ?? s['baseUrl'] ?? ''}',
        ),
    ];
    final cw = '${e['contentWarning'] ?? ''}';
    final langFromPkg = RegExp(r'\.extension\.([a-z-]+)\.').firstMatch(pkg)?.group(1) ?? '';
    out.add(Extension(
      name: '${e['name']}'.replaceFirst('Tachiyomi: ', ''),
      pkg: pkg,
      version: '${e['versionName'] ?? e['version'] ?? ''}',
      versionCode: int.tryParse('${e['versionCode'] ?? e['code'] ?? 0}') ?? 0,
      lang: sources.isNotEmpty && sources.first.lang.isNotEmpty ? sources.first.lang : langFromPkg,
      warning: cw.contains('NSFW') || e['nsfw'] == 1
          ? ContentWarning.nsfw
          : cw.contains('MIX')
              ? ContentWarning.mixed
              : ContentWarning.safe,
      icon: res?['iconUrl']?.toString() ?? (e['pkg'] != null ? '${base}icon/${e['pkg']}.png' : null),
      apkUrl: apk,
      sources: sources,
      repo: repo,
    ));
  }
  return out;
}

/// The chapter number Mihon parsed, or one read from the name when it couldn't.
String? chapterNumber(double? parsed, String name) {
  if (parsed != null && parsed >= 0) {
    return parsed == parsed.roundToDouble() ? parsed.toInt().toString() : parsed.toString();
  }
  final m = RegExp(r'(?:ch(?:apter)?\.?|episode|ep\.?|#)\s*(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(name) ??
      RegExp(r'(\d+(?:\.\d+)?)').firstMatch(name);
  return m?.group(1);
}

/// "Chapter 12 - The Gate" → "The Gate"; plain "Chapter 12" → null.
String? _chapterTitle(String name) {
  final t = name
      .replaceFirst(RegExp(r'^\s*(?:vol(?:ume)?\.?\s*\d+\s*)?(?:ch(?:apter)?\.?\s*\d+(?:\.\d+)?)\s*[-:–·]?\s*', caseSensitive: false), '')
      .trim();
  if (t.isEmpty || RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) return null;
  return t;
}
