import 'package:flutter/material.dart' hide Ink;

import '../app.dart';
import '../models/media.dart';
import '../services/anilist.dart';
import '../services/format.dart';
import '../services/store.dart';
import '../sources/manga/providers.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_image.dart';
import 'browse_view.dart';
import 'home_view.dart';
import 'manga_detail_view.dart';
import 'reader_view.dart';
import 'search_view.dart';

/// Manga, manhwa, manhua. Desktop `MangaHome.tsx` content, laid out the way
/// Mihon does it on a phone: Discover, Library, History and Sources tabs.
class MangaHomeView extends StatefulWidget {
  const MangaHomeView({super.key});

  @override
  State<MangaHomeView> createState() => _MangaHomeViewState();
}

class _MangaHomeViewState extends State<MangaHomeView> {
  int _tab = 0;
  MangaFeed? _feed;
  Object? _error;

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

  bool _refreshed = false;

  Future<void> _load({bool force = false}) async {
    try {
      final f = await AniList.i.mangaHome(force: force);
      if (mounted) setState(() => _feed = f);
      // The first answer may be the saved copy; swap in fresh data quietly.
      if (!force && !_refreshed) {
        _refreshed = true;
        Future<void>.delayed(const Duration(milliseconds: 600), () => _load(force: true));
      }
    } catch (e) {
      if (mounted && _feed == null) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabTopBar(
        title: 'Manga',
        subtitle: 'Manga · Manhwa · Manhua',
        onSearch: () => go(context, const SearchView(initial: BrowseFilters(type: MediaType.manga))),
      ),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: kGutter),
          children: [
            for (final (i, label) in const ['Discover', 'Library', 'History', 'Browse'].indexed)
              Padding(
                padding: const EdgeInsets.only(right: 18),
                child: Pressable(
                  onTap: () => setState(() => _tab = i),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(label, style: body(15, weight: _tab == i ? FontWeight.w800 : FontWeight.w500, color: _tab == i ? Paper.paper : Paper.paper3)),
                    const SizedBox(height: 6),
                    AnimatedContainer(duration: kMed, curve: kEase, height: 2, width: _tab == i ? 22 : 0, color: accentOf(context)),
                  ]),
                ),
              ),
          ],
        ),
      ),
      const Divider(height: 1, color: Lines.line),
      Expanded(
        child: AnimatedSwitcher(
          duration: kMed,
          switchInCurve: kEase,
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
          child: KeyedSubtree(
            key: ValueKey(_tab),
            child: switch (_tab) {
              0 => _discover(),
              1 => _library(),
              2 => _history(),
              _ => const _BrowsePane(),
            },
          ),
        ),
      ),
    ]);
  }

  String _t(Media m) => Fmt.titleOf(m, lang: Store.i.settings.titleLanguage);

  Widget _shelf(List<Media> list) => Shelf(
        height: 246,
        itemCount: list.length,
        itemBuilder: (c, i) => FadeIn(
          delay: Duration(milliseconds: 30 * (i % 6)),
          child: PosterCard(
            media: list[i],
            title: _t(list[i]),
            meta: [Fmt.mangaKind(list[i]), if (list[i].chapters != null) '${list[i].chapters} ch'].whereType<String>().join(' · '),
            onTap: () => go(context, MangaDetailView(mediaId: list[i].id)),
          ),
        ),
      );

  Widget _discover() {
    final f = _feed;
    if (f == null && _error != null) {
      return Center(child: StatePanel(title: 'Couldn’t load manga', message: '$_error', icon: 'offline', action: 'Try again', onAction: () => _load(force: true)));
    }
    final reading = Store.i.reading();
    return RefreshIndicator(
      color: accentOf(context),
      onRefresh: () => _load(force: true),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        children: [
          if (f != null && f.trending.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 12), child: _Spotlight(media: f.trending.first, title: _t(f.trending.first))),
          if (reading.isNotEmpty) ...[
            const SectionHeader('Continue reading'),
            Shelf(
              height: 246,
              itemCount: reading.length.clamp(0, 12),
              itemBuilder: (c, i) {
                final r = reading[i];
                return Pressable(
                  onTap: () => go(context, MangaDetailView(mediaId: r.media.id)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    AspectRatio(
                      aspectRatio: 2 / 3,
                      child: Stack(fit: StackFit.expand, children: [
                        PzImage(url: r.media.cover, radius: BorderRadius.circular(7)),
                        Positioned(left: 6, bottom: 6, child: Tag('Ch ${r.chapterNumber ?? '?'}')),
                      ]),
                    ),
                    const SizedBox(height: 7),
                    Text(r.media.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(13, weight: FontWeight.w700, height: 1.2)),
                    Text('Page ${r.page + 1}/${r.pages}', style: body(11.5, color: Paper.paper3)),
                  ]),
                );
              },
            ),
          ],
          const SectionHeader('Trending now', subtitle: 'What readers are on this week'),
          f == null ? const PosterSkeletons() : _shelf(f.trending.skip(1).toList()),
          const SectionHeader('Popular manhwa', subtitle: 'Korean webtoons and full-colour series'),
          f == null ? const PosterSkeletons() : _shelf(f.manhwa),
          const SectionHeader('Browse by genre'),
          GenreGrid(type: MediaType.manga),
          const SectionHeader('All-time favourites'),
          f == null ? const PosterSkeletons() : _shelf(f.top),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _library() {
    final items = Store.i.library().where((e) => e.media.type == MediaType.manga).toList();
    if (items.isEmpty) {
      return const Center(child: StatePanel(title: 'Your manga library is empty', message: 'Open any title and tap “Add to list” to keep it here.', icon: 'library'));
    }
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(kGutter),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 0.56),
      itemCount: items.length,
      itemBuilder: (c, i) {
        final e = items[i];
        final unread = Store.i.readingEntry(e.media.id);
        return FadeIn(
          delay: Duration(milliseconds: 25 * (i % 9)),
          child: Pressable(
            onTap: () => go(context, MangaDetailView(mediaId: e.media.id)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(fit: StackFit.expand, children: [
                  PzImage(url: e.media.cover, radius: BorderRadius.circular(7)),
                  Positioned(left: 6, top: 6, child: Tag(e.status.label)),
                  if (unread != null) Positioned(left: 6, bottom: 6, child: Tag('Ch ${unread.chapterNumber ?? '?'}')),
                ]),
              ),
              const SizedBox(height: 6),
              Text(e.media.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(12.5, weight: FontWeight.w700, height: 1.2)),
            ]),
          ),
        );
      },
    );
  }

  Widget _history() {
    final items = Store.i.reading();
    if (items.isEmpty) {
      return const Center(child: StatePanel(title: 'Nothing read yet', message: 'Chapters you open show up here so you can jump back in.', icon: 'history'));
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      itemBuilder: (c, i) {
        final r = items[i];
        return FadeIn(
          delay: Duration(milliseconds: 25 * (i % 10)),
          child: Pressable(
            scale: 0.98,
            onTap: () => go(context, MangaDetailView(mediaId: r.media.id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: kGutter, vertical: 7),
              child: Row(children: [
                SizedBox(width: 52, child: AspectRatio(aspectRatio: 2 / 3, child: PzImage(url: r.media.cover, radius: BorderRadius.circular(5)))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.media.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(14, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Chapter ${r.chapterNumber ?? '?'} · page ${r.page + 1} of ${r.pages}', style: body(12.5, color: Paper.paper2)),
                    Text(Fmt.relativeTime(r.updatedAt), style: body(11.5, color: Paper.paper3)),
                  ]),
                ),
                RoundIcon('trash', iconSize: 16, size: 36, filled: false, color: Paper.paper3, onTap: () => Store.i.removeReading(r.media.id)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Spotlight extends StatelessWidget {
  const _Spotlight({required this.media, required this.title});

  final Media media;
  final String title;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => go(context, MangaDetailView(mediaId: media.id)),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: kGutter),
          height: 200,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Ink.ink2),
          child: Stack(fit: StackFit.expand, children: [
            PzImage(url: media.bannerImage ?? Fmt.coverOf(media)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xF00C0B0A), Color(0x330C0B0A)]),
              ),
            ),
            Positioned(
              left: 14,
              top: 14,
              bottom: 14,
              child: AspectRatio(aspectRatio: 2 / 3, child: PzImage(url: Fmt.coverOf(media), radius: BorderRadius.circular(7))),
            ),
            Positioned(
              left: 136,
              right: 14,
              bottom: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('No. 1 trending', style: body(11.5, color: accentOf(context), weight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: display(26)),
                const SizedBox(height: 6),
                Text([Fmt.mangaKind(media), Fmt.scoreLabel(media.averageScore) == null ? null : 'Score ${Fmt.scoreLabel(media.averageScore)}'].whereType<String>().join(' · '),
                    style: body(12, color: Paper.paper2)),
              ]),
            ),
          ]),
        ),
      );
}

