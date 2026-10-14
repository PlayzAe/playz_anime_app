import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Ink;

import '../services/store.dart';
import '../sources/manga/extensions.dart';
import '../sources/manga/providers.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_icon.dart';
import '../widgets/pz_image.dart';
import 'reader_view.dart';

/// A cover served by an extension: fetched natively with the source's headers,
/// falling back to a plain request with its referer.
class ExtCover extends StatefulWidget {
  const ExtCover({super.key, required this.source, required this.url, this.radius = 7});

  final InstalledSource source;
  final String url;
  final double radius;

  @override
  State<ExtCover> createState() => _ExtCoverState();
}

class _ExtCoverState extends State<ExtCover> {
  static final Map<String, String> _paths = {};
  String? _path;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ExtCover old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  Future<void> _load() async {
    final key = '${widget.source.id}|${widget.url}';
    _path = _paths[key];
    _failed = false;
    if (_path != null) return;
    try {
      final p = await Extensions.i.cover(widget.source.id, widget.url);
      _paths[key] = p;
      if (mounted) setState(() => _path = p);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(widget.radius);
    if (_failed) return PzImage(url: widget.url, referer: '${widget.source.baseUrl}/', radius: r);
    if (_path == null) return ClipRRect(borderRadius: r, child: const Skeleton());
    return ClipRRect(
      borderRadius: r,
      child: Image.file(File(_path!), fit: BoxFit.cover, cacheWidth: 360, gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Container(color: Ink.ink2)),
    );
  }
}

class _ExtIcon extends StatelessWidget {
  const _ExtIcon({required this.url, required this.letter, this.size = 40});

  final String? url;
  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: url == null
            ? Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Ink.ink3, borderRadius: BorderRadius.circular(9)),
                child: Text(letter.isEmpty ? '?' : letter[0], style: display(size * 0.55)),
              )
            : PzImage(url: url!, radius: BorderRadius.circular(9), fit: BoxFit.cover),
      );
}

class _Tag18 extends StatelessWidget {
  const _Tag18();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: const Color(0x33E5484D), borderRadius: BorderRadius.circular(4)),
        child: Text('18+', style: body(10, weight: FontWeight.w800, color: const Color(0xFFFF8A8F))),
      );
}

/// Installed extension sources, shown under the built-ins in Browse → Sources.
/// English and multi-language sources first; other languages fold away.
class InstalledSourcesList extends StatefulWidget {
  const InstalledSourcesList({super.key});

  @override
  State<InstalledSourcesList> createState() => _InstalledSourcesListState();
}

class _InstalledSourcesListState extends State<InstalledSourcesList> {
  bool _allLangs = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Extensions.i,
        builder: (context, _) {
          final all = Extensions.i.installed;
          final mine = Extensions.i.searchable;
          final others = all.length - mine.length;
          final list = _allLangs ? all : mine;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 18, kGutter, 8),
              child: Row(children: [
                Expanded(child: Text('From extensions · ${mine.length}', style: body(14, weight: FontWeight.w700))),
                PzBtn('Manage', compact: true, icon: 'plus', onTap: () => go(context, const ExtensionsPage())),
              ]),
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
                child: Text('Nothing installed yet. Extensions add hundreds of manga, manhwa and manhua sites.', style: body(12.5, color: Paper.paper3)),
              ),
            for (final s in list)
              Pressable(
                scale: 0.98,
                onTap: () => go(context, SourceBrowseView(source: s)),
                onLongPress: () => _sourceSheet(context, s),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Ink.ink1, borderRadius: BorderRadius.circular(10), border: Border.all(color: Lines.line)),
                  child: Row(children: [
                    _ExtIcon(url: s.icon, letter: s.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(14.5, weight: FontWeight.w700))),
                          if (s.nsfw) const _Tag18(),
                        ]),
                        Text(s.lang.toUpperCase(), style: body(11.5, color: Paper.paper3)),
                      ]),
                    ),
                    PzToggle(value: Store.i.isSourceEnabled(s.provider), onChanged: (v) => Store.i.setSourceEnabled(s.provider, v)),
                    const SizedBox(width: 6),
                    const PzIcon('chevronRight', size: 16, color: Paper.paper3),
                  ]),
                ),
              ),
            if (others > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
                child: PzBtn(_allLangs ? 'Only English' : 'Show $others in other languages',
                    compact: true, icon: 'globe', onTap: () => setState(() => _allLangs = !_allLangs)),
              ),
          ]);
        },
      );

  static void _sourceSheet(BuildContext context, InstalledSource s) => pzSheet<void>(context,
      title: s.name,
      builder: (c) => ListView(shrinkWrap: true, children: [
            SheetOption('Browse', selected: false, onTap: () {
              Navigator.pop(c);
              go(context, SourceBrowseView(source: s));
            }),
            SheetOption('Uninstall extension', selected: false, onTap: () {
              Navigator.pop(c);
              Extensions.i.uninstall(s.pkg);
            }),
          ]));
}

