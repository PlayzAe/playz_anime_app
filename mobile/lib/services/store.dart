import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/local.dart';
import '../models/media.dart';
import 'files.dart';
import 'log.dart';
import 'paths.dart';
import 'prefs.dart';

/// The single on-device data file.
///
/// A port of `src/main/store.ts`. Same JSON shape, same debounced atomic write,
/// same caps — minus everything that only existed because the desktop app had a
/// window and a Desktop folder to manage.
///
/// Widgets do not read this directly: [Store] extends [ChangeNotifier] and the
/// app's stores listen to it, so a write here rebuilds only the panels that
/// subscribed to the slice that changed.
class Store extends ChangeNotifier {
  Store._();

  static final Store i = Store._();

  final _log = Log('store');

  static const int _maxHistory = 80;
  static const int _maxDownloadRecords = 300;
  static const int _version = 2;

  _StoreData _data = _StoreData.fresh();
  Timer? _timer;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> init() async {
    if (_loaded) return;
    await Paths.i.init();
    _data = await _load();
    _loaded = true;
    notifyListeners();
  }

  // ── Load / save ───────────────────────────────────────────────────────────

  Future<_StoreData> _load() async {
    final base = _StoreData.fresh();
    final raw = await Files.readText(Paths.i.dataFile);
    if (raw == null || raw.isEmpty) return base;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return base;
      final json = Map<String, dynamic>.from(decoded);

      // A profile's worth of state comes from SharedPreferences on web, where
      // there is no file system.
      final settings = Settings.fromJson(_mapOf(json['settings']));

      return _StoreData(
        version: _version,
        settings: settings,
        library: _entriesOf<LibraryEntry>(json['library'], LibraryEntry.fromJson),
        history: _entriesOf<HistoryEntry>(json['history'], HistoryEntry.fromJson),
        watched: _numberListsOf(json['watched']),
        reading: _entriesOf<ReadingEntry>(json['reading'], ReadingEntry.fromJson),
        read: _stringListsOf(json['read']),
        downloads: [
          for (final e in (json['downloads'] as List? ?? const []))
            if (e is Map) DownloadJob.fromJson(Map<String, dynamic>.from(e)),
        ],
        categories: [
          for (final e in (json['categories'] as List? ?? const []))
            if (e is Map) LibraryCategory.fromJson(Map<String, dynamic>.from(e)),
        ],
        setupDone: json['setupDone'] == true,
        profile: json['profile'] is Map ? Profile.fromJson(_mapOf(json['profile'])) : null,
        imported: [
          for (final e in (json['imported'] as List? ?? const []))
            if (e is Map) ImportedProfile.fromJson(Map<String, dynamic>.from(e)),
        ],
        disabledSources: (json['disabledSources'] as List? ?? const []).map((e) => e.toString()).toSet(),
        sourceOrder: (json['sourceOrder'] as List? ?? const []).map((e) => e.toString()).toList(),
        pinned: (json['pinned'] is Map)
            ? Map<String, String>.from((json['pinned'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())))
            : <String, String>{},
      );
    } catch (err) {
      _log.error('could not read the data file, starting fresh', err);
      // Keep the broken file so the user can send it in.
      await Files.writeTextAtomic(
        '${Paths.i.dataFile}.corrupt-${DateTime.now().millisecondsSinceEpoch}',
        raw,
      );
      return base;
    }
  }

  static Map<String, dynamic> _mapOf(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static Map<String, T> _entriesOf<T>(Object? v, T Function(Map<String, dynamic>) parse) {
    final out = <String, T>{};
    if (v is! Map) return out;
    for (final e in v.entries) {
      final row = e.value;
      if (row is Map) out[e.key.toString()] = parse(Map<String, dynamic>.from(row));
    }
    return out;
  }

  static Map<String, List<num>> _numberListsOf(Object? v) {
    final out = <String, List<num>>{};
    if (v is! Map) return out;
    for (final e in v.entries) {
      final row = e.value;
      if (row is List) out[e.key.toString()] = [for (final n in row) if (n is num) n];
    }
    return out;
  }

  static Map<String, List<String>> _stringListsOf(Object? v) {
    final out = <String, List<String>>{};
    if (v is! Map) return out;
    for (final e in v.entries) {
      final row = e.value;
      if (row is List) out[e.key.toString()] = [for (final n in row) n.toString()];
    }
    return out;
  }

  /// Debounced: a burst of writes (dragging a slider) costs one disk hit.
  void _schedule() {
    if (kIsWeb) {
      // No file system; SharedPreferences takes a small, immediate write.
      unawaited(_persistSmall());
      return;
    }
    _timer ??= Timer(const Duration(milliseconds: 400), () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<void> _persistSmall() async {
    await Prefs.i.setJson('settings', _data.settings.toJson());
    await Prefs.i.setJson('library', {
      for (final e in _data.library.entries) e.key: e.value.toJson(),
    });
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (kIsWeb) {
      await _persistSmall();
      return;
    }
    try {
      await Files.writeTextAtomic(Paths.i.dataFile, jsonEncode(_data.toJson()));
    } catch (err) {
      _log.error('write failed', err);
    }
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Settings get settings => _data.settings;

  Settings patchSettings(Settings Function(Settings) change) {
    _data.settings = change(_data.settings);
    _schedule();
    notifyListeners();
    return _data.settings;
  }

  // ── First run & profiles ──────────────────────────────────────────────────

  bool get setupDone => _data.setupDone;

  void markSetupDone() {
    _data.setupDone = true;
    _schedule();
    notifyListeners();
  }

  Profile? get profile => _data.profile;

  void setProfile(Profile? profile) {
    _data.profile = profile;
    _schedule();
    notifyListeners();
  }

  /// Everything a friend needs to see what we watch and read. Settings stay private.
  ProfileExport exportProfile() {
    final p = _data.profile ??
        Profile(id: 'anonymous', name: 'PlayzAnime viewer', createdAt: DateTime.now().millisecondsSinceEpoch);
    return ProfileExport(
      exportedAt: DateTime.now().millisecondsSinceEpoch,
      profile: p,
      library: library(),
      history: history(),
      reading: reading(),
    );
  }

  /// Restores a backup made on this or another phone: library, history and
  /// reading merge in (newer entries win), settings and profile replace ours.
  void restoreBackup(ProfileExport p, {Map<String, dynamic>? settings}) {
    final lib = {for (final e in _data.library.values) e.media.id: e};
    for (final e in p.library) {
      final mine = lib[e.media.id];
      if (mine == null || e.updatedAt > mine.updatedAt) _data.library['${e.media.id}'] = e;
    }
    for (final h in p.history) {
      saveHistory(h);
    }
    for (final r in p.reading) {
      saveReading(r);
    }
    _data.profile = p.profile;
    if (settings != null) {
      final keep = _data.settings;
      _data.settings = Settings.fromJson({...keep.toJson(), ...settings}).copyWith(
        downloadDir: keep.downloadDir,
        mangaDir: keep.mangaDir,
        setupDone: true,
      );
    }
    _schedule();
    notifyListeners();
  }

  List<ImportedProfile> importedProfiles() =>
      [..._data.imported]..sort((a, b) => b.importedAt.compareTo(a.importedAt));

  /// Re-importing the same person replaces their earlier copy instead of
  /// duplicating it.
  ImportedProfile addImported(ProfileExport p) {
    final entry = ImportedProfile(data: p, importedAt: DateTime.now().millisecondsSinceEpoch);
    _data.imported = [entry, ..._data.imported.where((x) => x.profile.id != p.profile.id)];
    _schedule();
    notifyListeners();
    return entry;
  }

  void removeImported(String profileId) {
    _data.imported = _data.imported.where((x) => x.profile.id != profileId).toList();
    _schedule();
    notifyListeners();
  }

  // ── Library ───────────────────────────────────────────────────────────────

  List<LibraryEntry> library() =>
      [..._data.library.values]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<LibraryEntry> libraryIn(String? categoryId) {
    if (categoryId == null || categoryId == 'all') return library();
    if (categoryId == 'default') {
      return library().where((e) => e.categories.isEmpty || e.categories.contains('default')).toList();
    }
    return library().where((e) => e.categories.contains(categoryId)).toList();
  }

  LibraryEntry? libraryEntry(int mediaId) => _data.library['$mediaId'];

  List<LibraryEntry> setLibrary(MediaSnapshot media, ListStatus status) {
    final key = '${media.id}';
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = _data.library[key];
    _data.library[key] = LibraryEntry(
      media: media,
      status: status,
      addedAt: prev?.addedAt ?? now,
      updatedAt: now,
      categories: prev?.categories ?? const [],
    );
    _schedule();
    notifyListeners();
    return library();
  }

  List<LibraryEntry> setCategories(int mediaId, List<String> categories) {
    final key = '$mediaId';
    final prev = _data.library[key];
    if (prev != null) {
      _data.library[key] = prev.copyWith(
        categories: categories,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _schedule();
      notifyListeners();
    }
    return library();
  }

  List<LibraryEntry> removeLibrary(int mediaId) {
    _data.library.remove('$mediaId');
    _schedule();
    notifyListeners();
    return library();
  }

  // ── Categories (the Mihon structure) ──────────────────────────────────────

  List<LibraryCategory> get categories {
    final list = [..._data.categories]..sort((a, b) => a.order.compareTo(b.order));
    if (list.isEmpty) return const [LibraryCategory(id: 'default', name: 'Default', order: 0)];
    return list;
  }

  void addCategory(String name) {
    final id = 'cat-${DateTime.now().millisecondsSinceEpoch}';
    _data.categories = [..._data.categories, LibraryCategory(id: id, name: name, order: _data.categories.length)];
    _schedule();
    notifyListeners();
  }

  void renameCategory(String id, String name) {
    _data.categories = [
      for (final c in _data.categories)
        c.id == id ? LibraryCategory(id: c.id, name: name, order: c.order) : c,
    ];
    _schedule();
    notifyListeners();
  }

  // ── Source preferences ────────────────────────────────────────────────────

  Set<String> get disabledSources => _data.disabledSources;

  bool isSourceEnabled(String id) => !_data.disabledSources.contains(id);

  void setSourceEnabled(String id, bool enabled) {
    if (enabled) {
      _data.disabledSources = {..._data.disabledSources}..remove(id);
    } else {
      _data.disabledSources = {..._data.disabledSources, id};
    }
    _schedule();
    notifyListeners();
  }

  List<String> get sourceOrder => _data.sourceOrder;

  void setSourceOrder(List<String> ids) {
    _data.sourceOrder = ids;
    _schedule();
    notifyListeners();
  }

  /// A source the user pinned for a specific title, overriding auto-pick.
  String? pinnedSource(int mediaId) => _data.pinned['$mediaId'];

  void pinSource(int mediaId, String? sourceId) {
    if (sourceId == null) {
      _data.pinned.remove('$mediaId');
    } else {
      _data.pinned['$mediaId'] = sourceId;
    }
    _schedule();
    notifyListeners();
  }

  // ── Watch history ─────────────────────────────────────────────────────────

  List<HistoryEntry> history() =>
      [..._data.history.values]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  void saveHistory(HistoryEntry entry) {
    _data.history['${entry.media.id}'] = entry;
    final sorted = history();
    for (final old in sorted.skip(_maxHistory)) {
      _data.history.remove('${old.media.id}');
    }
    _promoteFromPlanning(entry.media.id);
    _schedule();
    notifyListeners();
  }

  List<HistoryEntry> removeHistory(int mediaId) {
    _data.history.remove('$mediaId');
    _schedule();
    notifyListeners();
    return history();
  }

  void clearHistory() {
    _data.history = {};
    _data.watched = {};
    _data.reading = {};
    _data.read = {};
    _schedule();
    notifyListeners();
  }

  List<int> watched(int mediaId) => [...?_data.watched['$mediaId']?.map((n) => n.toInt())];

  List<int> setWatched(int mediaId, List<int> episodes, bool watched) {
    final key = '$mediaId';
    final set = {...?_data.watched[key]?.map((n) => n.toInt())};
    for (final ep in episodes) {
      if (watched) {
        set.add(ep);
      } else {
        set.remove(ep);
      }
    }
    _data.watched[key] = set.toList()..sort();
    _schedule();
    notifyListeners();
    return this.watched(mediaId);
  }

  // ── Reading history ───────────────────────────────────────────────────────

  List<ReadingEntry> reading() =>
      [..._data.reading.values]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  ReadingEntry? readingEntry(int mediaId) => _data.reading['$mediaId'];

  void saveReading(ReadingEntry entry) {
    _data.reading['${entry.media.id}'] = entry;
    final sorted = reading();
    for (final old in sorted.skip(_maxHistory)) {
      _data.reading.remove('${old.media.id}');
    }
    _promoteFromPlanning(entry.media.id);
    _schedule();
    notifyListeners();
  }

  List<ReadingEntry> removeReading(int mediaId) {
    _data.reading.remove('$mediaId');
    _schedule();
    notifyListeners();
    return reading();
  }

  List<String> readChapters(int mediaId) => [...?_data.read['$mediaId']];

  List<String> setRead(int mediaId, List<String> chapters, bool read) {
    final key = '$mediaId';
    final set = {...?_data.read[key]};
    for (final c in chapters) {
      if (read) {
        set.add(c);
      } else {
        set.remove(c);
      }
    }
    _data.read[key] = set.toList();
    _schedule();
    notifyListeners();
    return readChapters(mediaId);
  }

  // ── Download records ──────────────────────────────────────────────────────

  List<DownloadJob> downloadRecords() => [..._data.downloads];

  void saveDownloadRecords(List<DownloadJob> jobs) {
    _data.downloads = jobs.take(_maxDownloadRecords).toList();
    _schedule();
    // Download progress is high-frequency; the queue notifies its own listeners
    // and this store stays quiet so the shell does not rebuild 10x a second.
  }

  /// Opening something from the planning list moves it to watching.
  void _promoteFromPlanning(int mediaId) {
    final lib = _data.library['$mediaId'];
    if (lib != null && lib.status == ListStatus.planning) {
      _data.library['$mediaId'] = lib.copyWith(
        status: ListStatus.watching,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  /// Wipes everything but the profile. Settings → Advanced.
  Future<void> resetAll() async {
    _data = _StoreData.fresh();
    await flush();
    notifyListeners();
  }

  /// Removes cached home feed data on disk when adult filters change.
  Future<void> removeFeedCache() async {
    if (kIsWeb) return;
    try {
      await Files.delete(Paths.i.feedCacheFile);
    } catch (_) {}
  }
}

class _StoreData {
  _StoreData({
    required this.version,
    required this.settings,
    required this.library,
    required this.history,
    required this.watched,
    required this.reading,
    required this.read,
    required this.downloads,
    required this.categories,
    required this.setupDone,
    required this.profile,
    required this.imported,
    required this.disabledSources,
    required this.sourceOrder,
    required this.pinned,
  });

  factory _StoreData.fresh() => _StoreData(
    version: Store._version,
    settings: const Settings(),
    library: {},
    history: {},
    watched: {},
    reading: {},
    read: {},
    downloads: [],
    categories: [],
    setupDone: false,
    profile: null,
    imported: [],
    disabledSources: {},
    sourceOrder: [],
    pinned: {},
  );

  int version;
  Settings settings;
  Map<String, LibraryEntry> library;
  Map<String, HistoryEntry> history;
  Map<String, List<num>> watched;
  Map<String, ReadingEntry> reading;
  Map<String, List<String>> read;
  List<DownloadJob> downloads;
  List<LibraryCategory> categories;
  bool setupDone;
  Profile? profile;
  List<ImportedProfile> imported;
  Set<String> disabledSources;
  List<String> sourceOrder;
  Map<String, String> pinned = {};

  Map<String, dynamic> toJson() => {
    'version': version,
    'settings': settings.toJson(),
    'library': {for (final e in library.entries) e.key: e.value.toJson()},
    'history': {for (final e in history.entries) e.key: e.value.toJson()},
    'watched': watched,
    'reading': {for (final e in reading.entries) e.key: e.value.toJson()},
    'read': read,
    'downloads': [for (final j in downloads) j.toJson()],
    'categories': [for (final c in categories) c.toJson()],
    'setupDone': setupDone,
    'profile': profile?.toJson(),
    'imported': [for (final p in imported) p.toJson()],
    'disabledSources': disabledSources.toList(),
    'sourceOrder': sourceOrder,
    'pinned': pinned,
  };
}
