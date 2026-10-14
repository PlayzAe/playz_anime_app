import 'package:flutter/foundation.dart';

import '../models/local.dart';
import '../models/media.dart';
import '../services/store.dart';

/// How the Library orders what it shows.
///
/// `updated` is the desktop's order — the store hands titles back newest-touched
/// first — and stays the default so the list does not move under the user on a
/// fresh install.
enum LibrarySort {
  updated('Last updated'),
  added('Date added'),
  title('Title A–Z');

  const LibrarySort(this.label);

  final String label;
}

/// The Library screen's data: the saved titles, the Mihon categories, and both
/// histories.
///
/// The category filter, the sort and the search all live here rather than in the
/// view because [visible] is the one list the grid draws from — it is rebuilt
/// when an input changes and never while a frame is being laid out. `build()`
/// calling `where` and `sort` over the whole library is the exact thing that
/// makes a long list janky.
class LibraryState extends ChangeNotifier {
  LibraryState({Store? store}) : _store = store ?? Store.i {
    _store.addListener(_onStore);
    _read();
  }

  final Store _store;

  List<LibraryEntry> _entries = const [];
  List<LibraryCategory> _categories = const [];
  List<HistoryEntry> _history = const [];
  List<ReadingEntry> _reading = const [];

  List<LibraryEntry> _visible = const [];
  Map<ListStatus, List<LibraryEntry>> _byStatus = const {};
  Map<ListStatus, int> _counts = const {};
  List<LibraryActivity> _activity = const [];

  Map<int, ListStatus> _statusIndex = const {};
  Map<int, HistoryEntry> _historyIndex = const {};
  Map<int, ReadingEntry> _readingIndex = const {};

  String _category = 'all';
  LibrarySort _sort = LibrarySort.updated;
  String _query = '';
  MediaType? _kind;

  // ── Reads ─────────────────────────────────────────────────────────────────

  /// Every saved title, newest first — the store's order, nothing filtered out.
  List<LibraryEntry> get all => _entries;

  List<LibraryCategory> get categories => _categories;

  /// `all` / `default` / a category id. The chip row's current pick.
  String get category => _category;

  LibrarySort get sort => _sort;

  String get query => _query;

  /// `null` means everything — the desktop expressed `type=all` by leaving the
  /// parameter out, so the port spells it as null instead of inventing a third
  /// `MediaType`.
  MediaType? get kind => _kind;

  /// Category + kind + search, sorted. Assignments to it happen only inside
  /// [refresh]; a build never triggers the work.
  List<LibraryEntry> get visible => _visible;

  /// Per-status totals over [visible] — the badge on each tab.
  Map<ListStatus, int> get counts => _counts;

  /// The already-filtered bucket for one tab, so the grid never filters in build.
  List<LibraryEntry> ofStatus(ListStatus status) => _byStatus[status] ?? const [];

  List<HistoryEntry> get history => _history;
  List<ReadingEntry> get reading => _reading;

  /// Watching and reading merged, newest first — the History tab's rows.
  List<LibraryActivity> get activity => _activity;

  LibraryEntry? entryFor(int mediaId) => _store.libraryEntry(mediaId);

  /// An index, not the desktop's linear scan: `LibraryMeta` asks this once per
  /// card, which is once per card per frame in a scrolling grid.
  ListStatus? statusOf(int mediaId) => _statusIndex[mediaId];

  HistoryEntry? historyFor(int mediaId) => _historyIndex[mediaId];

  ReadingEntry? readingFor(int mediaId) => _readingIndex[mediaId];

  // ── Writes ────────────────────────────────────────────────────────────────
  //
  // All of these are synchronous and none of them notify: the store replaces the
  // entry it changed, fires once, and [_onStore] picks the new lists up. Writing
  // straight through keeps one source of truth instead of two that can disagree.
  //
  // `setStatus(null)` removes the title, exactly as the desktop's did.

  void setStatus(MediaSnapshot media, ListStatus? status) {
    if (status == null) {
      _store.removeLibrary(media.id);
      return;
    }
    _store.setLibrary(media, status);
  }

  void remove(int mediaId) => _store.removeLibrary(mediaId);

  /// Adds the category when the title is not already in it, takes it out when it
  /// is — one tap on the checkbox in the categories sheet.
  void toggleCategory(int mediaId, String categoryId) {
    final entry = _store.libraryEntry(mediaId);
    if (entry == null) return;
    final next = [...entry.categories];
    if (!next.remove(categoryId)) next.add(categoryId);
    _store.setCategories(mediaId, next);
  }

  void setCategories(int mediaId, List<String> categoryIds) =>
      _store.setCategories(mediaId, categoryIds);

  void addCategory(String name) => _store.addCategory(name);

  void renameCategory(String id, String name) => _store.renameCategory(id, name);

  void removeHistory(int mediaId) => _store.removeHistory(mediaId);

  void removeReading(int mediaId) => _store.removeReading(mediaId);

  /// Wipes both histories, which is what the confirm modal's copy promises.
  /// Library lists and downloaded files are untouched.
  void clearHistory() => _store.clearHistory();

