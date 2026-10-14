import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Ink;

import '../models/local.dart';
import '../models/media.dart';
import '../models/stream.dart';
import '../services/downloader.dart';
import '../services/store.dart';
import '../sources/manga/providers.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_icon.dart';
import '../widgets/subtitle_style.dart';
import 'downloads_list.dart';

/// Pick the episodes (a range), audio, quality and subtitles, then queue them.
/// Port of desktop `components/DownloadDialogs.tsx`, laid out for a phone.
Future<void> showEpisodeDownload(
  BuildContext context, {
  required MediaSnapshot media,
  required EpisodeList eps,
  required List<Episode> targets,
  int? minutes,
}) async {
  if (eps.episodes.isEmpty) return;
  final dir = await Downloader.i.folder();
  if (!context.mounted) return;
  final queued = await pzSheet<int>(
    context,
    title: 'Download',
    builder: (c) => _EpisodeDownloadBody(media: media, eps: eps, targets: targets, folder: dir, minutes: minutes),
  );
  if (queued != null && queued > 0 && context.mounted) {
    showDownloadsSnack(context, queued == 1 ? 'Downloading 1 episode' : 'Downloading $queued episodes');
  }
}

/// "Downloading…" with a shortcut to the Downloads screen.
void showDownloadsSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Ink.ink2,
      content: Text(text, style: body(14)),
      action: SnackBarAction(label: 'View', textColor: accentOf(context), onPressed: () => go(context, const DownloadsView())),
    ));
}

/// Queue chapter downloads straight away (pages have no options to pick).
Future<void> downloadChapters(BuildContext context, MediaSnapshot media, List<MChapter> chapters) async {
  final dir = await Downloader.i.mangaFolder();
  if (!await Downloader.canWrite(dir)) {
    if (context.mounted) toast(context, 'Can’t save to $dir. Pick another folder in Settings → Downloads.');
    return;
  }
  for (final ch in chapters) {
    Downloader.i.enqueueChapter(media, ch);
  }
  if (context.mounted) {
    showDownloadsSnack(context, chapters.length == 1 ? 'Downloading ${chapters.first.label}' : 'Downloading ${chapters.length} chapters');
  }
}

/// Rough size of one episode at a quality ceiling, from typical bitrates on the
/// source (1080p ≈ 2.8 Mb/s). Shown so nobody downloads 500 MB by surprise.
int estimateBytes(QualityPref q, {int minutes = 24}) {
  final mbps = switch (q) {
    QualityPref.best || QualityPref.q1080 => 2.8,
    QualityPref.q720 => 1.5,
    QualityPref.q480 => 0.8,
    QualityPref.q360 => 0.5,
  };
  return (mbps * 1000000 / 8 * minutes * 60).round();
}

String sizeLabel(int bytes) => bytes >= 1 << 30 ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB' : '${(bytes / (1 << 20)).round()} MB';

class _EpisodeDownloadBody extends StatefulWidget {
  const _EpisodeDownloadBody({required this.media, required this.eps, required this.targets, required this.folder, this.minutes});

  final MediaSnapshot media;
  final EpisodeList eps;
  final List<Episode> targets;
  final String folder;

  /// Episode length from AniList, for the size estimate.
  final int? minutes;

  @override
  State<_EpisodeDownloadBody> createState() => _EpisodeDownloadBodyState();
}

class _EpisodeDownloadBodyState extends State<_EpisodeDownloadBody> {
  late final List<Episode> _all = widget.eps.episodes;
  late int _from;
  late int _to;
  late Set<int>? _pick = widget.targets.length > 1 ? {for (final e in widget.targets) e.number} : null;
  late Audio _audio = Store.i.settings.preferDub && widget.eps.hasDub ? Audio.dub : Audio.sub;
  late QualityPref _q = Store.i.settings.dataSaver ? QualityPref.q480 : Store.i.settings.downloadQuality;
  String _subs = 'English';
  late String _folder = widget.folder;

