import 'dart:async';

import 'package:flutter/material.dart' hide Ink;

import '../models/media.dart';
import '../services/anilist.dart';
import '../services/format.dart';
import '../services/store.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_icon.dart';
import '../sources/manga/extensions.dart';
import 'browse_view.dart' show ExtCover, SourceMangaView;
import 'home_view.dart' show kGenres;
import 'manga_detail_view.dart';
import 'series_view.dart';

/// Shorthand people actually type. Port of `lib/aliases.ts`.
const Map<String, String> kAliases = {
  'jjk': 'Jujutsu Kaisen', 'aot': 'Attack on Titan', 'snk': 'Shingeki no Kyojin', 'mha': 'My Hero Academia',
  'bnha': 'Boku no Hero Academia', 'db': 'Dragon Ball', 'dbz': 'Dragon Ball Z', 'dbs': 'Dragon Ball Super',
  'ds': 'Demon Slayer', 'kny': 'Kimetsu no Yaiba', 'op': 'One Piece', 'csm': 'Chainsaw Man',
  'fma': 'Fullmetal Alchemist', 'fmab': 'Fullmetal Alchemist: Brotherhood', 'sao': 'Sword Art Online',
  'nge': 'Neon Genesis Evangelion', 'eva': 'Neon Genesis Evangelion', 'opm': 'One Punch Man', 'hxh': 'Hunter x Hunter',
  'sl': 'Solo Leveling', 'tg': 'Tokyo Ghoul', 'bc': 'Black Clover', 'dn': 'Death Note', 'cg': 'Code Geass',
  'vinland': 'Vinland Saga', 'slime': 'That Time I Got Reincarnated as a Slime', 'mob': 'Mob Psycho 100',
  'mp100': 'Mob Psycho 100', 'sxf': 'Spy x Family', 'kaiju': 'Kaiju No. 8', 'frieren': "Frieren: Beyond Journey's End",
  'dandadan': 'Dandadan', 'oshi': 'Oshi no Ko', 'bocchi': 'Bocchi the Rock!', 're0': 'Re:Zero', 'rezero': 'Re:Zero',
  're zero': 'Re:Zero', 'konosuba': 'KonoSuba', 'toradora': 'Toradora!',
};

({String query, bool expanded}) expandAlias(String q) {
  final key = q.trim().toLowerCase();
  final hit = kAliases[key];
  return hit != null ? (query: hit, expanded: true) : (query: q.trim(), expanded: false);
}

class SearchView extends StatefulWidget {
  const SearchView({super.key, this.initial});

  final BrowseFilters? initial;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  late final _ctl = TextEditingController(text: widget.initial?.search ?? '');
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;

  late MediaType _type = widget.initial?.type ?? MediaType.anime;
  late SortKey? _sort = widget.initial?.sort;
  late final Set<String> _genres = {...?widget.initial?.genres};
  late final MediaSeason? _season = widget.initial?.season;
  late final int? _year = widget.initial?.year;