  // ── Filters ───────────────────────────────────────────────────────────────

  void setCategory(String id) {
    if (id == _category) return;
    _category = id;
    _republish();
  }

  void setSort(LibrarySort next) {
    if (next == _sort) return;
    _sort = next;
    _republish();
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _republish();
  }

  void setKind(MediaType? next) {
    if (next == _kind) return;
    _kind = next;
    _republish();
  }

  // ── Store plumbing ────────────────────────────────────────────────────────

  void _onStore() {
    if (!_read()) return;
    notifyListeners();
  }

  /// Refills from the store and rebuilds the derived lists.
  ///
  /// Returns false when nothing observable changed. Every entry in the store is
  /// immutable — a write swaps in a `copyWith` result or drops the key — so
  /// comparing the lists element by element by identity is exact, costs no
  /// allocation, and keeps a category write from rebuilding a grid of posters
  /// that did not move.
  bool _read() {
    final entries = _store.library();
    final categories = _store.categories;
    final history = _store.history();
    final reading = _store.reading();
    if (_same(entries, _entries) &&
        _same(categories, _categories) &&
        _same(history, _history) &&
        _same(reading, _reading)) {
      return false;
    }
    _entries = entries;
    _categories = categories;
    _history = history;
    _reading = reading;
    _indexes();
    _refresh();
    return true;
  }

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  void _indexes() {
    // `Store.history()` and `Store.reading()` are one row per title already, so
    // the maps cannot lose an entry.
    _statusIndex = {for (final e in _entries) e.media.id: e.status};
    _historyIndex = {for (final h in _history) h.media.id: h};
    _readingIndex = {for (final r in _reading) r.media.id: r};
  }

  // ── Derived lists ─────────────────────────────────────────────────────────

  void _republish() {
    _refresh();
    notifyListeners();
  }

  /// Rebuilds `visible`, the per-status buckets, the counts and the merged
  /// activity list. Only ever called after an input moved.
  void _refresh() {
    final needle = _query.trim().toLowerCase();
    final visible = <LibraryEntry>[
      for (final e in _entries)
        if (_keep(e, needle)) e,
    ]..sort(_compare);
    _visible = visible;

    final byStatus = <ListStatus, List<LibraryEntry>>{};
    final counts = <ListStatus, int>{};
    for (final e in visible) {
      (byStatus[e.status] ??= <LibraryEntry>[]).add(e);
      counts[e.status] = (counts[e.status] ?? 0) + 1;
    }
    _byStatus = byStatus;
    _counts = counts;

    // The History tab drops the kind that cannot be in it, the same way the
    // desktop's merged list did.
    final activity = <LibraryActivity>[
      if (_kind != MediaType.manga)
        for (final h in _history) LibraryActivity.watch(h),
      if (_kind != MediaType.anime)
        for (final r in _reading) LibraryActivity.read(r),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _activity = activity;
  }

  bool _keep(LibraryEntry e, String needle) {
    final m = e.media;
    if (_kind != null && m.type != _kind) return false;
    if (!_inCategory(e)) return false;
    if (needle.isEmpty) return true;
    // Native titles are searched too — a romaji-only match would hide the title
    // the user is looking at when they typed the Japanese.
    return m.title.toLowerCase().contains(needle) ||
        (m.romaji?.toLowerCase().contains(needle) ?? false) ||
        (m.native?.toLowerCase().contains(needle) ?? false);
  }

  /// `all` is every title; `default` is the ones nobody filed, which is also
  /// where an empty category list sits — the same rule the store's own
  /// `libraryIn` applies, kept identical so the two can never disagree.
  bool _inCategory(LibraryEntry e) => switch (_category) {
    'all' => true,
    'default' => e.categories.isEmpty || e.categories.contains('default'),
    _ => e.categories.contains(_category),
  };

  int _compare(LibraryEntry a, LibraryEntry b) => switch (_sort) {
    LibrarySort.updated => b.updatedAt.compareTo(a.updatedAt),
    LibrarySort.added => b.addedAt.compareTo(a.addedAt),
    LibrarySort.title => a.media.title.toLowerCase().compareTo(b.media.title.toLowerCase()),
  };

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }
}

/// One row of the History tab: a resume point for an episode, or for a chapter.
///
/// The two share a list on purpose — the desktop merged them and sorted by
/// `updatedAt`, so "what was I in the middle of" is one scroll, not two tabs.
class LibraryActivity {
  const LibraryActivity.watch(this.watch) : read = null;
  const LibraryActivity.read(this.read) : watch = null;

  final HistoryEntry? watch;
  final ReadingEntry? read;

  bool get isWatch => watch != null;

  /// What the row's artwork and title come from, whichever kind it is.
  MediaSnapshot get media => watch?.media ?? read!.media;

  int get updatedAt => watch?.updatedAt ?? read!.updatedAt;

  /// Where the row opens: the same route the desktop linked to, expressed as
  /// data so the view does not have to branch twice.
  String get path => isWatch
      ? '/watch/${media.id}/${watch!.episode}'
      : '/read/${media.id}/${Uri.encodeComponent(read!.chapterId)}';
}