/// Settings → Manga → Extensions, and the "Install an extension" prompts.
class ExtensionsPage extends StatelessWidget {
  const ExtensionsPage({super.key, this.query});

  final String? query;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Ink.ink0,
      body: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(8, top + 8, kGutter, 4),
          child: Row(children: [
            RoundIcon('arrowLeft', filled: false, onTap: () => Navigator.pop(context)),
            const SizedBox(width: 6),
            Expanded(child: Text('Extensions', style: display(28))),
          ]),
        ),
        Expanded(child: ExtensionsPane(query: query)),
      ]),
    );
  }
}

/// Mihon's Browse → Extensions: every extension in the repos, one-tap install,
/// updates, and bulk install.
class ExtensionsPane extends StatefulWidget {
  const ExtensionsPane({super.key, this.query});

  final String? query;

  @override
  State<ExtensionsPane> createState() => _ExtensionsPaneState();
}

class _ExtensionsPaneState extends State<ExtensionsPane> {
  late String _q = widget.query ?? '';
  late final _ctl = TextEditingController(text: widget.query);
  String _lang = 'en';
  Object? _error;
  String? _bulk;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _error = null);
    try {
      await Future.wait([Extensions.i.load(force: force), Extensions.i.refresh()]);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _install(Extension e) async {
    final err = await Extensions.i.install(e);
    if (!mounted) return;
    toast(context, err == null ? 'Installed ${e.name}' : '${e.name}: $err');
  }

  Future<void> _many(List<Extension> list, String verb) async {
    if (list.isEmpty || _bulk != null) return;
    setState(() => _bulk = '$verb 0/${list.length}');
    final ok = await Extensions.i.installMany(list, onProgress: (d, t) {
      if (mounted) setState(() => _bulk = '$verb $d/$t');
    });
    if (!mounted) return;
    setState(() => _bulk = null);
    toast(context, ok == list.length ? '$verb ${list.length} extensions' : '$ok of ${list.length} done. Tap a failed one to see why.');
  }

  Future<void> _installAllShown(List<Extension> shown) async {
    final todo = shown.where((e) => !Extensions.i.isInstalled(e.pkg)).toList();
    if (todo.isEmpty) return;
    final ok = await pzSheet<bool>(context,
        title: 'Install ${todo.length} extensions?',
        builder: (c) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Every extension in this list gets installed. They only load when you use them, so the app stays fast. '
                    'Downloads are about 30–80 KB each.', style: body(13.5, color: Paper.paper2, height: 1.45)),
                const SizedBox(height: 14),
                PzBtn('Install all', icon: 'downloads', primary: true, onTap: () => Navigator.pop(c, true)),
              ]),
            ));
    if (ok == true) await _many(todo, 'Installed');
  }

  void _repos() {
    final ctl = TextEditingController();
    pzSheet<void>(context,
        title: 'Extension repos',
        builder: (c) => StatefulBuilder(
              builder: (c, set) => ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
                for (final r in Extensions.i.repos)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(child: Text(r, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(12.5, color: Paper.paper2))),
                      if (r != kDefaultRepo)
                        RoundIcon('trash', size: 34, iconSize: 15, filled: false, onTap: () {
                          Extensions.i.removeRepo(r);
                          set(() {});
                          _load(force: true);
                        }),
                    ]),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctl,
                  style: body(14),
                  decoration: InputDecoration(
                    hintText: 'https://…/index.json',
                    hintStyle: body(14, color: Paper.paper4),
                    filled: true,
                    fillColor: Ink.ink2,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                PzBtn('Add repo', icon: 'plus', primary: true, onTap: () {
                  Extensions.i.addRepo(ctl.text);
                  Navigator.pop(c);
                  _load(force: true);
                }),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text('Update extensions automatically', style: body(14))),
                  PzToggle(value: Extensions.i.autoUpdate, onChanged: (v) {
                    Extensions.i.setAutoUpdate(v);
                    set(() {});
                  }),
                ]),
                const SizedBox(height: 16),
              ]),
            ));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Extensions.i,
        builder: (context, _) {
          final all = Extensions.i.catalogue;
          final hideAdult = Store.i.settings.hideAdult;
          final shown = (all ?? const <Extension>[]).where((e) {
            if (hideAdult && e.nsfw) return false;
            if (_lang != 'any' && e.lang != _lang && e.lang != 'all') return false;
            return _q.isEmpty || e.name.toLowerCase().contains(_q.toLowerCase());
          }).toList();
          final installed = shown.where((e) => Extensions.i.isInstalled(e.pkg)).toList();
          final available = shown.where((e) => !Extensions.i.isInstalled(e.pkg)).toList();
          final updates = Extensions.i.updates;
          final recommended = (all ?? const <Extension>[])
              .where((e) => kRecommended.contains(e.pkg) && !Extensions.i.isInstalled(e.pkg) && !(hideAdult && e.nsfw))
              .toList();

          return CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 6),
                child: Row(children: [
                  Expanded(
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: Ink.ink2, borderRadius: BorderRadius.circular(8), border: Border.all(color: Lines.line2)),
                      child: Row(children: [
                        const PzIcon('search', size: 16, color: Paper.paper3),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _ctl,
                            onChanged: (v) => setState(() => _q = v),
                            style: body(14),
                            decoration: InputDecoration(
                                isCollapsed: true, border: InputBorder.none, hintText: 'Search ${all?.length ?? ''} extensions', hintStyle: body(14, color: Paper.paper4)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RoundIcon('globe', onTap: _repos),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 6), children: [
                  for (final (code, label) in const [
                    ('en', 'English'),
                    ('any', 'All languages'),
                    ('ja', 'Japanese'),
                    ('ko', 'Korean'),
                    ('zh', 'Chinese'),
                    ('es', 'Spanish'),
                    ('fr', 'French'),
                    ('id', 'Indonesian'),
                    ('pt-BR', 'Portuguese'),
                  ])
                    Padding(padding: const EdgeInsets.only(right: 8), child: Chip2(label, on: _lang == code, onTap: () => setState(() => _lang = code))),
                ]),
              ),
            ),
            if (_bulk != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 8),
                  child: Row(children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Text(_bulk!, style: body(13, color: Paper.paper2)),
                  ]),
                ),
              ),
            if (updates.isNotEmpty)
              SliverToBoxAdapter(
                child: _Banner(
                  title: '${updates.length} update${updates.length == 1 ? '' : 's'} ready',
                  text: 'Sites change often; updated extensions keep chapters loading.',
                  action: 'Update all',
                  onTap: _bulk == null ? () => _many(updates, 'Updated') : null,
                ),
              ),
            if (recommended.isNotEmpty && _q.isEmpty)
              SliverToBoxAdapter(
                child: _Banner(
                  title: 'Recommended',
                  text: recommended.map((e) => e.name).take(6).join(' · '),
                  action: 'Install ${recommended.length}',
                  onTap: _bulk == null ? () => _many(recommended, 'Installed') : null,
                ),
              ),
            if (_error != null && all == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: StatePanel(title: 'Couldn’t read the repo', message: '$_error', icon: 'offline', action: 'Try again', onAction: () => _load(force: true)),
              )
            else if (all == null)
              SliverList.builder(
                  itemCount: 8,
                  itemBuilder: (_, __) => const Padding(padding: EdgeInsets.fromLTRB(kGutter, 0, kGutter, 10), child: Skeleton(height: 56)))
            else ...[
              if (installed.isNotEmpty) SliverToBoxAdapter(child: SectionHeader('Installed · ${installed.length}')),
              SliverList.builder(itemCount: installed.length, itemBuilder: (c, i) => _row(installed[i])),
              SliverToBoxAdapter(
                child: SectionHeader(
                  'Available · ${available.length}',
                  action: available.length > 1 && _bulk == null ? 'Install all' : null,
                  onAction: () => _installAllShown(shown),
                ),
              ),
              SliverList.builder(itemCount: available.length, itemBuilder: (c, i) => _row(available[i])),
            ],
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.bottom + 32)),
          ]);
        },
      );

  Widget _row(Extension e) {
    final have = Extensions.i.package(e.pkg);
    final busy = Extensions.i.busy[e.pkg];
    final error = Extensions.i.errors[e.pkg];
    final update = Extensions.i.hasUpdate(e.pkg);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kGutter, vertical: 6),
      child: Row(children: [
        _ExtIcon(url: e.icon, letter: e.name),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(14.5, weight: FontWeight.w700))),
              if (e.nsfw) const _Tag18(),
            ]),
            Text(
              error != null
                  ? 'Failed: $error'
                  : '${e.lang.toUpperCase()} · v${have?.version ?? e.version}${update ? ' → v${e.version}' : ''}${e.sources.length > 1 ? ' · ${e.sources.length} sources' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: body(11.5, color: error != null ? const Color(0xFFFF8A8F) : Paper.paper3),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        if (have != null && !update)
          PzBtn('Remove', compact: true, busy: busy != null, onTap: () => Extensions.i.uninstall(e.pkg))
        else
          PzBtn(
            update ? 'Update' : (error != null ? 'Retry' : 'Install'),
            compact: true,
            primary: true,
            busy: busy != null,
            onTap: () => _install(e),
          ),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.title, required this.text, required this.action, required this.onTap});

  final String title;
  final String text;
  final String action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: accentOf(context).withAlpha(0x1F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accentOf(context).withAlpha(0x55)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: body(14, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(12, color: Paper.paper2)),
            ]),
          ),
          const SizedBox(width: 8),
          PzBtn(action, compact: true, primary: true, onTap: onTap),
        ]),
      );
}