/// Mihon's Browse → Sources: each source, whether it answers right now, an
/// on/off switch, and which one is the default.
class _SourcesTab extends StatefulWidget {
  const _SourcesTab();

  @override
  State<_SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends State<_SourcesTab> {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check({bool force = false}) async {
    setState(() => _checking = true);
    await MangaProviders.i.checkHealth(force: force);
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final pref = Store.i.settings.mangaProvider;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 10),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 10),
          child: Row(children: [
            Expanded(
              child: Text('PlayzAnime asks every enabled source and reads from the one furthest along. Pin one per title from its chapter list.',
                  style: body(12.5, color: Paper.paper3, height: 1.4)),
            ),
            const SizedBox(width: 10),
            PzBtn('Check', icon: 'refresh', compact: true, busy: _checking, onTap: () => _check(force: true)),
          ]),
        ),
        for (final (i, p) in kProviders.indexed)
          FadeIn(
            delay: Duration(milliseconds: 40 * i),
            child: Container(
              margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Ink.ink1, borderRadius: BorderRadius.circular(10), border: Border.all(color: Lines.line)),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Ink.ink3, borderRadius: BorderRadius.circular(9)),
                  child: Text(p.name[0], style: display(22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(p.name, style: body(15, weight: FontWeight.w700))),
                      if (pref == p.id) ...[const SizedBox(width: 6), const Tag('Default')],
                    ]),
                    const SizedBox(height: 2),
                    Text(p.note, style: body(12, color: Paper.paper3)),
                    const SizedBox(height: 4),
                    _HealthLine(provider: p.id, checking: _checking),
                  ]),
                ),
                PzToggle(value: Store.i.isSourceEnabled(p.id), onChanged: (v) => Store.i.setSourceEnabled(p.id, v)),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 6, kGutter, 0),
          child: Text('Default source', style: body(14, weight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kGutter),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            Chip2('Auto (recommended)', on: pref == 'auto', onTap: () => Store.i.patchSettings((s) => s.copyWith(mangaProvider: 'auto'))),
            for (final p in kProviders) Chip2(p.name, on: pref == p.id, onTap: () => Store.i.patchSettings((s) => s.copyWith(mangaProvider: p.id))),
          ]),
        ),
        const InstalledSourcesList(),
        const SizedBox(height: 32),
      ],
    );
  }
}

