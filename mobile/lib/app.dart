import 'package:flutter/material.dart' hide Ink;

import 'models/local.dart';
import 'services/connectivity.dart';
import 'services/downloader.dart';
import 'services/native.dart';
import 'services/store.dart';
import 'sources/manga/extensions.dart';
import 'state/app_state.dart';
import 'theme/accent.dart';
import 'theme/tokens.dart';
import 'ui/kit.dart';
import 'views/browse_view.dart' show maybeOfferExtensions;
import 'views/downloads_list.dart';
import 'views/first_run_view.dart';
import 'views/home_view.dart';
import 'views/library_view.dart';
import 'views/manga_home_view.dart';
import 'views/profile_view.dart';
import 'views/schedule_view.dart';
import 'views/settings_view.dart';
import 'views/splash_view.dart';
import 'widgets/pz_icon.dart';

class PlayzAnimeApp extends StatefulWidget {
  const PlayzAnimeApp({super.key});

  @override
  State<PlayzAnimeApp> createState() => _PlayzAnimeAppState();
}

class _PlayzAnimeAppState extends State<PlayzAnimeApp> {
  late final AppState _app = AppState();
  AccentKey? _last;

  @override
  void initState() {
    super.initState();
    _last = _app.accent;
    _app.addListener(() {
      if (_last != _app.accent) {
        _last = _app.accent;
        applyAccentToSystem(_app.accent);
      }
    });
  }

  @override
  void dispose() {
    _app.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _app,
        builder: (context, _) {
          final accent = _app.accent;
          return PzAccent(
            key0: accent,
            child: MaterialApp(
              title: 'PlayzAnime',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                fontFamily: 'Archivo',
                scaffoldBackgroundColor: Ink.ink0,
                canvasColor: Ink.ink0,
                colorScheme: ColorScheme.dark(surface: Ink.ink1, primary: accent.base, onPrimary: Seal.accentInk, onSurface: Paper.paper),
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                textSelectionTheme: TextSelectionThemeData(cursorColor: accent.base, selectionColor: accent.soft),
              ),
              home: Shell(app: _app),
            ),
          );
        },
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.app});

  final AppState app;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  bool _splashDone = false;
  bool _setupDone = Store.i.setupDone;
  bool _started = false;
  final _built = <int>{0};

  static const _items = [
    ('tv', 'Anime'),
    ('manga', 'Manga'),
    ('schedule', 'Schedule'),
    ('library', 'Library'),
    ('settings', 'Settings'),
  ];

  Widget _page(int i) => switch (i) {
        0 => HomeView(onTab: _select),
        1 => const MangaHomeView(),
        2 => const ScheduleView(),
        3 => LibraryView(onTab: _select),
        _ => SettingsView(app: widget.app),
      };

  void _select(int i) {
    if (i == _tab) return;
    setState(() {
      _tab = i;
      _built.add(i);
    });
    if (i == 1) maybeOfferExtensions(context);
  }

  /// Runs once the shell is showing: native hooks, the daily extension
  /// check, and — when there's no connection — straight to the downloads.
  void _start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      Native.wire();
      Native.setIcon(Store.i.settings.accent);
      Extensions.i.dailyCheck();
      if (!NetWatch.i.online && Downloader.i.jobs.any((j) => j.state == DownloadState.done)) {
        _select(3);
        if (mounted) go(context, const DownloadsView());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.app.ready) return const Scaffold(backgroundColor: Ink.ink0);
    if (!_splashDone) return SplashView(onDone: () => setState(() => _splashDone = true));
    if (!_setupDone && !Store.i.setupDone) return FirstRunView(onDone: () => setState(() => _setupDone = true));
    _start();

    final bottom = MediaQuery.of(context).padding.bottom;
    final accent = accentOf(context);
    // Tablets, unfolded foldables and landscape phones get a side rail.
    final wide = MediaQuery.sizeOf(context).width >= 720;

    final pages = Stack(children: [
      for (var i = 0; i < _items.length; i++)
        if (_built.contains(i))
          Offstage(
            offstage: _tab != i,
            child: TickerMode(
              enabled: _tab == i,
              child: AnimatedOpacity(opacity: _tab == i ? 1 : 0, duration: kMed, curve: kEase, child: _page(i)),
            ),
          ),
    ]);

    final content = Column(children: [
      const _OfflineBanner(),
      Expanded(child: pages),
    ]);

    if (wide) {
      return Scaffold(
        backgroundColor: Ink.ink0,
        body: Row(children: [
          Container(
            width: 84,
            decoration: const BoxDecoration(color: Ink.ink1, border: Border(right: BorderSide(color: Lines.line))),
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, bottom: bottom + 12),
            child: Column(children: [
              PzLogo(size: 36, accent: accent),
              const SizedBox(height: 18),
              for (var i = 0; i < _items.length; i++)
                Pressable(
                  onTap: () => _select(i),
                  scale: 0.9,
                  child: Container(
                    width: 84,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(children: [
                      AnimatedContainer(
                        duration: kMed,
                        width: 48,
                        height: 32,
                        decoration: BoxDecoration(color: _tab == i ? accent.withAlpha(0x30) : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                        alignment: Alignment.center,
                        child: PzIcon(_items[i].$1, size: 22, color: _tab == i ? Paper.paper : Paper.paper3),
                      ),
                      const SizedBox(height: 4),
                      Text(_items[i].$2, style: body(11, color: _tab == i ? Paper.paper : Paper.paper3, weight: _tab == i ? FontWeight.w700 : FontWeight.w500)),
                    ]),
                  ),
                ),
            ]),
          ),
          Expanded(child: content),
        ]),
      );
    }

    return Scaffold(
      backgroundColor: Ink.ink0,
      body: content,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: Ink.ink1, border: Border(top: BorderSide(color: Lines.line))),
        padding: EdgeInsets.only(bottom: bottom),
        height: 62 + bottom,
        child: Row(children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: Pressable(
                onTap: () => _select(i),
                scale: 0.9,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AnimatedContainer(
                    duration: kMed,
                    curve: kEase,
                    width: _tab == i ? 18 : 0,
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 7),
                    color: accent,
                  ),
                  AnimatedScale(
                    scale: _tab == i ? 1.08 : 1,
                    duration: kMed,
                    curve: Curves.easeOutBack,
                    child: PzIcon(_items[i].$1, size: 22, color: _tab == i ? Paper.paper : Paper.paper3),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    child: Text(_items[i].$2,
                        maxLines: 1, style: body(10.5, color: _tab == i ? Paper.paper : Paper.paper3, weight: _tab == i ? FontWeight.w700 : FontWeight.w500)),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

/// "You're offline" strip with a shortcut to what still works.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: NetWatch.i,
        builder: (c, _) => AnimatedSize(
          duration: kMed,
          curve: kEase,
          child: NetWatch.i.online
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(kGutter, MediaQuery.of(c).padding.top + 6, 8, 6),
                  color: Ink.ink2,
                  child: Row(children: [
                    const PzIcon('offline', size: 16, color: Paper.paper2),
                    const SizedBox(width: 8),
                    Expanded(child: Text('You’re offline. Downloads still play.', style: body(13, color: Paper.paper2))),
                    PzBtn('Downloads', compact: true, onTap: () => go(c, const DownloadsView())),
                  ]),
                ),
        ),
      );
}