/// One-time prompt (first Manga visit): load the repo and offer the recommended set.
Future<void> maybeOfferExtensions(BuildContext context) async {
  if (Extensions.i.setupDone) return;
  Extensions.i.markSetupDone();
  try {
    await Extensions.i.load();
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  final picks = (Extensions.i.catalogue ?? const <Extension>[])
      .where((e) => kRecommended.contains(e.pkg) && !Extensions.i.isInstalled(e.pkg))
      .toList();
  if (picks.isEmpty) return;
  final chosen = {for (final e in picks) e.pkg};
  final go = await pzSheet<bool>(context,
      title: 'Add manga sources',
      builder: (c) => StatefulBuilder(
            builder: (c, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text('PlayzAnime reads from Mihon extensions. These cover most manga, manhwa and manhua. '
                    'You can add or remove any later in Settings → Manga → Extensions.', style: body(13, color: Paper.paper2, height: 1.45)),
              ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final e in picks)
                    InkWell(
                      onTap: () => set(() => chosen.contains(e.pkg) ? chosen.remove(e.pkg) : chosen.add(e.pkg)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(children: [
                          _ExtIcon(url: e.icon, letter: e.name, size: 34),
                          const SizedBox(width: 12),
                          Expanded(child: Text(e.name, style: body(14.5, weight: FontWeight.w600))),
                          PzToggle(value: chosen.contains(e.pkg), onChanged: (v) => set(() => v ? chosen.add(e.pkg) : chosen.remove(e.pkg))),
                        ]),
                      ),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: PzBtn('Install ${chosen.length}', icon: 'downloads', primary: true, onTap: () => Navigator.pop(c, true)),
              ),
            ]),
          ));
  if (go != true) return;
  final list = picks.where((e) => chosen.contains(e.pkg)).toList();
  if (context.mounted) toast(context, 'Installing ${list.length} extensions…');
  final ok = await Extensions.i.installMany(list);
  if (context.mounted) toast(context, 'Installed $ok extensions');
}

