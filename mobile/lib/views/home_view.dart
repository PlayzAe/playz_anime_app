import 'dart:async';

import 'package:flutter/material.dart' hide Ink;

import '../app.dart';
import '../models/local.dart';
import '../models/media.dart';
import '../services/anilist.dart';
import '../services/format.dart';
import '../services/store.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_icon.dart';
import '../widgets/pz_image.dart';
import 'search_view.dart';
import 'series_view.dart';
import 'watch_view.dart';

const kGenres = [
  'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Romance', 'Sci-Fi', 'Slice of Life',
  'Mystery', 'Sports', 'Supernatural', 'Horror', 'Psychological', 'Mecha', 'Thriller',
];

/// Anime home. Port of `Home.tsx`.
class HomeView extends StatefulWidget {
  const HomeView({super.key, required this.onTab});

  final ValueChanged<int> onTab;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  HomeFeed? _feed;
  List<AiringItem>? _aired;
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

  Future<void> _load({bool force = false}) async {
    try {
      final feed = await AniList.i.home(force: force);
      if (mounted) setState(() => _feed = feed);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final aired = await AniList.i.schedule(now - 36 * 3600, now);
      if (mounted) setState(() => _aired = aired.reversed.toList());
    } catch (_) {}
  }

  String _t(Media m) => Fmt.titleOf(m, lang: Store.i.settings.titleLanguage);

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    final history = Store.i.history();
    if (feed == null && _error != null) {
      return Column(children: [
        TabTopBar(title: 'Anime', onSearch: () => go(context, const SearchView())),
        Expanded(
          child: Center(
            child: StatePanel(
              title: 'Couldn’t load the anime catalogue',
              message: '$_error',
              icon: 'offline',
              action: 'Try again',
              onAction: () {
                setState(() => _error = null);
                _load(force: true);
              },
            ),
          ),
        ),
      ]);
    }
    final slides = <HeroSlide>[
      if (history.isNotEmpty) HeroSlide.continueWatching(context, history.first),
      if (feed != null)
        for (final (i, m) in feed.trending.where((m) => m.bannerImage != null).take(history.isEmpty ? 5 : 4).indexed)
          HeroSlide.trending(context, m, i + 1, _t(m)),
    ];
    return RefreshIndicator(
      color: accentOf(context),
      backgroundColor: Ink.ink2,
      onRefresh: () => _load(force: true),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(child: TabTopBar(title: 'Anime', onSearch: () => go(context, const SearchView()))),
          SliverToBoxAdapter(
            child: slides.isEmpty
                ? const Padding(padding: EdgeInsets.all(kGutter), child: Skeleton(height: 420, radius: 12))
                : HeroCarousel(slides: slides),
          ),
          if (history.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader('Continue watching')),
            SliverToBoxAdapter(child: ContinueShelf(items: history.take(12).toList())),
          ],
          if (_aired != null && _aired!.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader('Aired recently', subtitle: 'New episodes from the last day and a half')),
            SliverToBoxAdapter(
              child: Shelf(
                height: 246,
                itemCount: _aired!.length,
                itemBuilder: (c, i) {
                  final a = _aired![i];
                  return FadeIn(
                    delay: Duration(milliseconds: 30 * (i % 6)),
                    child: PosterCard(
                      media: a.media,
                      title: _t(a.media),
                      badge: 'E${a.episode}',
                      meta: Fmt.relativeTime(a.airingAt * 1000),
                      // New to the show? Open its page so it starts from episode 1, not the latest.
                      onTap: () => go(
                          context,
                          Store.i.history().any((h) => h.media.id == a.media.id)
                              ? WatchView(mediaId: a.media.id, episode: a.episode)
                              : SeriesView(mediaId: a.media.id)),
                    ),
                  );
                },
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SectionHeader('Top 10 this week', subtitle: 'Ranked by AniList activity over the last few days')),
          SliverToBoxAdapter(
            child: feed == null
                ? const PosterSkeletons()
                : Shelf(
                    height: 236,
                    itemWidth: 150,
                    gap: 4,
                    itemCount: feed.trending.take(10).length,
                    itemBuilder: (c, i) => FadeIn(delay: Duration(milliseconds: 40 * (i % 6)), child: _Ranked(media: feed.trending[i], rank: i + 1, title: _t(feed.trending[i]))),
                  ),
          ),
          SliverToBoxAdapter(
            child: SectionHeader(
              feed == null ? 'This season' : '${Fmt.seasonName(feed.seasonLabel.season)} ${feed.seasonLabel.year}',
              subtitle: 'The most popular shows airing this season',
              action: feed == null ? null : 'All of it',
              onAction: feed == null
                  ? null
                  : () => go(
                        context,
                        SearchView(
                          initial: BrowseFilters(
                            type: MediaType.anime,
                            season: feed.seasonLabel.season,
                            year: feed.seasonLabel.year,
                            sort: SortKey.popularityDesc,
                          ),
                        ),
                      ),
            ),
          ),
          SliverToBoxAdapter(child: feed == null ? const PosterSkeletons() : _posters(feed.season)),
          const SliverToBoxAdapter(child: SectionHeader('Browse by genre')),
          SliverToBoxAdapter(child: GenreGrid(type: MediaType.anime)),
          const SliverToBoxAdapter(child: SectionHeader('All-time favourites', subtitle: 'Highest rated on AniList, with enough viewers to count')),
          SliverToBoxAdapter(child: feed == null ? const PosterSkeletons() : _posters(feed.top)),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _posters(List<Media> list) => Shelf(
        height: 246,
        itemCount: list.length,
        itemBuilder: (c, i) => FadeIn(
          delay: Duration(milliseconds: 30 * (i % 6)),
          child: PosterCard(media: list[i], title: _t(list[i]), onTap: () => go(context, SeriesView(mediaId: list[i].id))),
        ),
      );
}

class _Ranked extends StatelessWidget {
  const _Ranked({required this.media, required this.rank, required this.title});