/// Mihon's Browse: Sources (built-in + installed) and Extensions (the repo).
/// Browse → the built-in sources and installed extensions. Installing and
/// updating extensions lives in Settings → Manga → Extensions.
class _BrowsePane extends StatelessWidget {
  const _BrowsePane();

  @override
  Widget build(BuildContext context) => const _SourcesTab();
}

class _HealthLine extends StatelessWidget {
  const _HealthLine({required this.provider, required this.checking});

  final String provider;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final h = MangaProviders.i.health[provider];
    final (color, text) = h == null
        ? (Paper.paper4, checking ? 'Checking…' : 'Not checked')
        : h.ok
            ? (Pulse.good, 'Online · ${h.ms} ms')
            : (Pulse.bad, 'Not answering');
    return Row(children: [
      AnimatedContainer(duration: kMed, width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(text, style: body(11.5, color: color, weight: FontWeight.w600)),
    ]);
  }
}

/// Opens a chapter from anywhere (history rows reuse it).
void openChapter(BuildContext context, int mediaId, List<MChapter> chapters, int index) =>
    go(context, ReaderView(mediaId: mediaId, chapters: chapters, index: index));

/// Status colours from `tokens.css` (`--good`, `--warn`, `--bad`).
abstract final class Pulse {
  static const good = Color(0xFF93C48D);
  static const warn = Color(0xFFE8B85E);
  static const bad = Color(0xFFEA6B60);
}

