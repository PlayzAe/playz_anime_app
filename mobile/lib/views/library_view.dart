import 'package:flutter/material.dart' hide Ink;

import '../app.dart';
import '../models/local.dart';
import '../models/media.dart';
import '../services/format.dart';
import '../services/store.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_image.dart';
import 'downloads_list.dart';
import 'manga_detail_view.dart';
import 'series_view.dart';
import 'watch_view.dart';

/// Library. Port of `Library.tsx`: your lists by status, plus history.
class LibraryView extends StatefulWidget {
  const LibraryView({super.key, required this.onTab});

  final ValueChanged<int> onTab;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  MediaType _type = MediaType.anime;
  ListStatus? _status; // null = all
  bool _history = false;

  @override
  void initState() {
    super.initState();
    Store.i.addListener(_onStore);
  }

  @override
  void dispose() {
    Store.i.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final all = Store.i.library().where((e) => e.media.type == _type).toList();
    final shown = _status == null ? all : all.where((e) => e.status == _status).toList();
    return Column(children: [
      const TabTopBar(title: 'Library'),
      Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 8),
        child: Row(children: [
          Segmented<MediaType>(
            value: _type,
            options: const [(MediaType.anime, 'Anime'), (MediaType.manga, 'Manga')],
            onChanged: (t) => setState(() => _type = t),
          ),
          const Spacer(),
          Chip2('Downloads', onTap: () => go(context, DownloadsView(initial: _type == MediaType.anime ? 'Anime' : 'Everything'))),
          const SizedBox(width: 8),
          Chip2('History', on: _history, onTap: () => setState(() => _history = !_history)),
        ]),
      ),
      if (!_history)
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 6),
            children: [
              Padding(padding: const EdgeInsets.only(right: 8), child: Chip2('All ${all.length}', on: _status == null, onTap: () => setState(() => _status = null))),
              for (final s in ListStatus.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip2('${s.label} ${all.where((e) => e.status == s).length}', on: _status == s, onTap: () => setState(() => _status = s)),
                ),
            ],
          ),
        ),
      const Divider(height: 1, color: Lines.line),
      Expanded(
        child: AnimatedSwitcher(
          duration: kMed,
          child: _history ? _historyList() : _grid(shown),
        ),
      ),
    ]);
  }

  Widget _grid(List<LibraryEntry> items) {
    if (items.isEmpty) {
      return StatePanel(
        key: const ValueKey('empty'),
        title: _status == null ? 'Nothing saved yet' : 'Nothing in ${_status!.label}',
        message: 'Tap “Add to list” on any ${_type == MediaType.anime ? 'show' : 'title'} to keep track of it here.',
        icon: 'library',
        action: 'Browse',
        onAction: () => widget.onTab(_type == MediaType.anime ? 0 : 1),
      );
    }
    // One pass over history instead of a search per poster.
    final last = <int, HistoryEntry>{};
    for (final h in Store.i.history()) {
      last.putIfAbsent(h.media.id, () => h);
    }
    return GridView.builder(
      key: ValueKey('grid$_type$_status'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(kGutter),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: MediaQuery.sizeOf(context).width > 700 ? 160 : 130, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 0.56),
      itemCount: items.length,
      itemBuilder: (c, i) {
        final e = items[i];
        final h = last[e.media.id];
        return Pressable(
            onTap: () => go(context, e.media.type == MediaType.manga ? MangaDetailView(mediaId: e.media.id) : SeriesView(mediaId: e.media.id)),
            onLongPress: () => pickListStatus(context, e.media, e.status),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(fit: StackFit.expand, children: [
                  PzImage(url: e.media.cover, radius: BorderRadius.circular(7)),
                  Positioned(left: 6, top: 6, child: Tag(e.status.label)),
                  if (h != null) Positioned(left: 6, bottom: 6, child: Tag('E${h.episode}')),
                ]),
              ),
              const SizedBox(height: 6),
              Text(e.media.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(12.5, weight: FontWeight.w700, height: 1.2)),
            ]),
        );
      },
    );
  }

  Widget _historyList() {
    final watch = Store.i.history();
    final read = Store.i.reading();
    final rows = _type == MediaType.anime ? watch.length : read.length;
    if (rows == 0) {
      return const StatePanel(key: ValueKey('nohist'), title: 'No history yet', icon: 'history');
    }
    return ListView.builder(
      key: ValueKey('hist$_type'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows,
      itemBuilder: (c, i) {
        final isAnime = _type == MediaType.anime;
        final media = isAnime ? watch[i].media : read[i].media;
        final line = isAnime
            ? 'Episode ${watch[i].episode} · ${Fmt.clock((watch[i].duration - watch[i].position).clamp(0, double.infinity))} left'
            : 'Chapter ${read[i].chapterNumber ?? '?'} · page ${read[i].page + 1}/${read[i].pages}';
        final at = isAnime ? watch[i].updatedAt : read[i].updatedAt;
        return FadeIn(
          delay: Duration(milliseconds: 20 * (i % 10)),
          child: Dismissible(
            key: ValueKey('h${media.id}'),
            direction: DismissDirection.endToStart,
            background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), color: Ink.ink2, child: Text('Remove', style: body(13, color: Paper.paper2))),
            onDismissed: (_) => isAnime ? Store.i.removeHistory(media.id) : Store.i.removeReading(media.id),
            child: Pressable(
              scale: 0.98,
              onTap: () => go(context, isAnime ? WatchView(mediaId: media.id, episode: watch[i].episode) : MangaDetailView(mediaId: media.id)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: kGutter, vertical: 7),
                child: Row(children: [
                  SizedBox(
                    width: isAnime ? 112 : 50,
                    child: AspectRatio(
                      aspectRatio: isAnime ? 16 / 9 : 2 / 3,
                      child: PzImage(url: (isAnime ? watch[i].thumbnail : null) ?? media.banner ?? media.cover, radius: BorderRadius.circular(6)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(media.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(14, weight: FontWeight.w700)),
                      Text(line, style: body(12.5, color: Paper.paper2)),
                      Text(Fmt.relativeTime(at), style: body(11.5, color: Paper.paper3)),
                      if (isAnime && watch[i].duration > 0) ...[
                        const SizedBox(height: 6),
                        ProgressLine(watch[i].position / watch[i].duration),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