  final Media media;
  final int rank;
  final String title;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => go(context, SeriesView(mediaId: media.id)),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            bottom: 34,
            child: Text('$rank',
                style: display(96, color: Ink.ink0, height: 1).copyWith(
                  shadows: const [Shadow(color: Paper.paper3, blurRadius: 0, offset: Offset(1.5, 1.5)), Shadow(color: Paper.paper3, offset: Offset(-1.5, -1.5))],
                )),
          ),
          Positioned(
            left: 42,
            right: 6,
            top: 0,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AspectRatio(aspectRatio: 2 / 3, child: PzImage(url: Fmt.coverOf(media), radius: BorderRadius.circular(7), blurHashColor: hexColor(media.coverImage?.color))),
              const SizedBox(height: 6),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(12.5, weight: FontWeight.w700)),
            ]),
          ),
        ]),
      );
}

// ── Hero ────────────────────────────────────────────────────────────────────

class HeroSlide {
  const HeroSlide({
    required this.key,
    required this.kicker,
    required this.title,
    this.native,
    this.banner,
    this.cover,
    this.meta = const [],
    this.progress,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onSecondary,
    this.secondaryLabel = 'Details',
    this.kickerIcon,
  });

  final String key;
  final String kicker;
  final String? kickerIcon;
  final String title;
  final String? native;
  final String? banner;
  final String? cover;
  final List<String> meta;
  final double? progress;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  factory HeroSlide.continueWatching(BuildContext context, HistoryEntry h) {
    final left = (h.duration - h.position).clamp(0, double.infinity);
    return HeroSlide(
      key: 'continue-${h.media.id}',
      kicker: 'Continue watching · Episode ${h.episode}',
      kickerIcon: 'history',
      title: h.media.title,
      native: h.media.native,
      banner: h.media.banner ?? h.thumbnail,
      cover: h.media.cover,
      meta: ['${Fmt.clock(left)} left', h.audio.wire.toUpperCase()],
      progress: h.duration > 0 ? h.position / h.duration : null,
      primaryLabel: 'Resume E${h.episode}',
      onPrimary: () => go(context, WatchView(mediaId: h.media.id, episode: h.episode)),
      secondaryLabel: 'Episodes',
      onSecondary: () => go(context, SeriesView(mediaId: h.media.id)),
    );
  }