/// One extension source: popular, latest, search. Mihon's source screen.
class SourceBrowseView extends StatefulWidget {
  const SourceBrowseView({super.key, required this.source});

  final InstalledSource source;

  @override
  State<SourceBrowseView> createState() => _SourceBrowseViewState();
}

class _SourceBrowseViewState extends State<SourceBrowseView> {
  int _mode = 0; // 0 popular, 1 latest, 2 search
  String _q = '';
  final List<SManga> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _end = false;
  Object? _error;
  int _token = 0;
  Timer? _debounce;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 500) _more();
    });
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<List<SManga>> _fetch(int page) => switch (_mode) {
        1 => Extensions.i.latest(widget.source, page),
        2 => Extensions.i.search(widget.source, _q, page),
        _ => Extensions.i.popular(widget.source, page),
      };

  Future<void> _reload() async {
    final t = ++_token;
    setState(() {
      _items.clear();
      _page = 1;
      _end = false;
      _error = null;
      _loading = true;
    });
    try {
      final r = await _fetch(1);
      if (t != _token || !mounted) return;
      setState(() {
        _items.addAll(r);
        _end = r.isEmpty;
        _loading = false;
      });
    } catch (e) {
      if (t == _token && mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _more() async {
    if (_loading || _end || _error != null) return;
    final t = _token;
    setState(() => _loading = true);
    try {
      final r = await _fetch(_page + 1);
      if (t != _token || !mounted) return;
      setState(() {
        _page++;
        final fresh = r.where((m) => !_items.any((x) => x.url == m.url)).toList();
        _items.addAll(fresh);
        _end = fresh.isEmpty;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: Ink.ink0,
      body: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(8, top + 8, kGutter, 6),
          child: Row(children: [
            RoundIcon('arrowLeft', filled: false, onTap: () => Navigator.pop(context)),
            const SizedBox(width: 6),
            Expanded(child: Text(widget.source.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(26))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
          child: Row(children: [
            Segmented<int>(
              value: _mode == 2 ? 0 : _mode,
              options: [(0, 'Popular'), if (widget.source.supportsLatest) (1, 'Latest')],
              onChanged: (v) {
                setState(() => _mode = v);
                _reload();
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                    color: Ink.ink2, borderRadius: BorderRadius.circular(8), border: Border.all(color: _mode == 2 ? accentOf(context) : Lines.line2)),
                child: TextField(
                  onChanged: (v) {
                    _q = v.trim();
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 450), () {
                      setState(() => _mode = _q.isEmpty ? 0 : 2);
                      _reload();
                    });
                  },
                  style: body(14),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: 'Search', hintStyle: body(14, color: Paper.paper4)),
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _error != null && _items.isEmpty
              ? StatePanel(title: 'This source didn’t answer', message: '$_error', icon: 'offline', action: 'Try again', onAction: _reload)
              : !_loading && _items.isEmpty
                  ? const StatePanel(title: 'Nothing here', icon: 'search')
                  : GridView.builder(
                      controller: _scroll,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 32),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: width > 700 ? 160 : 130, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 0.52),
                      itemCount: _items.isEmpty ? 9 : _items.length,
                      itemBuilder: (c, i) {
                        if (_items.isEmpty) {
                          return const Column(children: [AspectRatio(aspectRatio: 2 / 3, child: Skeleton()), SizedBox(height: 8), Skeleton(height: 12)]);
                        }
                        final m = _items[i];
                        return Pressable(
                          onTap: () => go(context, SourceMangaView(source: widget.source, manga: m)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            AspectRatio(
                              aspectRatio: 2 / 3,
                              child: m.thumbnail == null
                                  ? Container(decoration: BoxDecoration(color: Ink.ink2, borderRadius: BorderRadius.circular(7)))
                                  : ExtCover(source: widget.source, url: m.thumbnail!),
                            ),
                            const SizedBox(height: 6),
                            Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(12.5, weight: FontWeight.w700, height: 1.2)),
                          ]),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

/// A title on an extension source: description and chapters.
class SourceMangaView extends StatefulWidget {
  const SourceMangaView({super.key, required this.source, required this.manga});

  final InstalledSource source;
  final SManga manga;

  @override
  State<SourceMangaView> createState() => _SourceMangaViewState();
}

class _SourceMangaViewState extends State<SourceMangaView> {
  SManga? _details;
  List<MChapter>? _chapters;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Extensions.i.update(widget.source, widget.manga);
      if (!mounted) return;
      setState(() {
        _details = r.manga;
        _chapters = r.chapters;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _details ?? widget.manga;
    final chapters = _chapters;
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Ink.ink0,
      body: CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, top + 8, kGutter, 0),
            child: Align(alignment: Alignment.centerLeft, child: RoundIcon('arrowLeft', onTap: () => Navigator.pop(context))),
          ),
        ),
        SliverToBoxAdapter(
          child: FadeIn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(
                  width: 104,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: m.thumbnail == null ? Container(color: Ink.ink2) : ExtCover(source: widget.source, url: m.thumbnail!, radius: 8),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.source.name.toUpperCase(), style: body(11, color: accentOf(context), weight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(m.title, maxLines: 4, overflow: TextOverflow.ellipsis, style: display(28)),
                    if ((m.author ?? '').isNotEmpty) Text(m.author!, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(12.5, color: Paper.paper3)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        if ((m.genre ?? '').isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final g in m.genre!.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty).take(8)) Tag(g),
              ]),
            ),
          ),
        if ((m.description ?? '').isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 14, kGutter, 0),
              child: Text(m.description!, maxLines: 6, overflow: TextOverflow.ellipsis, style: body(13.5, color: Paper.paper2, height: 1.5)),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 0),
            child: PzBtn('Start reading',
                icon: 'manga',
                primary: true,
                onTap: chapters == null || chapters.isEmpty ? null : () => go(context, ReaderView(mediaId: 0, chapters: chapters, index: 0))),
          ),
        ),
        SliverToBoxAdapter(child: SectionHeader('Chapters', subtitle: chapters == null ? 'Loading…' : '${chapters.length} chapters')),
        if (_error != null)
          SliverToBoxAdapter(child: StatePanel(title: 'Couldn’t list chapters', message: '$_error', icon: 'alert', action: 'Try again', onAction: _load))
        else if (chapters == null)
          SliverList.builder(
              itemCount: 5, itemBuilder: (_, __) => const Padding(padding: EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8), child: Skeleton(height: 50)))
        else
          SliverList.builder(
            itemCount: chapters.length,
            itemBuilder: (c, i) {
              final idx = chapters.length - 1 - i;
              final ch = chapters[idx];
              return Pressable(
                scale: 0.985,
                onTap: () => go(context, ReaderView(mediaId: 0, chapters: chapters, index: idx)),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(color: Ink.ink1, borderRadius: BorderRadius.circular(8), border: Border.all(color: Lines.line)),
                  child: Text(ch.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(14, weight: FontWeight.w600)),
                ),
              );
            },
          ),
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.bottom + 32)),
      ]),
    );
  }
}