  @override
  void initState() {
    super.initState();
    final first = widget.targets.isEmpty ? _all.first.number : widget.targets.map((e) => e.number).reduce((a, b) => a < b ? a : b);
    final last = widget.targets.isEmpty ? first : widget.targets.map((e) => e.number).reduce((a, b) => a > b ? a : b);
    _from = first;
    _to = last;
    final lang = Store.i.settings.subtitleLanguage;
    _subs = lang.toLowerCase() == 'off' ? 'None' : 'English';
  }

  List<Episode> get _chosen {
    final range = _all.where((e) => e.number >= _from && e.number <= _to);
    final set = _pick;
    final list = set == null ? range.toList() : _all.where((e) => set.contains(e.number)).toList();
    return list.where((e) => Downloader.i.episodeFile(widget.media.id, e.number, _audio) == null).toList();
  }

  void _quick(String which) {
    final watched = Store.i.watched(widget.media.id).toSet();
    setState(() {
      _pick = null;
      switch (which) {
        case 'next5':
          final start = _all.indexWhere((e) => e.number >= _from);
          final slice = _all.skip(start < 0 ? 0 : start).take(5).toList();
          _to = slice.last.number;
        case 'unwatched':
          final left = _all.where((e) => !watched.contains(e.number)).toList();
          if (left.isNotEmpty) {
            _from = left.first.number;
            _to = left.last.number;
          }
        case 'all':
          _from = _all.first.number;
          _to = _all.last.number;
      }
      if (_to < _from) _to = _from;
    });
  }

  Future<void> _pickEpisode(bool start) async {
    final n = await pzSheet<int>(context,
        title: start ? 'From episode' : 'To episode',
        builder: (c) => ListView(shrinkWrap: true, children: [
              for (final e in _all)
                SheetOption('Episode ${e.number}', selected: e.number == (start ? _from : _to), onTap: () => Navigator.pop(c, e.number)),
            ]));
    if (n == null) return;
    setState(() {
      _pick = null;
      if (start) {
        _from = n;
        if (_to < n) _to = n;
      } else {
        _to = n;
        if (_from > n) _from = n;
      }
    });
  }

