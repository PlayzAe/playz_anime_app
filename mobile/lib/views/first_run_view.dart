import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Ink;

import '../models/local.dart';
import '../models/media.dart';
import '../services/anilist.dart';
import '../services/downloader.dart';
import '../services/native.dart';
import '../services/settings_file.dart';
import '../services/store.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_icon.dart';

/// One-time setup on first launch: who you are and your colour, the
/// permissions the app needs, and where downloads go (chosen by you, never
/// picked silently). A settings file left by an earlier install is offered back.
class FirstRunView extends StatefulWidget {
  const FirstRunView({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<FirstRunView> createState() => _FirstRunViewState();
}

class _FirstRunViewState extends State<FirstRunView> {
  final _pages = PageController();
  final _name = TextEditingController();
  int _step = 0;
  String? _anime;
  String? _manga;
  bool _restored = false;

  static const _steps = 4;

  @override
  void initState() {
    super.initState();
    Native.wire();
    Native.permissions.addListener(_refresh);
    Native.permissionState();
    // Warm the catalogue while the user reads.
    unawaited(AniList.i.home().then((_) {}, onError: (_) {}));
    unawaited(AniList.i.mangaHome().catchError((_) => const MangaFeed(trending: [], manhwa: [], top: [])));
  }

  @override
  void dispose() {
    Native.permissions.removeListener(_refresh);
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _go(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _pages.animateToPage(step, duration: const Duration(milliseconds: 380), curve: kEase);
  }

  Future<void> _pick({required bool manga}) async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: manga ? 'Where should manga go?' : 'Where should anime go?');
    if (dir == null) return;
    if (!await Downloader.canWrite(dir)) {
      if (mounted) toast(context, 'PlayzAnime can’t write there yet. Allow file access on the previous step, or pick another folder.');
      return;
    }
    setState(() => manga ? _manga = dir : _anime = dir);
    if (!manga && !_restored) await _offerRestore(dir);
  }

  Future<void> _useDefault() async {
    final def = await Downloader.defaultFolder();
    if (!await Downloader.canWrite(def)) {
      if (mounted) toast(context, 'Allow file access first, or choose folders yourself.');
      return;
    }
    setState(() {
      _anime = def;
      _manga = '$def/Manga';
    });
    if (!_restored) await _offerRestore(def);
  }

  /// An earlier install left its settings in this folder: offer them back.
  Future<void> _offerRestore(String dir) async {
    final ini = await SettingsFile.find(dir);
    if (ini == null || !mounted) return;
    final ok = await confirm(
      context,
      title: 'Welcome back',
      message: 'Settings from an earlier install were found in this folder (accent, player, reader). Use them?',
      action: 'Restore',
    );
    if (!ok) return;
    Store.i.patchSettings((s) => SettingsFile.merge(s, ini));
    _restored = true;
    if (mounted) toast(context, 'Settings restored');
  }

  void _finish() {
    final name = _name.text.trim();
    if (name.isNotEmpty && Store.i.profile == null) {
      Store.i.setProfile(Profile(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, createdAt: DateTime.now().millisecondsSinceEpoch));
    }
    Store.i.patchSettings((s) => s.copyWith(downloadDir: _anime ?? s.downloadDir, mangaDir: _manga ?? s.mangaDir, setupDone: true));
    Store.i.markSetupDone();
    SettingsFile.save(Store.i.settings);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final accent = PzAccent.of(context);
    final pad = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: Ink.ink0,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        Positioned(
          top: -120,
          right: -80,
          child: AnimatedContainer(
            duration: kMed,
            width: 320,
            height: 320,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [accent.base.withAlpha(0x40), accent.base.withAlpha(0)])),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(0, pad.top + 12, 0, pad.bottom + 12),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                for (var i = 0; i < _steps; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: kMed,
                      height: 3,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(color: i <= _step ? accent.base : Ink.ink3, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [_welcome(accent), _permissions(), _folders(), _ready()],
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _frame({required String kicker, required String title, required String text, required List<Widget> children, required Widget action, Widget? back}) =>
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
        child: FadeIn(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(kicker.toUpperCase(), style: body(11.5, weight: FontWeight.w800, color: accentOf(context))),
            const SizedBox(height: 6),
            Text(title, style: display(38)),
            const SizedBox(height: 8),
            Text(text, style: body(14, color: Paper.paper2, height: 1.5)),
            const SizedBox(height: 22),
            ...children,
            const SizedBox(height: 26),
            action,
            if (back != null) ...[const SizedBox(height: 8), back],
          ]),
        ),
      );

  Widget _welcome(PzAccent accent) => _frame(
        kicker: 'PlayzAnime',
        title: 'Anime and manga,\nin one place.',
        text: 'Watch with subs or dub, read manga, manhwa and manhua, and keep anything offline. First, make it yours.',
        children: [
          Center(child: AnimatedSwitcher(duration: kMed, child: PzLogo(key: ValueKey(accent.key0), size: 84, accent: accent.base))),
          const SizedBox(height: 20),
          Text('Your name', style: body(13, color: Paper.paper3, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            style: body(16),
            cursorColor: accent.base,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Optional',
              hintStyle: body(16, color: Paper.paper4),
              filled: true,
              fillColor: Ink.ink2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 18),
          Text('Colour', style: body(13, color: Paper.paper3, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Also colours the app icon on your home screen.', style: body(12, color: Paper.paper3)),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final a in AccentKey.values)
              Pressable(
                onTap: () => Store.i.patchSettings((s) => s.copyWith(accent: a.name)),
                child: AnimatedContainer(
                  duration: kMed,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.key0 == a ? Paper.paper : Colors.transparent, width: 2),
                  ),
                  child: PzLogo(size: 40, accent: a.base),
                ),
              ),
          ]),
        ],
        action: PzBtn('Continue', icon: 'arrowRight', primary: true, onTap: () => _go(1)),
      );