/// Top bar for each tab: logo and title, search pill, downloads (with a live
/// count) and the profile avatar.
class TabTopBar extends StatelessWidget {
  const TabTopBar({super.key, required this.title, this.onSearch, this.trailing, this.subtitle});

  final String title;
  final String? subtitle;
  final VoidCallback? onSearch;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final offline = !NetWatch.i.online;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return Padding(
      padding: EdgeInsets.fromLTRB(kGutter, (offline ? 0 : MediaQuery.of(context).padding.top) + 10, kGutter - 4, 8),
      child: Row(children: [
        if (!wide) ...[PzLogo(size: 30, accent: accentOf(context)), const SizedBox(width: 10)],
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(26)),
            if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(11.5, color: Paper.paper3)),
          ]),
        ),
        const Spacer(),
        if (onSearch != null)
          Pressable(
            onTap: onSearch,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(color: Ink.ink2, borderRadius: BorderRadius.circular(8), border: Border.all(color: Lines.line2)),
              child: Row(children: [
                const PzIcon('search', size: 16, color: Paper.paper2),
                if (MediaQuery.sizeOf(context).width > 380) ...[const SizedBox(width: 7), Text('Search', style: body(13.5, color: Paper.paper3))],
              ]),
            ),
          ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        const SizedBox(width: 4),
        const _DownloadsButton(),
        Pressable(
          onTap: () => go(context, const ProfileView()),
          child: const Padding(padding: EdgeInsets.only(left: 2), child: Avatar(size: 32)),
        ),
      ]),
    );
  }
}

class _DownloadsButton extends StatelessWidget {
  const _DownloadsButton();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Downloader.i,
        builder: (c, _) {
          final n = Downloader.i.activeCount;
          return Pressable(
            onTap: () => go(c, const DownloadsView()),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Stack(alignment: Alignment.center, children: [
                PzIcon('downloads', size: 20, color: n > 0 ? accentOf(c) : Paper.paper2),
                if (n > 0)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: accentOf(c), borderRadius: BorderRadius.circular(8)),
                      child: Text('$n', textAlign: TextAlign.center, style: body(10, weight: FontWeight.w800, color: Seal.accentInk)),
                    ),
                  ),
              ]),
            ),
          );
        },
      );
}
