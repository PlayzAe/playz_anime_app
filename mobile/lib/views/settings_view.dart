import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Ink;

import '../app.dart';
import '../models/local.dart';
import '../services/anilist.dart';
import '../services/downloader.dart';
import '../services/native.dart';
import '../services/store.dart';
import '../services/stream_resolver.dart';
import '../sources/ani/episodes.dart';
import '../sources/manga/extensions.dart';
import '../sources/manga/providers.dart';
import '../state/app_state.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_icon.dart';
import '../widgets/subtitle_style.dart';
import 'browse_view.dart';
import 'downloads_list.dart';
import 'profile_view.dart';
import 'reader_view.dart' show ReadMode;

/// Settings. Port of `Settings.tsx`: same sections and wording, laid out for
/// a phone. A chip bar jumps between sections; long choices open a picker.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.app});

  final AppState app;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _scroll = ScrollController();
  final _keys = {for (final s in _sections) s: GlobalKey()};
  String _active = _sections.first;
  bool _subOpen = false;

  static const _sections = ['Look', 'Watching', 'Reading', 'Manga', 'Downloads', 'Privacy', 'Permissions', 'Your data', 'About'];

  @override
  void initState() {
    super.initState();
    Store.i.addListener(_onStore);
    Extensions.i.addListener(_onStore);
    Native.permissions.addListener(_onStore);
    Native.permissionState();
  }

  @override
  void dispose() {
    Store.i.removeListener(_onStore);
    Extensions.i.removeListener(_onStore);
    Native.permissions.removeListener(_onStore);
    _scroll.dispose();
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Settings get _s => Store.i.settings;
  void _set(Settings Function(Settings) f) => widget.app.patch(f);

  Future<void> _pickFolder({required bool manga}) async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: manga ? 'Save manga to' : 'Save anime to');
    if (dir == null || !mounted) return;
    if (!await Downloader.canWrite(dir)) {
      if (mounted) toast(context, 'PlayzAnime can’t save there. Allow file access under Permissions, or pick another folder.');
      return;
    }
    _set((x) => manga ? x.copyWith(mangaDir: dir) : x.copyWith(downloadDir: dir));
    if (mounted) toast(context, '${manga ? 'Manga' : 'Anime'} will save to $dir');
  }

  void _jump(String s) {
    setState(() => _active = s);
    final ctx = _keys[s]!.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 420), curve: kEase, alignment: 0.02);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final perms = Native.permissions.value;
    final ext = Extensions.i;
    return Column(children: [
      const TabTopBar(title: 'Settings'),
      SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 6),
          children: [
            for (final sec in _sections) Padding(padding: const EdgeInsets.only(right: 8), child: Chip2(sec, on: _active == sec, onTap: () => _jump(sec))),
          ],
        ),
      ),
      const Divider(height: 1, color: Lines.line),
      Expanded(
        child: ListView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(kGutter, 14, kGutter, MediaQuery.of(context).padding.bottom + 40),
          children: [
            Pressable(
              scale: 0.98,
              onTap: () => go(context, const ProfileView()),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Ink.ink1, borderRadius: BorderRadius.circular(12), border: Border.all(color: Lines.line)),
                child: Row(children: [
                  const Avatar(size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((Store.i.profile?.name ?? '').isEmpty ? 'Set up your profile' : Store.i.profile!.name, style: body(16, weight: FontWeight.w800)),
                      Text('Name, picture, backup and restore', style: body(12.5, color: Paper.paper3)),
                    ]),
                  ),
                  const PzIcon('chevronRight', size: 16, color: Paper.paper3),
                ]),
              ),
            ),
            _section('Look', [
              _Row(
                title: 'Accent',
                desc: 'Colours the play button, the logo and the app icon on your home screen. The icon changes once you leave the app.',
                below: Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final a in AccentKey.values) _Swatch(accent: a, selected: widget.app.accent == a, onTap: () => _set((x) => x.copyWith(accent: a.name))),
                ]),
              ),
              _Row(
                title: 'Titles',
                desc: 'Which name to show first.',
                below: Segmented<String>(
                  value: s.titleLanguage,
                  options: const [('english', 'English'), ('romaji', 'Romaji')],
                  onChanged: (v) => _set((x) => x.copyWith(titleLanguage: v)),
                ),
              ),
              _Row(
                title: 'Japanese titles',
                desc: 'Show the original title set vertically beside the artwork.',
                trailing: PzToggle(value: s.showNativeTitles, onChanged: (v) => _set((x) => x.copyWith(showNativeTitles: v))),
              ),
            ]),
            _section('Watching', [
              _Row(
                title: 'Player',
                desc: s.player == PlayerMode.direct
                    ? 'PlayzAnime’s player: gestures, quality, subtitle style, picture-in-picture.'
                    : 'The source’s own web player. Fewer features, but some episodes only start here.',
                trailing: _Picker(
                  value: s.player == PlayerMode.direct ? 'PlayzAnime' : 'Source player',
                  options: const ['PlayzAnime', 'Source player'],
                  onChanged: (v) => _set((x) => x.copyWith(player: v == 'PlayzAnime' ? PlayerMode.direct : PlayerMode.embed)),
                ),
              ),
              _Row(
                title: 'Open episodes in fullscreen',
                desc: 'Turns to landscape when an episode starts. The exit button brings you back.',
                trailing: PzToggle(value: s.autoRotate, onChanged: (v) => _set((x) => x.copyWith(autoRotate: v))),
              ),
              _Row(
                title: 'Picture-in-picture',
                desc: 'Keep watching in a small window when you leave the app.',
                trailing: PzToggle(value: s.autoPip, onChanged: (v) => _set((x) => x.copyWith(autoPip: v))),
              ),
              _Row(
                title: 'Brightness and volume swipes',
                desc: 'In fullscreen, swipe up or down on the left for brightness, on the right for volume.',
                trailing: PzToggle(value: s.swipeGestures, onChanged: (v) => _set((x) => x.copyWith(swipeGestures: v))),
              ),
              _Row(
                title: 'Skip step',
                desc: 'Double-tap the sides or use the skip buttons.',
                trailing: _Picker(
                  value: '${s.seekSeconds} s',
                  options: const ['5 s', '10 s', '15 s', '30 s'],
                  onChanged: (v) => _set((x) => x.copyWith(seekSeconds: int.parse(v.split(' ').first))),
                ),
              ),
              _Row(
                title: 'Episode quality',
                desc: 'Highest quality the player starts at. Data saver caps it at 480p. Change it any time in the player.',
                trailing: _Picker(
                  value: s.quality == QualityPref.best ? 'Best' : s.quality.label,
                  options: const ['Best', '1080p', '720p', '480p', '360p'],
                  onChanged: (v) => _set((x) => x.copyWith(quality: v == 'Best' ? QualityPref.best : QualityPrefX.parse(v.replaceAll('p', '')))),
                ),
              ),
              _Row(
                title: 'Prefer English dub',
                desc: 'Starts dubbed when a dub exists.',
                trailing: PzToggle(value: s.preferDub, onChanged: (v) => _set((x) => x.copyWith(preferDub: v))),
              ),
              _Row(
                title: 'Subtitle language',
                desc: 'Picked automatically when the source has it.',
                trailing: _Picker(
                  value: s.subtitleLanguage,
                  options: const ['English', 'Spanish', 'Portuguese', 'French', 'German', 'Italian', 'Russian', 'Arabic', 'Off'],
                  onChanged: (v) => _set((x) => x.copyWith(subtitleLanguage: v)),
                ),
              ),
              _Row(
                title: 'Subtitle style',
                desc: 'Size, colour, background and position.',
                trailing: PzBtn(_subOpen ? 'Done' : 'Edit', compact: true, onTap: () => setState(() => _subOpen = !_subOpen)),
                below: _subOpen ? const SubtitleStyleEditor() : null,
              ),
              _Row(
                title: 'Autoplay next episode',
                desc: 'Counts down while the credits roll.',
                trailing: PzToggle(value: s.autoplayNext, onChanged: (v) => _set((x) => x.copyWith(autoplayNext: v))),
              ),
              _Row(
                title: 'Skip intros automatically',
                desc: 'Only for episodes where the source marks the opening.',
                trailing: PzToggle(value: s.autoSkipIntro, onChanged: (v) => _set((x) => x.copyWith(autoSkipIntro: v))),
              ),
            ]),
            _section('Reading', [
              _Row(
                title: 'Reading mode',
                desc: 'Long strip suits manhwa and manhua; paged suits manga. Change it in the reader too.',
                trailing: _Picker(
                  value: ReadMode.parse(s.readMode).label,
                  options: [for (final m in ReadMode.values) m.label],
                  onChanged: (v) => _set((x) => x.copyWith(readMode: ReadMode.values.firstWhere((m) => m.label == v).name)),
                ),
              ),
              _Row(
                title: 'Long-strip page width',
                desc: 'Adds side margins on wide screens. ${(s.readerWidth * 100).round()}% of the screen.',
                below: Slider(
                  value: s.readerWidth.clamp(0.5, 1),
                  min: 0.5,
                  max: 1,
                  divisions: 10,
                  activeColor: accentOf(context),
                  onChanged: (v) => _set((x) => x.copyWith(readerWidth: v)),
                ),
              ),
              _Row(
                title: 'Background',
                desc: 'Behind the pages.',
                below: Segmented<String>(
                  value: s.readerBackground,
                  options: const [('black', 'Black'), ('ink', 'Ink'), ('white', 'White')],
                  onChanged: (v) => _set((x) => x.copyWith(readerBackground: v)),
                ),
              ),
            ]),
            _section('Manga', [
              _Row(
                title: 'Extensions',
                desc: ext.packages.isEmpty
                    ? 'Mihon extensions add hundreds of manga, manhwa and manhua sites.'
                    : '${ext.packages.length} installed${ext.updates.isEmpty ? '' : ' · ${ext.updates.length} updates ready'}',
                trailing: PzBtn(ext.updates.isEmpty ? 'Manage' : 'Update', compact: true, primary: ext.updates.isNotEmpty, onTap: () => go(context, const ExtensionsPage())),
              ),
              _Row(
                title: 'Update extensions automatically',
                desc: 'Checks the repo once a day. Sites change often, so updates keep chapters loading.',
                trailing: PzToggle(value: ext.autoUpdate, onChanged: ext.setAutoUpdate),
              ),
              _Row(
                title: 'Default source',
                desc: 'Auto asks every source and reads from the one furthest along. You can still pick per title.',
                trailing: _Picker(
                  value: s.mangaProvider == 'auto' ? 'Auto' : providerName(s.mangaProvider),
                  options: ['Auto', for (final p in kProviders) p.name, for (final x in ext.installed) x.name],
                  onChanged: (v) {
                    final id = v == 'Auto'
                        ? 'auto'
                        : kProviders.where((p) => p.name == v).map((p) => p.id).firstOrNull ?? ext.installed.firstWhere((x) => x.name == v).provider;
                    _set((x) => x.copyWith(mangaProvider: id));
                  },
                ),
              ),
              for (final p in kProviders)
                _Row(
                  title: p.name,
                  desc: p.note,
                  trailing: PzToggle(value: Store.i.isSourceEnabled(p.id), onChanged: (v) => Store.i.setSourceEnabled(p.id, v)),
                ),
            ]),
            _section('Downloads', [
              FutureBuilder<String>(
                future: Downloader.i.folder(),
                builder: (c, snap) => _Row(
                  title: 'Anime folder',
                  desc: snap.data ?? '…',
                  trailing: PzBtn('Change', compact: true, onTap: () => _pickFolder(manga: false)),
                ),
              ),
              FutureBuilder<String>(
                future: Downloader.i.mangaFolder(),
                builder: (c, snap) => _Row(
                  title: 'Manga folder',
                  desc: snap.data ?? '…',
                  trailing: PzBtn('Change', compact: true, onTap: () => _pickFolder(manga: true)),
                ),
              ),
              _Row(
                title: 'Download quality',
                desc: 'Offered first when you download. 720p is about 270 MB an episode; 1080p about 500 MB.',
                trailing: _Picker(
                  value: s.downloadQuality.label,
                  options: const ['1080p', '720p', '480p', '360p'],
                  onChanged: (v) => _set((x) => x.copyWith(downloadQuality: QualityPrefX.parse(v.replaceAll('p', '')))),
                ),
              ),
              _Row(
                title: 'Only download on wifi',
                desc: 'Holds the queue on mobile data and resumes on wifi.',
                trailing: PzToggle(value: s.downloadOnlyOnWifi, onChanged: (v) => _set((x) => x.copyWith(downloadOnlyOnWifi: v))),
              ),
              _Row(
                title: 'Tell me when downloads finish',
                desc: 'A notification once the queue is done.',
                trailing: PzToggle(value: s.notifyDownloads, onChanged: (v) => _set((x) => x.copyWith(notifyDownloads: v))),
              ),
              _Row(
                title: 'Open Downloads',
                desc: 'Everything saved on this phone, and what is downloading now.',
                trailing: PzBtn('Open', compact: true, icon: 'downloads', onTap: () => go(context, const DownloadsView())),
              ),
            ]),
            _section('Privacy', [
              _Row(
                title: 'Data saver',
                desc: 'Smaller covers, 480p episodes and compressed manga pages. Falls back to the smallest quality a show has.',
                trailing: PzToggle(value: s.dataSaver, onChanged: (v) => _set((x) => x.copyWith(dataSaver: v))),
              ),
              _Row(
                title: 'Hide adult content',
                desc: 'Keeps 18+ titles out of lists and search, and hides NSFW extensions (they stay installed and come back when this is off).',
                trailing: PzToggle(
                  value: s.hideAdult,
                  onChanged: (v) {
                    _set((x) => x.copyWith(hideAdult: v));
                    AniList.i.hideAdult = v;
                    Store.i.removeFeedCache();
                  },
                ),
              ),
              _Row(
                title: 'Keep screen on',
                desc: 'While a video plays or a chapter is open.',
                trailing: PzToggle(value: s.keepScreenOn, onChanged: (v) => _set((x) => x.copyWith(keepScreenOn: v))),
              ),
            ]),
            _section('Permissions', [
              _Row(
                title: 'Files',
                desc: perms['files'] == false ? 'Needed to save downloads to the folders you pick.' : 'Allowed.',
                trailing: perms['files'] == false ? PzBtn('Allow', compact: true, primary: true, onTap: Native.requestFiles) : const PzIcon('check', size: 18, color: Paper.paper2),
              ),
              _Row(
                title: 'Notifications',
                desc: perms['notifications'] == false ? 'Download progress and the now-playing controls.' : 'Allowed.',
                trailing: perms['notifications'] == false
                    ? PzBtn('Allow', compact: true, primary: true, onTap: Native.requestNotifications)
                    : const PzIcon('check', size: 18, color: Paper.paper2),
              ),
              _Row(title: 'App settings', desc: 'Change any permission in Android settings.', trailing: PzBtn('Open', compact: true, onTap: Native.openAppSettings)),
            ]),
            _section('Your data', [
              _Row(
                title: 'Clear cached lists',
                desc: 'Home, schedule and search reload from AniList. Your library stays.',
                trailing: PzBtn('Clear', compact: true, onTap: () async {
                  await Store.i.removeFeedCache();
                  StreamResolver.i.clearCache();
                  clearEpisodeCache();
                  MangaProviders.i.clear();
                  if (context.mounted) toast(context, 'Cached lists cleared');
                }),
              ),
              _Row(
                title: 'Watch and reading history',
                desc: 'Removes Continue watching, resume points and reading progress.',
                trailing: PzBtn('Clear', compact: true, onTap: () async {
                  if (!await confirm(context, title: 'Clear all history?', message: 'Continue watching and reading progress will be gone.', action: 'Clear')) return;
                  Store.i.clearHistory();
                  for (final r in Store.i.reading()) {
                    Store.i.removeReading(r.media.id);
                  }
                  if (context.mounted) toast(context, 'History cleared');
                }),
              ),
              _Row(
                title: 'Reset the app',
                desc: 'Library, history and settings go back to new. Downloaded files stay in your folders.',
                trailing: PzBtn('Reset', compact: true, onTap: () async {
                  if (!await confirm(context, title: 'Reset PlayzAnime?', message: 'Your list, history and settings are erased. Downloads stay.', action: 'Reset')) return;
                  final dir = Store.i.settings.downloadDir;
                  final manga = Store.i.settings.mangaDir;
                  await Store.i.resetAll();
                  Store.i.patchSettings((x) => x.copyWith(downloadDir: dir, mangaDir: manga));
                  if (context.mounted) toast(context, 'Reset done');
                }),
              ),
              _Row(
                title: 'Delete downloads too',
                desc: 'Removes every downloaded episode and chapter from your phone.',
                trailing: PzBtn('Delete', compact: true, onTap: () async {
                  if (!await confirm(context, title: 'Delete all downloads?', message: 'Every downloaded episode and chapter is removed from this phone. This can’t be undone.', action: 'Delete')) {
                    return;
                  }
                  for (final j in Downloader.i.jobs.toList()) {
                    await Downloader.i.remove(j.id);
                  }
                  if (context.mounted) toast(context, 'Downloads deleted');
                }),
              ),
              _Row(
                title: 'When you uninstall',
                desc: 'Android asks whether to keep app data. Your settings are also saved as playzanime-settings.ini in your downloads folder, so a reinstall picks them up.',
              ),
            ]),
            _section('About', [
              _Row(
                title: 'PlayzAnime 2.2 for Android',
                desc: 'Anime from AniList and anikoto. Manga from MangaDex, Asura, Flame, WeebCentral, MangaPill and Mihon extensions.'
                    '${Platform.isAndroid ? '' : ''}',
                trailing: PzLogo(size: 40, accent: accentOf(context)),
              ),
            ]),
          ],
        ),
      ),
    ]);
  }

  Widget _section(String title, List<Widget> rows) => Container(
        key: _keys[title],
        padding: const EdgeInsets.only(top: 26, bottom: 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Lines.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: body(18, weight: FontWeight.w800)),
          const SizedBox(height: 6),
          ...rows,
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.desc, this.trailing, this.below});

  final String title;
  final String desc;
  final Widget? trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: body(15, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(desc, style: body(12.5, color: Paper.paper3, height: 1.4)),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 14), trailing!],
          ]),
          if (below != null) ...[const SizedBox(height: 12), below!],
        ]),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.accent, required this.selected, required this.onTap});

  final AccentKey accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.9,
        child: AnimatedContainer(
          duration: kMed,
          curve: kEase,
          width: 62,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Ink.ink2 : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: selected ? Lines.line2 : Colors.transparent),
          ),
          child: Column(children: [
            PzLogo(size: 32, accent: accent.base, framed: true),
            const SizedBox(height: 5),
            Text(accent.kanji, style: TextStyle(fontSize: 12, color: selected ? Paper.paper : Paper.paper3)),
            Text(accent.label, style: body(11, weight: selected ? FontWeight.w800 : FontWeight.w500, color: selected ? Paper.paper : Paper.paper3)),
          ]),
        ),
      );
}

/// Dropdown-style picker that opens a sheet, like the desktop `<select>`.
class _Picker extends StatelessWidget {
  const _Picker({required this.value, required this.options, required this.onChanged});

  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => pzSheet<void>(context,
            title: 'Choose',
            builder: (c) => ListView(shrinkWrap: true, children: [
                  for (final o in options)
                    SheetOption(o, selected: o == value, onTap: () {
                      Navigator.pop(c);
                      onChanged(o);
                    }),
                ])),
        child: Container(
          height: 40,
          constraints: const BoxConstraints(maxWidth: 170),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Ink.ink1, borderRadius: BorderRadius.circular(8), border: Border.all(color: Lines.line2)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(13.5, weight: FontWeight.w700))),
            const SizedBox(width: 8),
            const PzIcon('chevronDown', size: 14, color: Paper.paper2),
          ]),
        ),
      );
}
