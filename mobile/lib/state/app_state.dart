import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/local.dart';
import '../models/media.dart';
import '../services/format.dart';
import '../services/log.dart';
import '../services/store.dart';
import '../services/native.dart';
import '../services/settings_file.dart';
import '../theme/accent.dart';
import '../widgets/pz_toast.dart';

/// The handful of things every screen needs, and nothing else.
///
/// [Store] is one notifier for the whole data file, so a `ListenableBuilder` on
/// it rebuilds its caller for a library write it does not care about. This sits
/// in front of it and fires only when the slice it exposes actually moved, which
/// is what lets the root widget watch it for the accent and the shell watch it
/// for the toast host without either sitting on the store's guest list.
///
/// It holds no data of its own — everything is derived from the store or a
/// device signal — so `dispose()` is the only thing that has to be undone.
class AppState extends ChangeNotifier {
  AppState({Store? store, Connectivity? connectivity})
    : _store = store ?? Store.i,
      _connectivity = connectivity ?? Connectivity() {
    _settings = _store.settings;
    _loaded = _store.isLoaded;
    _store.addListener(_onStore);
    unawaited(_watchNetwork());
  }

  final Store _store;
  final Connectivity _connectivity;
  final _log = Log('app-state');

  Settings _settings = const Settings();
  bool _loaded = false;
  bool _online = true;
  StreamSubscription<List<ConnectivityResult>>? _netSub;

  // ── Settings ──────────────────────────────────────────────────────────────

  /// False until the data file (or `SharedPreferences` on web) is in memory.
  /// The shell holds the splash until this flips, because painting defaults and
  /// then correcting them is the flicker the desktop's store also avoided.
  bool get ready => _loaded;

  Settings get settings => _settings;

  /// The one write path for settings, so a screen never has to hold a [Store]
  /// to change one — and so the optimistic/authoritative dance stays in one place.
  Settings patch(Settings Function(Settings) change) => _store.patchSettings(change);

  /// The seal colour, parsed once per settings change instead of per widget.
  AccentKey get accent => AccentKey.parse(_settings.accent);

  void _onStore() {
    final settings = _store.settings;
    final loaded = _store.isLoaded;
    // `Settings` has no `==`, and `patchSettings` always swaps in a new object,
    // so identity is the honest comparison here: same object means the write was
    // to something else in the file (library, history) and no screen of ours cares.
    if (identical(settings, _settings) && loaded == _loaded) return;
    if (_loaded && !identical(settings, _settings)) {
      // Keep the launcher icon and the settings.ini backup in step.
      if (settings.accent != _settings.accent) Native.setIcon(settings.accent);
      SettingsFile.schedule(settings);
    }
    _settings = settings;
    _loaded = loaded;
    notifyListeners();
  }

  // ── Network ───────────────────────────────────────────────────────────────

  bool get online => _online;
  bool get offline => !_online;

  /// `connectivity_plus` reports the interface, not reachability — the same
  /// truth the desktop took from `navigator.onLine`. A captive portal counts as
  /// online here, exactly as it did there, and only the two transitions that
  /// matter (`online`, `offline`) are re-broadcast.
  Future<void> _watchNetwork() async {
    try {
      _netSub = _connectivity.onConnectivityChanged.listen(_onNetwork);
      _onNetwork(await _connectivity.checkConnectivity());
    } catch (err) {
      // No platform behind the call (tests, an unsupported target). The app runs;
      // it just never claims to be offline, which is the safe direction: the
      // offline notice only ever hides things.
      _log.warn('connectivity unavailable, assuming online', err);
    }
  }

  void _onNetwork(List<ConnectivityResult> results) {
    final next = results.any((r) => r != ConnectivityResult.none);
    if (next == _online) return;
    _online = next;
    notifyListeners();
  }

  // ── Titles ────────────────────────────────────────────────────────────────

  /// The row title for anything that came out of the store.
  ///
  /// A snapshot only carries the title that was preferred when it was captured,
  /// plus romaji and native — never the English one — so romaji resolves straight
  /// through and english falls back to whatever was saved.
  String title(MediaSnapshot m) =>
      _settings.titleLanguage == 'romaji' ? _firstOf(m.romaji, m.title) : _firstOf(m.title, m.romaji);

  /// Live AniList data, which still has every title.
  String titleOf(Media m) => Fmt.titleOf(m, lang: _settings.titleLanguage);

  /// The other-language title, or null when it would just repeat [titleOf].
  String? altTitleOf(Media m) => Fmt.altTitleOf(m, lang: _settings.titleLanguage);

  /// Every write into the store builds its snapshot here, so what gets persisted
  /// carries the title language that was live at that moment instead of whichever
  /// one the calling screen happened to pass.
  MediaSnapshot snapshotOf(Media m) => Fmt.snapshot(m, lang: _settings.titleLanguage);

  /// Dart's `??` only skips null; the desktop's `||` also skipped empty strings.
  static String _firstOf(String? a, String? b) => (a != null && a.isNotEmpty) ? a : (b ?? 'Untitled');

  // ── Images ────────────────────────────────────────────────────────────────

  /// Whether the fast image path is on: the raised memory budget and the
  /// disk-backed cache `PzImage` reads through.
  ///
  /// Off on web — there is no disk to write to and the browser already keeps its
  /// own copy — and off under Data saver, which exists so the app stops holding
  /// decoded art the user may never scroll to.
  bool get imageCacheAccelerated => !kIsWeb && !_settings.dataSaver;

  /// `imageCache.maximumSizeBytes` for `PaintingBinding`, set once in `main()`.
  /// A 40-page webtoon chapter is 40-120 MB if it is allowed to pile up, so the
  /// cap is deliberately below what the reader could use.
  int get imageCacheBytes => imageCacheAccelerated ? 96 << 20 : 16 << 20;

  /// `imageCache.maximumSize` — a count of live bitmaps, not bytes.
  int get imageCacheEntries => imageCacheAccelerated ? 40 : 12;

  // ── Toasts ────────────────────────────────────────────────────────────────

  /// Thin on purpose: [PzToasts] owns the queue, the 3.4s/6s timers and the
  /// animation, so a toast raised from a screen and one raised from a sheet
  /// behave identically and neither reaches for the singleton itself.
  void toast(String text, {ToastTone tone = ToastTone.info, ToastAction? action}) =>
      PzToasts.i.show(text, tone: tone, action: action);

  void toastError(String text) => PzToasts.i.show(text, tone: ToastTone.error);

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _netSub?.cancel();
    super.dispose();
  }
}