  Widget _permissions() {
    final p = Native.permissions.value;
    final files = p['files'] ?? !Native.available;
    final notes = p['notifications'] ?? !Native.available;
    return _frame(
      kicker: 'Step 2 of 4',
      title: 'A couple of\npermissions',
      text: 'Android asks you directly. Nothing is switched on behind your back, and you can change these later in Settings → Permissions.',
      children: [
        _PermCard(
          icon: 'folder',
          title: 'Files',
          text: 'Save episodes and chapters to folders you choose, and play them offline.',
          granted: files,
          onAllow: Native.requestFiles,
        ),
        const SizedBox(height: 12),
        _PermCard(
          icon: 'bolt',
          title: 'Notifications',
          text: 'Download progress, “downloads finished”, and play/pause controls while watching.',
          granted: notes,
          onAllow: Native.requestNotifications,
        ),
      ],
      action: PzBtn(files && notes ? 'Continue' : 'Continue without', icon: 'arrowRight', primary: true, onTap: () => _go(2)),
      back: PzBtn('Back', onTap: () => _go(0)),
    );
  }

  Widget _folders() => _frame(
        kicker: 'Step 3 of 4',
        title: 'Where should\ndownloads go?',
        text: 'Pick a folder for anime and one for manga. They stay on your phone even if you uninstall PlayzAnime.',
        children: [
          _FolderCard(icon: 'tv', title: 'Anime', path: _anime, onPick: () => _pick(manga: false)),
          const SizedBox(height: 12),
          _FolderCard(icon: 'manga', title: 'Manga, manhwa & manhua', path: _manga, onPick: () => _pick(manga: true)),
          const SizedBox(height: 12),
          if (_anime == null || _manga == null)
            Center(
              child: TextButton(
                onPressed: _useDefault,
                child: Text('Use Download/PlayzAnime for both', style: body(13, color: Paper.paper2, weight: FontWeight.w600)),
              ),
            ),
        ],
        action: PzBtn(
          _anime != null && _manga != null ? 'Continue' : 'Choose both folders',
          icon: 'arrowRight',
          primary: true,
          onTap: _anime != null && _manga != null ? () => _go(3) : null,
        ),
        back: PzBtn('Back', onTap: () => _go(1)),
      );

  Widget _ready() => _frame(
        kicker: 'All set',
        title: 'Ready when\nyou are.',
        text: 'A few things worth knowing:',
        children: [
          for (final (i, t) in const [
            ('play', 'Episodes open in fullscreen. Double-tap the sides to skip 5 s; swipe the edges for brightness and volume.'),
            ('downloads', 'Hold an episode to select several and download them in one go.'),
            ('manga', 'Manga reads from built-in sources and Mihon extensions. Add more in Settings → Manga.'),
            ('profile', 'Back up your list and settings from your profile, top right.'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: Ink.ink2, borderRadius: BorderRadius.circular(9)),
                  alignment: Alignment.center,
                  child: PzIcon(i, size: 17, color: accentOf(context)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(t, style: body(13.5, color: Paper.paper2, height: 1.45))),
              ]),
            ),
        ],
        action: PzBtn('Start watching', icon: 'play', primary: true, onTap: _finish),
        back: PzBtn('Back', onTap: () => _go(2)),
      );
}

class _PermCard extends StatelessWidget {
  const _PermCard({required this.icon, required this.title, required this.text, required this.granted, required this.onAllow});

  final String icon;
  final String title;
  final String text;
  final bool granted;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: kMed,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Ink.ink1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: granted ? accentOf(context).withAlpha(0x88) : Lines.line),
        ),
        child: Row(children: [
          PzIcon(icon, size: 22, color: granted ? accentOf(context) : Paper.paper2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: body(15, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(text, style: body(12.5, color: Paper.paper3, height: 1.4)),
            ]),
          ),
          const SizedBox(width: 10),
          granted ? PzIcon('check', size: 20, color: accentOf(context)) : PzBtn('Allow', compact: true, primary: true, onTap: onAllow),
        ]),
      );
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.icon, required this.title, required this.path, required this.onPick});

  final String icon;
  final String title;
  final String? path;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onPick,
        child: AnimatedContainer(
          duration: kMed,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Ink.ink1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: path != null ? accentOf(context).withAlpha(0x88) : Lines.line),
          ),
          child: Row(children: [
            PzIcon(icon, size: 22, color: path != null ? accentOf(context) : Paper.paper2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: body(15, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(path ?? 'Not chosen yet', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(12.5, color: path == null ? Paper.paper4 : Paper.paper3)),
              ]),
            ),
            const SizedBox(width: 10),
            PzBtn(path == null ? 'Choose' : 'Change', compact: true, primary: path == null, onTap: onPick),
          ]),
        ),
      );
}
