import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Ink;

import '../models/local.dart';
import '../services/downloader.dart';
import '../services/format.dart';
import '../services/store.dart';
import '../sources/manga/providers.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_icon.dart';
import '../widgets/pz_image.dart';
import 'reader_view.dart';
import 'watch_view.dart';

/// Downloads. Port of desktop `views/Downloads.tsx`, rebuilt for a phone:
/// what's downloading now (pause, resume, cancel), then everything on the
/// device grouped by show, filtered Everything / Anime / Manga / Manhwa / Manhua.
class DownloadsView extends StatefulWidget {
  const DownloadsView({super.key, this.initial = 'Everything'});

  final String initial;

  @override
  State<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends State<DownloadsView> {
  late String _tab = widget.initial;

  static const _tabs = ['Everything', 'Anime', 'Manga', 'Manhwa', 'Manhua'];

  Future<void> _folder(bool manga) async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: manga ? 'Folder for manga downloads' : 'Folder for anime downloads');
    if (dir == null) return;
    if (!await Downloader.canWrite(dir)) {
      if (mounted) toast(context, 'PlayzAnime can’t write there. Allow file access, or pick another folder.');
      return;
    }
    Store.i.patchSettings((s) => manga ? s.copyWith(mangaDir: dir) : s.copyWith(downloadDir: dir));
    if (mounted) toast(context, manga ? 'Manga will save to $dir' : 'Anime will save to $dir');
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Ink.ink0,
      body: ListenableBuilder(
        listenable: Downloader.i,
        builder: (context, _) {
          final jobs = Downloader.i.jobs;
          bool inTab(DownloadJob j) => _tab == 'Everything' || j.media.kind == _tab;
          final active = jobs.where((j) => !j.state.isFinished || j.state == DownloadState.error).where(inTab).toList().reversed.toList();
          final done = jobs.where((j) => j.state == DownloadState.done && inTab(j)).toList();
          final groups = <int, List<DownloadJob>>{};
          for (final j in done) {
            groups.putIfAbsent(j.media.id * (j.isEpisode ? 1 : -1), () => []).add(j);
          }
          final counts = {
            for (final t in _tabs)
              t: {
                for (final j in jobs.where((j) => j.state == DownloadState.done && (t == 'Everything' || j.media.kind == t))) j.media.id * (j.isEpisode ? 1 : -1)
              }.length,
          };
          final total = done.fold<int>(0, (a, j) => a + j.bytes);
          final paused = active.where((j) => j.state == DownloadState.paused || j.state == DownloadState.error).length;
          final width = MediaQuery.sizeOf(context).width;

          return CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(8, top + 8, kGutter, 0),
                child: Row(children: [
                  if (Navigator.canPop(context)) RoundIcon('arrowLeft', filled: false, onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Downloads', style: display(30))),
                  RoundIcon('tv', filled: false, iconSize: 18, onTap: () => _folder(false)),
                  RoundIcon('manga', filled: false, iconSize: 18, onTap: () => _folder(true)),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 2, kGutter, 8),
                child: Text('Everything here plays and reads inside PlayzAnime, with or without internet.', style: body(12.5, color: Paper.paper3)),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(kGutter, 2, kGutter, 6), children: [
                  for (final t in _tabs)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip2('$t ${counts[t]}', on: _tab == t, onTap: () => setState(() => _tab = t)),
                    ),
                ]),
              ),
            ),
            if (active.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  'In progress · ${active.length}',
                  action: paused == active.length ? 'Resume all' : 'Pause all',
                  onAction: paused == active.length ? Downloader.i.resumeAll : Downloader.i.pauseAll,
                ),
              ),
              SliverList.builder(itemCount: active.length, itemBuilder: (c, i) => _JobRow(active[i])),
            ],
            SliverToBoxAdapter(
              child: SectionHeader('On this device · ${groups.length}', subtitle: total > 0 ? Fmt.bytes(total) : null),
            ),
            if (groups.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 24),
                  child: Text(
                    'Nothing saved yet. Tap the download icon on an episode or chapter, or hold one to pick several.',
                    style: body(13, color: Paper.paper3, height: 1.45),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 0),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: width > 700 ? 170 : 130,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.5,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (c, i) => _ShowCard(groups.values.elementAt(i)),
                    childCount: groups.length,
                  ),
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.bottom + 40)),
          ]);
        },
      ),
    );
  }
}

/// Kept for the Library tab, which embeds the same list.
class DownloadsList extends StatelessWidget {
  const DownloadsList({super.key, required this.anime});

  final bool anime;

  @override
  Widget build(BuildContext context) => DownloadsView(initial: anime ? 'Anime' : 'Manga');
}

class _ShowCard extends StatelessWidget {
  const _ShowCard(this.items);

  final List<DownloadJob> items;

