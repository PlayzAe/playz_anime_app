import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/services.dart';

import '../models/local.dart';
import '../models/media.dart';
import '../models/stream.dart';
import '../services/anilist.dart';
import '../services/downloader.dart';
import '../services/format.dart';
import '../services/store.dart';
import '../sources/ani/episodes.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_icon.dart';
import '../widgets/pz_image.dart';
import 'download_sheet.dart';
import 'manga_detail_view.dart';
import 'watch_view.dart';

/// Anime detail. Port of `Series.tsx` + `Detail.tsx`.
class SeriesView extends StatefulWidget {
  const SeriesView({super.key, required this.mediaId});

  final int mediaId;

  @override
  State<SeriesView> createState() => _SeriesViewState();
}

class _SeriesViewState extends State<SeriesView> {
  MediaDetail? _m;
  EpisodeList? _eps;
  Object? _error;
  Object? _epsError;
  bool _expanded = false;
  bool _newestFirst = false;

  /// Hold an episode to start picking several (download or mark watched).
  final Set<int> _picked = {};

  @override
  void initState() {
    super.initState();
    Store.i.addListener(_onStore);
    _load();
  }

  @override
  void dispose() {
    Store.i.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _error = null;
      _epsError = null;
    });
    try {
      final m = await AniList.i.media(widget.mediaId, force: force);
      if (!mounted) return;
      setState(() => _m = m);
      if (m.status == MediaStatus.notYetReleased) return;
      final eps = await listEpisodes(widget.mediaId, force: force);
      if (mounted) setState(() => _eps = eps);
    } catch (e) {
      if (!mounted) return;
      setState(() => _m == null ? _error = e : _epsError = e);
    }
  }

  MediaSnapshot _snap(MediaDetail m) => Fmt.snapshotOfDetail(m, lang: Store.i.settings.titleLanguage);

  void _bulkDownload(MediaDetail m, List<Episode> eps, Set<int> watched) {
    final unwatched = eps.where((e) => !watched.contains(e.number)).toList();
    final h = Store.i.history().where((h) => h.media.id == m.id).firstOrNull;
    final from = eps.indexWhere((e) => e.number == (h?.episode ?? eps.first.number));
    final next10 = eps.skip(from < 0 ? 0 : from).take(10).toList();
    void pick(List<Episode> list) {
      Navigator.pop(context);
      showEpisodeDownload(context, media: _snap(m), eps: _eps!, targets: list, minutes: m.duration);
    }

    pzSheet<void>(context, title: 'Download episodes', builder: (c) => ListView(shrinkWrap: true, children: [
          SheetOption('Next ${next10.length}', sub: 'From episode ${next10.first.number}', selected: false, onTap: () => pick(next10)),
          if (unwatched.isNotEmpty && unwatched.length != eps.length)
            SheetOption('Unwatched (${unwatched.length})', selected: false, onTap: () => pick(unwatched)),
          SheetOption('All ${eps.length}', selected: false, onTap: () => pick(eps)),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    if (_error != null) {
      return Scaffold(
        backgroundColor: Ink.ink0,
        body: SafeArea(
          child: Column(children: [
            Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.all(8), child: RoundIcon('arrowLeft', onTap: () => Navigator.pop(context)))),
            Expanded(child: Center(child: StatePanel(title: 'Couldn’t load this show', message: '$_error', icon: 'alert', action: 'Try again', onAction: _load))),
          ]),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Ink.ink0,
      body: m == null ? _skeleton() : _content(m),
    );
  }

  Widget _skeleton() => const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(kGutter),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Skeleton(height: 220, radius: 12),
            SizedBox(height: 16),
            Skeleton(height: 32, width: 260),
            SizedBox(height: 10),
            Skeleton(height: 14, width: 180),
          ]),
        ),
      );

  Widget _content(MediaDetail m) {
    final lang = Store.i.settings.titleLanguage;
    final title = Fmt.titleOf(m, lang: lang);
    final alt = Fmt.altTitleOf(m, lang: lang);
    final h = Store.i.history().where((h) => h.media.id == m.id).firstOrNull;
    final watched = Store.i.watched(m.id).toSet();
    final status = Store.i.libraryEntry(m.id)?.status;
    final eps = _eps?.episodes ?? const <Episode>[];
    final ordered = _newestFirst ? eps.reversed.toList() : eps;
    final unreleased = m.status == MediaStatus.notYetReleased;
    final top = MediaQuery.of(context).padding.top;
    final meta = [
      Fmt.formatLabel(m.format),
      Fmt.seasonLabel(m),
      Fmt.episodesLabel(m),
      Fmt.statusLabel(m.status),
      if (m.studios?.isNotEmpty ?? false) m.studios!.first,
    ].whereType<String>().toList();

    return RefreshIndicator(
      color: accentOf(context),
      onRefresh: () => _load(force: true),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 300 + top,
              child: Stack(fit: StackFit.expand, children: [
                PzImage(url: m.bannerImage ?? Fmt.coverOf(m)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x880C0B0A), Color(0x330C0B0A), Ink.ink0],
                      stops: [0, 0.4, 1],
                    ),
                  ),
                ),
                Positioned(top: top + 6, left: 8, child: RoundIcon('arrowLeft', onTap: () => Navigator.pop(context))),
                Positioned(
                  left: kGutter,
                  right: kGutter,
                  bottom: 0,
                  child: FadeIn(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      SizedBox(
                        width: 104,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: PzImage(url: Fmt.coverOf(m), radius: BorderRadius.circular(8), blurHashColor: hexColor(m.coverImage?.color)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (Fmt.scoreLabel(m.averageScore) != null) Tag('${Fmt.scoreLabel(m.averageScore)}', icon: 'bolt'),
                          const SizedBox(height: 8),
                          Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: display(30)),
                          if (alt != null) ...[
                            const SizedBox(height: 4),
                            Text(alt, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(12.5, color: Paper.paper3)),
                          ],
                        ]),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: FadeIn(
              delay: const Duration(milliseconds: 80),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 14, kGutter, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(meta.join('  ·  '), style: body(12.5, color: Paper.paper2)),
                  if (m.nextAiringEpisode != null) ...[
                    const SizedBox(height: 6),
                    Text('Episode ${m.nextAiringEpisode!.episode} airs in ${Fmt.countdown(m.nextAiringEpisode!.timeUntilAiring)}',
                        style: body(12.5, color: accentOf(context), weight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: unreleased
                          ? const PzBtn('Not out yet', icon: 'clock')
                          : PzBtn(
                              h != null ? 'Resume E${h.episode}' : (m.format == 'MOVIE' ? 'Play movie' : 'Play E1'),
                              icon: 'play',
                              primary: true,
                              onTap: () => go(context, WatchView(mediaId: m.id, episode: h?.episode ?? 1)),
                            ),
                    ),
                    const SizedBox(width: 10),
                    _ListButton(media: m, status: status),
                  ]),
                  if (m.genres?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 14),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final g in m.genres!) Tag(g)]),
                  ],
                  if ((m.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Pressable(
                      onTap: () => setState(() => _expanded = !_expanded),
                      scale: 0.99,
                      child: AnimatedSize(
                        duration: kMed,
                        curve: kEase,
                        alignment: Alignment.topCenter,
                        child: Text(
                          Fmt.plainText(m.description),
                          maxLines: _expanded ? null : 4,
                          overflow: _expanded ? null : TextOverflow.ellipsis,
                          style: body(13.5, color: Paper.paper2, height: 1.5),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
          if (!unreleased) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                'Episodes',
                subtitle: _eps == null ? 'Finding a source…' : '${eps.length} episodes${_eps!.hasDub ? ' · Sub & Dub' : ' · Sub'}',
                action: eps.length > 1 ? (_newestFirst ? 'Oldest first' : 'Newest first') : null,
                onAction: () => setState(() => _newestFirst = !_newestFirst),
              ),
            ),
            if (_eps != null && eps.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
                  child: _picked.isEmpty
                      ? Row(children: [
                          Expanded(child: Text('Hold an episode to select several', style: body(12, color: Paper.paper3))),
                          Pressable(
                            onTap: () => _bulkDownload(m, eps, watched),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const PzIcon('downloads', size: 16, color: Paper.paper2),
                              const SizedBox(width: 6),
                              Text('Download…', style: body(12.5, color: Paper.paper2, weight: FontWeight.w600)),
                            ]),
                          ),
                        ])
                      : Row(children: [
                          Expanded(child: Text('${_picked.length} selected', style: body(14, weight: FontWeight.w800))),
                          PzBtn('Watched', compact: true, icon: 'check', onTap: () {
                            final all = _picked.every(watched.contains);
                            Store.i.setWatched(m.id, _picked.toList(), !all);
                            setState(() => _picked.clear());
                          }),
                          const SizedBox(width: 6),
                          PzBtn('Download', compact: true, primary: true, icon: 'downloads', onTap: () {
                            final targets = eps.where((e) => _picked.contains(e.number)).toList();
                            setState(() => _picked.clear());
                            showEpisodeDownload(context, media: _snap(m), eps: _eps!, targets: targets, minutes: m.duration);
                          }),
                          RoundIcon('close', size: 34, iconSize: 15, filled: false, onTap: () => setState(() => _picked.clear())),
                        ]),
                ),
              ),
            if (_eps != null && !_eps!.available)
              SliverToBoxAdapter(
                child: StatePanel(
                  title: 'Not on the source yet',
                  message: 'PlayzAnime’s source doesn’t carry this title. Niche and Chinese releases are often added late.',
                  icon: 'clock',
                  action: 'Check again',
                  onAction: () => _load(force: true),
                ),
              ),
            if (_epsError != null)
              SliverToBoxAdapter(child: StatePanel(title: 'Couldn’t list episodes', message: '$_epsError', icon: 'alert', action: 'Try again', onAction: _load))
            else if (_eps != null && !_eps!.available)
              const SliverToBoxAdapter(child: SizedBox.shrink())
            else if (_eps == null)
              SliverList.builder(
                itemCount: 4,
                itemBuilder: (_, __) => const Padding(padding: EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10), child: Skeleton(height: 66)),
              )
            else
              SliverList.builder(
                itemCount: ordered.length,
                itemBuilder: (c, i) {
                  final e = ordered[i];
                  final seen = watched.contains(e.number);
                  final picked = _picked.contains(e.number);
                  final resume = h?.episode == e.number ? h : null;
                  return FadeIn(
                    delay: Duration(milliseconds: i < 10 ? 25 * i : 0),
                    child: Pressable(
                      scale: 0.98,
                      onTap: _picked.isNotEmpty
                          ? () => setState(() => picked ? _picked.remove(e.number) : _picked.add(e.number))
                          : () => go(context, WatchView(mediaId: m.id, episode: e.number)),
                      onLongPress: () {
                        HapticFeedback.selectionClick();
                        setState(() => _picked.add(e.number));
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
                        child: Row(children: [
                          SizedBox(
                            width: 128,
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Stack(fit: StackFit.expand, children: [
                                  EpisodeThumb(episode: e, media: m),
                                  if (picked)
                                    Container(
                                      decoration: BoxDecoration(border: Border.all(color: accentOf(context), width: 2.5), color: Colors.black.withAlpha(0x66)),
                                      alignment: Alignment.center,
                                      child: PzIcon('check', size: 22, color: accentOf(context)),
                                    ),
                                  if (seen) Container(color: Colors.black.withAlpha(0x88), alignment: Alignment.center, child: const PzIcon('check', size: 20, color: Paper.paper2)),
                                  if (resume != null && resume.duration > 0)
                                    Positioned(left: 0, right: 0, bottom: 0, child: ProgressLine(resume.position / resume.duration)),
                                ]),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Episode ${e.number}', style: body(11.5, color: Paper.paper3, weight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              if (!RegExp(r'^episode\s*\d+$', caseSensitive: false).hasMatch(e.title.trim()))
                                Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(14, weight: FontWeight.w600, color: seen ? Paper.paper3 : Paper.paper, height: 1.25)),
                              if (e.dubUrl != null) ...[const SizedBox(height: 4), const Tag('DUB')],
                            ]),
                          ),
                          DownloadMark(
                            jobKey: Downloader.episodeKey(m.id, e.number),
                            done: () => Downloader.i.episodeFile(m.id, e.number) != null,
                            onDownload: () => showEpisodeDownload(context, media: _snap(m), eps: _eps!, targets: [e], minutes: m.duration),
                          ),
                        ]),
                      ),
                    ),
                  );
                },
              ),
          ],
          if (m.relations?.isNotEmpty ?? false) ...[
            const SliverToBoxAdapter(child: SectionHeader('Related')),
            SliverToBoxAdapter(
              child: Shelf(
                height: 246,
                itemCount: m.relations!.length,
                itemBuilder: (c, i) {
                  final r = m.relations![i];
                  return PosterCard(
                    media: r.node,
                    title: Fmt.titleOf(r.node, lang: lang),
                    meta: Fmt.formatLabel(r.node.format) ?? '',
                    onTap: () => go(context, Fmt.isManga(r.node) ? MangaDetailView(mediaId: r.node.id) : SeriesView(mediaId: r.node.id)),
                  );
                },
              ),
            ),
          ],
          if (m.recommendations?.isNotEmpty ?? false) ...[
            const SliverToBoxAdapter(child: SectionHeader('If you like this')),
            SliverToBoxAdapter(
              child: Shelf(
                height: 246,
                itemCount: m.recommendations!.length,
                itemBuilder: (c, i) {
                  final r = m.recommendations![i];
                  return PosterCard(media: r, title: Fmt.titleOf(r, lang: lang), onTap: () => go(context, SeriesView(mediaId: r.id)));
                },
              ),
            ),
          ],
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.bottom + 32)),
        ],
      ),
    );
  }
}

/// Library status picker. Port of `ListButton.tsx`.
class _ListButton extends StatelessWidget {
  const _ListButton({required this.media, required this.status});

  final MediaDetail media;
  final ListStatus? status;

  @override
  Widget build(BuildContext context) => PzBtn(
        status?.label ?? 'Add to list',
        icon: status == null ? 'plus' : 'bookmarkFilled',
        onTap: () => pickListStatus(context, Fmt.snapshotOfDetail(media, lang: Store.i.settings.titleLanguage), status),
      );
}

void pickListStatus(BuildContext context, MediaSnapshot snap, ListStatus? current) {
  pzSheet<void>(context, title: 'Save to library', builder: (c) => ListView(shrinkWrap: true, children: [
        for (final s in ListStatus.values)
          SheetOption(s.label, selected: s == current, onTap: () {
            Navigator.pop(c);
            Store.i.setLibrary(snap, s);
            toast(context, 'Saved to ${s.label}');
          }),
        if (current != null)
          SheetOption('Remove from library', selected: false, onTap: () {
            Navigator.pop(c);
            Store.i.removeLibrary(snap.id);
            toast(context, 'Removed from library');
          }),
      ]));
}