  Future<void> _changeFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Where should anime downloads go?');
    if (dir == null) return;
    if (!await Downloader.canWrite(dir)) {
      if (mounted) toast(context, 'PlayzAnime can’t write there. Allow file access in Settings, or pick another folder.');
      return;
    }
    Store.i.patchSettings((s) => s.copyWith(downloadDir: dir));
    setState(() => _folder = dir);
  }

  void _start() {
    final list = _chosen;
    final subs = switch (_subs) {
      'None' => const <String>[],
      'All' => const ['*'],
      _ => const ['English'],
    };
    for (final e in list) {
      final url = e.urlFor(_audio);
      if (url == null) continue;
      Downloader.i.enqueueEpisode(
        media: widget.media,
        episode: e.number,
        episodeTitle: e.title,
        audio: _audio,
        embedUrl: url,
        quality: _q,
        subtitles: subs,
      );
    }
    Store.i.patchSettings((s) => s.copyWith(downloadQuality: _q));
    Navigator.pop(context, list.length);
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    final minutes = widget.minutes ?? (widget.media.format == 'MOVIE' ? 100 : 24);
    final each = estimateBytes(_q, minutes: minutes);
    final st = SubStyle.of(Store.i.settings);
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(t, style: body(13, color: Paper.paper3, weight: FontWeight.w700)),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(widget.media.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(14, color: Paper.paper2)),
        label('Episodes'),
        if (_pick != null)
          Row(children: [
            Expanded(child: Text('${_pick!.length} selected', style: body(15, weight: FontWeight.w700))),
            PzBtn('Use a range', compact: true, onTap: () => setState(() => _pick = null)),
          ])
        else
          Row(children: [
            Expanded(child: _Picker(label: 'From', value: 'E$_from', onTap: () => _pickEpisode(true))),
            const SizedBox(width: 10),
            Expanded(child: _Picker(label: 'To', value: 'E$_to', onTap: () => _pickEpisode(false))),
          ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Chip2('Next 5', onTap: () => _quick('next5')),
          Chip2('Unwatched', onTap: () => _quick('unwatched')),
          Chip2('All ${_all.length}', onTap: () => _quick('all')),
        ]),
        if (widget.eps.hasDub) ...[
          label('Audio'),
          Segmented<Audio>(
            value: _audio,
            options: const [(Audio.sub, 'Japanese + subs'), (Audio.dub, 'English dub')],
            onChanged: (v) => setState(() => _audio = v),
          ),
        ],
        label('Quality'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final q in const [QualityPref.q1080, QualityPref.q720, QualityPref.q480, QualityPref.q360])
            Chip2('${q.label} · ${sizeLabel(estimateBytes(q, minutes: minutes))}', on: _q == q, onTap: () => setState(() => _q = q)),
        ]),
        const SizedBox(height: 6),
        Text('Sizes are per episode and approximate. If an episode doesn’t have this quality, the nearest one below it is used.',
            style: body(11.5, color: Paper.paper3, height: 1.4)),
        label('Subtitles'),
        Segmented<String>(
          value: _subs,
          options: const [('English', 'English'), ('All', 'All languages'), ('None', 'None')],
          onChanged: (v) => setState(() => _subs = v),
        ),
        if (_subs != 'None') ...[
          const SizedBox(height: 10),
          Pressable(
            onTap: () async {
              await pzSheet<void>(context,
                  title: 'Subtitle style',
                  builder: (c) => const SingleChildScrollView(padding: EdgeInsets.fromLTRB(20, 0, 20, 20), child: SubtitleStyleEditor()));
              if (mounted) setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Ink.ink2, borderRadius: BorderRadius.circular(10), border: Border.all(color: Lines.line)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Subtitle style', style: body(14, weight: FontWeight.w700)),
                    Text('${(st.size * 100).round()}% · ${st.outline ? 'outline' : 'no outline'}${st.background > 0 ? ' · box' : ''}. Used when you watch in PlayzAnime.',
                        style: body(11.5, color: Paper.paper3)),
                  ]),
                ),
                const PzIcon('chevronRight', size: 16, color: Paper.paper3),
              ]),
            ),
          ),
        ],
        label('Saving to'),
        Row(children: [
          Expanded(child: Text(_folder, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(12.5, color: Paper.paper2))),
          PzBtn('Change', compact: true, icon: 'folder', onTap: _changeFolder),
        ]),
        const SizedBox(height: 18),
        PzBtn(
          chosen.isEmpty
              ? 'Already downloaded'
              : 'Download ${chosen.length} episode${chosen.length == 1 ? '' : 's'} · ≈ ${sizeLabel(each * chosen.length)}',
          icon: 'downloads',
          primary: true,
          onTap: chosen.isEmpty ? null : _start,
        ),
      ]),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: Ink.ink2, borderRadius: BorderRadius.circular(10), border: Border.all(color: Lines.line2)),
          child: Row(children: [
            Text(label, style: body(12.5, color: Paper.paper3)),
            const Spacer(),
            Text(value, style: body(15, weight: FontWeight.w800)),
            const SizedBox(width: 6),
            const PzIcon('chevronDown', size: 14, color: Paper.paper3),
          ]),
        ),
      );
}

/// Download state for one row: idle icon, live ring while queued, check when saved.
class DownloadMark extends StatelessWidget {
  const DownloadMark({super.key, required this.jobKey, required this.done, required this.onDownload});

  final String jobKey;
  final bool Function() done;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Downloader.i,
        builder: (c, _) {
          final job = Downloader.i.active(jobKey);
          Widget child;
          if (done()) {
            child = PzIcon('check', size: 18, color: accentOf(c));
          } else if (job != null) {
            child = SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                value: job.progress > 0 ? job.progress : null,
                color: accentOf(c),
                backgroundColor: Ink.ink3,
              ),
            );
          } else {
            child = const PzIcon('downloads', size: 18, color: Paper.paper3);
          }
          return Pressable(
            onTap: job == null && !done() ? onDownload : null,
            child: Padding(padding: const EdgeInsets.all(10), child: child),
          );
        },
      );
}