  final List<Media> _items = [];
  int _page = 1;
  bool _hasNext = true;
  bool _loading = false;
  Object? _error;
  String? _expandedTo;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _more();
    });
    _reload();
    if (widget.initial == null) WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  BrowseFilters _filters(int page) {
    final e = expandAlias(_ctl.text);
    _expandedTo = e.expanded ? e.query : null;
    return BrowseFilters(
      type: _type,
      page: page,
      search: e.query.isEmpty ? null : e.query,
      sort: _sort,
      genres: _genres.isEmpty ? null : _genres.toList(),
      season: _season,
      year: _year,
    );
  }

  /// Manga searches also ask installed extensions, a shelf per source.
  final Map<InstalledSource, List<SManga>> _ext = {};
  int _extToken = 0;

  Future<void> _searchExtensions(String q) async {
    final token = ++_extToken;
    setState(() => _ext.clear());
    if (_type != MediaType.manga || q.trim().length < 2) return;
    final sources = Extensions.i.searchable.take(8).toList();
    await Future.wait(sources.map((s) async {
      try {
        final hits = await Extensions.i.search(s, q.trim(), 1).timeout(const Duration(seconds: 15));
        if (token != _extToken || !mounted || hits.isEmpty) return;
        setState(() => _ext[s] = hits.take(12).toList());
      } catch (_) {}
    }));
  }

  Future<void> _reload() async {
    unawaited(_searchExtensions(_ctl.text));
    final token = ++_token;
    setState(() {
      _items.clear();
      _page = 1;
      _hasNext = true;
      _error = null;
      _loading = true;
    });
    try {
      final res = await AniList.i.browse(_filters(1));
      if (token != _token || !mounted) return;
      setState(() {
        _items.addAll(res.items);
        _hasNext = res.hasNextPage;
        _loading = false;
      });
    } catch (e) {
      if (token != _token || !mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _more() async {
    if (_loading || !_hasNext || _error != null) return;
    final token = _token;
    setState(() => _loading = true);
    try {
      final res = await AniList.i.browse(_filters(_page + 1));
      if (token != _token || !mounted) return;
      setState(() {
        _page++;
        _items.addAll(res.items.where((m) => !_items.any((x) => x.id == m.id)));
        _hasNext = res.hasNextPage;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onType(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), _reload);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final lang = Store.i.settings.titleLanguage;
    return Scaffold(
      backgroundColor: Ink.ink0,
      body: CustomScrollView(
        controller: _scroll,
        physics: const BouncingScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, top + 8, kGutter, 6),
              child: Row(children: [
                RoundIcon('arrowLeft', filled: false, onTap: () => Navigator.pop(context)),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Ink.ink2,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: _focus.hasFocus ? accentOf(context) : Lines.line2),
                    ),
                    child: Row(children: [
                      const PzIcon('search', size: 18, color: Paper.paper2),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _ctl,
                          focusNode: _focus,
                          onChanged: _onType,
                          onSubmitted: (_) => _reload(),
                          textInputAction: TextInputAction.search,
                          style: body(15.5),
                          cursorColor: accentOf(context),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: _type == MediaType.anime ? 'Search anime' : 'Search manga, manhwa, manhua',
                            hintStyle: body(15, color: Paper.paper4),
                          ),
                        ),
                      ),
                      if (_ctl.text.isNotEmpty)
                        Pressable(
                          onTap: () {
                            _ctl.clear();
                            _reload();
                          },
                          child: const PzIcon('close', size: 16, color: Paper.paper3),
                        ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 4),
              child: Row(children: [
                Segmented<MediaType>(
                  value: _type,
                  options: const [(MediaType.anime, 'Anime'), (MediaType.manga, 'Manga')],
                  onChanged: (t) {
                    setState(() => _type = t);
                    _reload();
                  },
                ),
                const Spacer(),
                Pressable(
                  onTap: () => pzSheet<void>(context, title: 'Sort by', builder: (c) => ListView(shrinkWrap: true, children: [
                        for (final (k, label) in const [
                          (null, 'Best match / trending'),
                          (SortKey.popularityDesc, 'Most popular'),
                          (SortKey.scoreDesc, 'Highest rated'),
                          (SortKey.trendingDesc, 'Trending now'),
                          (SortKey.startDateDesc, 'Newest'),
                        ])
                          SheetOption(label, selected: _sort == k, onTap: () {
                            Navigator.pop(c);
                            setState(() => _sort = k);
                            _reload();
                          }),
                      ])),
                  child: Row(children: [
                    const PzIcon('sort', size: 18, color: Paper.paper2),
                    const SizedBox(width: 6),
                    Text(switch (_sort) {
                      SortKey.popularityDesc => 'Popular',
                      SortKey.scoreDesc => 'Top rated',
                      SortKey.trendingDesc => 'Trending',
                      SortKey.startDateDesc => 'Newest',
                      _ => 'Sort',
                    }, style: body(13.5, color: Paper.paper2, weight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 8),
                children: [
                  for (final g in kGenres)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip2(g, on: _genres.contains(g), onTap: () {
                        setState(() => _genres.contains(g) ? _genres.remove(g) : _genres.add(g));
                        _reload();
                      }),
                    ),
                ],
              ),
            ),
          ),
          if (_expandedTo != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 0),
                child: Text('Showing results for “$_expandedTo”', style: body(12.5, color: Paper.paper3)),
              ),
            ),
          if (_season != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 0),
                child: Text('${Fmt.seasonName(_season)} ${_year ?? ''}', style: body(12.5, color: Paper.paper3)),
              ),
            ),
          if (_error != null && _items.isEmpty)
            SliverToBoxAdapter(
              child: StatePanel(title: 'Search failed', message: '$_error', icon: 'offline', action: 'Try again', onAction: _reload),
            )
          else if (!_loading && _items.isEmpty && _ext.isEmpty)
            SliverToBoxAdapter(
              child: StatePanel(
                title: 'Nothing found',
                message: _ctl.text.isEmpty ? 'Try another filter.' : 'No ${_type == MediaType.anime ? 'anime' : 'manga'} matches “${_ctl.text.trim()}”.',
                icon: 'search',
              ),
            )
          else ...[
            for (final e in _ext.entries)
              SliverToBoxAdapter(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SectionHeader(e.key.name, subtitle: 'From your extensions'),
                  SizedBox(
                    height: 214,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: kGutter),
                      itemCount: e.value.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (c, i) {
                        final m = e.value[i];
                        return Pressable(
                          onTap: () => go(context, SourceMangaView(source: e.key, manga: m)),
                          child: SizedBox(
                            width: 112,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              AspectRatio(
                                aspectRatio: 2 / 3,
                                child: m.thumbnail == null ? Container(color: Ink.ink2) : ExtCover(source: e.key, url: m.thumbnail!),
                              ),
                              const SizedBox(height: 6),
                              Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(12, weight: FontWeight.w700, height: 1.2)),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ]),
              ),
            if (_ext.isNotEmpty && _items.isNotEmpty) const SliverToBoxAdapter(child: SectionHeader('From AniList')),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 140,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.49,
                ),
                itemCount: _items.isEmpty && _loading ? 9 : _items.length,
                itemBuilder: (c, i) {
                  if (_items.isEmpty) {
                    return const Column(children: [AspectRatio(aspectRatio: 2 / 3, child: Skeleton()), SizedBox(height: 8), Skeleton(height: 12)]);
                  }
                  final m = _items[i];
                  return FadeIn(
                    delay: Duration(milliseconds: 25 * (i % 9)),
                    child: PosterCard(
                      media: m,
                      title: Fmt.titleOf(m, lang: lang),
                      onTap: () => go(context, Fmt.isManga(m) || _type == MediaType.manga ? MangaDetailView(mediaId: m.id) : SeriesView(mediaId: m.id)),
                    ),
                  );
                },
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: _loading && _items.isNotEmpty
                    ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: accentOf(context)))
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