  factory HeroSlide.trending(BuildContext context, Media m, int rank, String title) => HeroSlide(
        key: 't-${m.id}',
        kicker: 'No. $rank trending this week',
        title: title,
        native: m.title.native,
        banner: m.bannerImage,
        cover: Fmt.coverOf(m),
        meta: [
          if (Fmt.formatLabel(m.format) != null) Fmt.formatLabel(m.format)!,
          if (Fmt.mediaYear(m) != null) '${Fmt.mediaYear(m)}',
          if (Fmt.episodesLabel(m) != null) Fmt.episodesLabel(m)!,
          if (Fmt.scoreLabel(m.averageScore) != null) 'Score ${Fmt.scoreLabel(m.averageScore)}',
        ],
        primaryLabel: m.format == 'MOVIE' ? 'Play movie' : 'Play E1',
        onPrimary: () => go(context, WatchView(mediaId: m.id)),
        onSecondary: () => go(context, SeriesView(mediaId: m.id)),
      );
}

class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.slides});

  final List<HeroSlide> slides;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final _pc = PageController();
  int _i = 0;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  void _restart() {
    _auto?.cancel();
    _auto = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || !_pc.hasClients || widget.slides.length < 2) return;
      _pc.animateToPage((_i + 1) % widget.slides.length, duration: const Duration(milliseconds: 600), curve: kEase);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showNative = Store.i.settings.showNativeTitles;
    return SizedBox(
      height: 460,
      child: Stack(children: [
        NotificationListener<ScrollStartNotification>(
          onNotification: (n) {
            if (n.dragDetails != null) _restart();
            return false;
          },
          child: PageView.builder(
            controller: _pc,
            itemCount: widget.slides.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (c, i) => _HeroPage(slide: widget.slides[i], showNative: showNative, active: i == _i),
          ),
        ),
        if (widget.slides.length > 1)
          Positioned(
            right: kGutter,
            bottom: 10,
            child: Row(children: [
              for (var i = 0; i < widget.slides.length; i++)
                Pressable(
                  onTap: () => _pc.animateToPage(i, duration: const Duration(milliseconds: 500), curve: kEase),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Column(children: [
                      Text((i + 1).toString().padLeft(2, '0'),
                          style: body(11.5, weight: FontWeight.w700, color: i == _i ? Paper.paper : Paper.paper4)),
                      const SizedBox(height: 4),
                      AnimatedContainer(duration: kMed, width: 22, height: 2, color: i == _i ? Paper.paper : Lines.line2),
                    ]),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}

class _HeroPage extends StatelessWidget {
  const _HeroPage({required this.slide, required this.showNative, required this.active});

  final HeroSlide slide;
  final bool showNative;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final s = slide;
    final jp = showNative && s.native != null && RegExp(r'[぀-ヿ一-鿿]').hasMatch(s.native!) ? s.native! : null;
    return Stack(fit: StackFit.expand, children: [
      if (s.banner != null || s.cover != null)
        AnimatedScale(
          scale: active ? 1.0 : 1.08,
          duration: const Duration(milliseconds: 1400),
          curve: kEase,
          child: PzImage(url: s.banner ?? s.cover!, alignment: Alignment.center),
        ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x330C0B0A), Color(0x660C0B0A), Color(0xF20C0B0A), Ink.ink0],
            stops: [0, 0.35, 0.78, 1],
          ),
        ),
      ),
      if (jp != null)
        Positioned(
          right: kGutter,
          top: 18,
          bottom: 80,
          child: RotatedBox(
            quarterTurns: 0,
            child: Column(
              children: [
                for (final ch in jp.characters.take(12))
                  Text(ch, style: TextStyle(fontSize: 18, height: 1.15, color: Paper.paper.withAlpha(0x8C), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      Positioned(
        left: kGutter,
        right: kGutter + (jp != null ? 34 : 0),
        bottom: 44,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: const Duration(milliseconds: 500),
          child: AnimatedSlide(
            offset: active ? Offset.zero : const Offset(0, 0.06),
            duration: const Duration(milliseconds: 500),
            curve: kEase,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                if (s.kickerIcon != null) ...[PzIcon(s.kickerIcon!, size: 14, color: Paper.paper2), const SizedBox(width: 6)],
                Flexible(child: Text(s.kicker, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(12.5, color: Paper.paper2, weight: FontWeight.w600))),
              ]),
              const SizedBox(height: 8),
              Text(s.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: display(44)),
              const SizedBox(height: 10),
              Text(s.meta.join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(12.5, color: Paper.paper2)),
              if (s.progress != null) ...[
                const SizedBox(height: 10),
                SizedBox(width: 180, child: ProgressLine(s.progress!)),
              ],
              const SizedBox(height: 16),
              Row(children: [
                PzBtn(s.primaryLabel, icon: 'play', primary: true, onTap: s.onPrimary),
                const SizedBox(width: 10),
                PzBtn(s.secondaryLabel, onTap: s.onSecondary),
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }
}

// ── Continue watching ───────────────────────────────────────────────────────

class ContinueShelf extends StatelessWidget {
  const ContinueShelf({super.key, required this.items});

  final List<HistoryEntry> items;

  @override
  Widget build(BuildContext context) => Shelf(
        height: 172,
        itemWidth: 236,
        itemCount: items.length,
        itemBuilder: (c, i) {
          final h = items[i];
          final left = (h.duration - h.position).clamp(0, double.infinity);
          return FadeIn(
            delay: Duration(milliseconds: 40 * (i % 5)),
            child: Pressable(
              onTap: () => go(context, WatchView(mediaId: h.media.id, episode: h.episode)),
              onLongPress: () => pzSheet<void>(context, title: h.media.title, builder: (c2) => ListView(shrinkWrap: true, children: [
                    SheetOption('Series details', selected: false, onTap: () {
                      Navigator.pop(c2);
                      go(context, SeriesView(mediaId: h.media.id));
                    }),
                    SheetOption('Remove from Continue watching', selected: false, onTap: () {
                      Navigator.pop(c2);
                      Store.i.removeHistory(h.media.id);
                    }),
                  ])),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Stack(fit: StackFit.expand, children: [
                      PzImage(url: h.thumbnail ?? h.media.banner ?? h.media.cover),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xAA000000)]),
                        ),
                      ),
                      Positioned(left: 8, bottom: 9, child: Text('E${h.episode}', style: body(12, weight: FontWeight.w800))),
                      Positioned(left: 0, right: 0, bottom: 0, child: ProgressLine(h.duration > 0 ? h.position / h.duration : 0, height: 3)),
                    ]),
                  ),
                ),
                const SizedBox(height: 7),
                Text(h.media.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(13, weight: FontWeight.w700)),
                Text('${Fmt.clock(left)} left · ${Fmt.relativeTime(h.updatedAt)}', style: body(11.5, color: Paper.paper3)),
              ]),
            ),
          );
        },
      );
}

class GenreGrid extends StatelessWidget {
  const GenreGrid({super.key, required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGutter),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final g in kGenres)
            Chip2(g, onTap: () => go(context, SearchView(initial: BrowseFilters(type: type, genres: [g], sort: SortKey.popularityDesc)))),
        ]),
      );
}