  @override
  Widget build(BuildContext context) {
    final first = items.first;
    final m = first.media;
    final size = items.fold<int>(0, (a, j) => a + j.bytes);
    final n = items.length;
    return Pressable(
      onTap: () => _open(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(fit: StackFit.expand, children: [
            PzImage(url: m.cover, radius: BorderRadius.circular(7)),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black.withAlpha(0xC0), borderRadius: BorderRadius.circular(4)),
                child: Text(first.isEpisode ? '$n ep${n == 1 ? '' : 's'}' : '$n ch${n == 1 ? '' : 's'}',
                    style: body(11, weight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(12.5, weight: FontWeight.w700, height: 1.2)),
        Text('${m.kind} · ${Fmt.bytes(size)}', maxLines: 1, style: body(11, color: Paper.paper3)),
      ]),
    );
  }

  void _open(BuildContext context) => pzSheet<void>(context,
      title: items.first.media.title,
      builder: (c) => ListenableBuilder(
            listenable: Downloader.i,
            builder: (c, _) {
              final live = [
                for (final j in Downloader.i.jobs)
                  if (j.state == DownloadState.done && items.any((x) => x.id == j.id)) j,
              ]..sort((a, b) => a.isEpisode
                  ? (a.episode ?? 0).compareTo(b.episode ?? 0)
                  : (double.tryParse(a.chapter?.number ?? '') ?? 0).compareTo(double.tryParse(b.chapter?.number ?? '') ?? 0));
              if (live.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text('Nothing left here.'));
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final j in live)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                        title: Text(j.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(14.5, weight: FontWeight.w600)),
                        subtitle: Text([if (j.resolution != null) j.resolution!, Fmt.bytes(j.bytes), if (j.audio != null) j.audio!.wire.toUpperCase()].join(' · '),
                            style: body(12, color: Paper.paper3)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          RoundIcon(j.isEpisode ? 'play' : 'manga', size: 36, iconSize: 16, onTap: () {
                            Navigator.pop(c);
                            _openJob(context, j, live);
                          }),
                          RoundIcon('trash', size: 36, iconSize: 16, filled: false, onTap: () async {
                            final ok = await confirm(context, title: 'Delete ${j.label}?', message: 'It will be removed from your phone.', action: 'Delete');
                            if (ok) await Downloader.i.remove(j.id);
                          }),
                        ]),
                        onTap: () {
                          Navigator.pop(c);
                          _openJob(context, j, live);
                        },
                      ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                  child: PzBtn('Delete all ${live.length}', icon: 'trash', onTap: () async {
                    final ok = await confirm(context, title: 'Delete all?', message: '${live.length} items will be removed from your phone.', action: 'Delete');
                    if (!ok) return;
                    for (final j in live) {
                      await Downloader.i.remove(j.id);
                    }
                    if (c.mounted) Navigator.pop(c);
                  }),
                ),
              ]);
            },
          ));
}

void _openJob(BuildContext context, DownloadJob job, List<DownloadJob> siblings) {
  if (job.isEpisode) {
    go(context, WatchView(mediaId: job.media.id, episode: job.episode ?? 1));
    return;
  }
  final chapters = [
    for (final j in siblings.where((j) => !j.isEpisode && j.chapter != null))
      MChapter(
        id: j.chapter!.id,
        provider: j.chapter!.provider,
        number: j.chapter!.number,
        title: j.chapter!.title,
        volume: j.chapter!.volume,
        group: j.chapter!.group,
        pages: j.chapter!.pages,
        publishedAt: j.chapter!.publishedAt,
      ),
  ];
  final index = chapters.indexWhere((c) => c.id == job.chapter?.id);
  go(context, ReaderView(mediaId: job.media.id, chapters: chapters, index: index < 0 ? 0 : index));
}

class _JobRow extends StatelessWidget {
  const _JobRow(this.job);

  final DownloadJob job;

  Future<void> _remove(BuildContext context) async {
    final ok = await confirm(context, title: 'Cancel download?', message: '${job.media.title} · ${job.label}', action: 'Cancel download');
    if (ok) await Downloader.i.remove(job.id);
  }

  String get _status => switch (job.state) {
        DownloadState.queued => job.stage ?? 'Waiting',
        DownloadState.resolving => job.stage ?? 'Finding the stream…',
        DownloadState.downloading => [
            '${(job.progress * 100).round()}%',
            if (job.bytes > 0) Fmt.bytes(job.bytes),
            if (job.speed > 0) '${Fmt.bytes(job.speed)}/s',
            if (job.resolution != null) job.resolution!,
          ].join(' · '),
        DownloadState.muxing => job.stage ?? 'Finishing…',
        DownloadState.paused => 'Paused · ${(job.progress * 100).round()}% · tap ▶ to resume',
        DownloadState.done => 'Ready offline',
        DownloadState.error => '${job.stage ?? 'Failed'} · ${job.error ?? ''}',
        DownloadState.cancelled => 'Cancelled',
      };

  @override
  Widget build(BuildContext context) {
    final s = job.state;
    final accent = accentOf(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Ink.ink1, borderRadius: BorderRadius.circular(10), border: Border.all(color: Lines.line)),
      child: Row(children: [
        SizedBox(width: 42, height: 60, child: PzImage(url: job.media.cover, radius: BorderRadius.circular(5))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(job.media.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(13.5, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(job.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(12.5, color: Paper.paper2)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: s == DownloadState.queued || s == DownloadState.resolving || job.progress <= 0 ? null : job.progress,
                minHeight: 3,
                color: s == DownloadState.paused || s == DownloadState.error ? Paper.paper3 : accent,
                backgroundColor: Ink.ink3,
              ),
            ),
            const SizedBox(height: 5),
            Text(_status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: body(11.5, color: s == DownloadState.error ? const Color(0xFFE5484D) : Paper.paper3)),
          ]),
        ),
        if (s.isRunning || s == DownloadState.queued)
          _Act('pause', () => Downloader.i.pause(job.id))
        else if (s == DownloadState.paused)
          _Act('play', () => Downloader.i.resume(job.id))
        else if (s == DownloadState.error || s == DownloadState.cancelled)
          _Act('refresh', () => Downloader.i.retry(job.id)),
        _Act('close', () => _remove(context)),
      ]),
    );
  }
}

class _Act extends StatelessWidget {
  const _Act(this.icon, this.onTap);

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(9), child: PzIcon(icon, size: 18, color: Paper.paper2)),
      );
}
