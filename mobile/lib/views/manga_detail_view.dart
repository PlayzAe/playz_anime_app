import 'package:flutter/material.dart' hide Ink;

import '../models/media.dart';
import '../services/anilist.dart';
import '../services/downloader.dart';
import '../services/format.dart';
import '../services/store.dart';
import '../sources/manga/extensions.dart';
import '../sources/manga/providers.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_icon.dart';
import '../widgets/pz_image.dart';
import 'browse_view.dart' show ExtensionsPage;
import 'download_sheet.dart';
import 'reader_view.dart';
import 'series_view.dart';

/// Manga detail. Port of `MangaDetail.tsx`: AniList metadata on top, the
/// auto-picked source's chapters below, a switch to any other source.
class MangaDetailView extends StatefulWidget {
  const MangaDetailView({super.key, required this.mediaId});

  final int mediaId;

  @override
  State<MangaDetailView> createState() => _MangaDetailViewState();
}

class _MangaDetailViewState extends State<MangaDetailView> {
  MediaDetail? _m;
  ChapterList? _list;
  Object? _error;
  Object? _chError;
  bool _loadingChapters = false;
  bool _newestFirst = true;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    Store.i.addListener(_onStore);
    Extensions.i.addListener(_onStore);
    // A title read on an extension needs the repo index to offer a reinstall.
    if (Store.i.readingEntry(widget.mediaId)?.chapterId.startsWith('x') ?? false) Extensions.i.load().catchError((_) => <Extension>[]);
    _load();
  }

  @override
  void dispose() {
    Store.i.removeListener(_onStore);
    Extensions.i.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _error = null);
    try {
      final m = await AniList.i.media(widget.mediaId, force: force);
      if (!mounted) return;
      setState(() => _m = m);
      await _chapters(force: force);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _chapters({bool force = false, String? provider, bool all = false}) async {
    setState(() {
      _loadingChapters = true;
      _chError = null;
    });
    try {
      final list = await MangaProviders.i.chapterList(widget.mediaId, provider: provider ?? Store.i.pinnedSource(widget.mediaId), force: force, all: all);
      if (mounted) setState(() => _list = list);
    } catch (e) {
      if (mounted) setState(() => _chError = e);
    } finally {
      if (mounted) setState(() => _loadingChapters = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Ink.ink0,
        body: SafeArea(
          child: Column(children: [
            Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.all(8), child: RoundIcon('arrowLeft', onTap: () => Navigator.pop(context)))),
            Expanded(child: Center(child: StatePanel(title: 'Couldn’t load this title', message: '$_error', icon: 'alert', action: 'Try again', onAction: _load))),
          ]),
        ),
      );
    }
    final m = _m;
    return Scaffold(
      backgroundColor: Ink.ink0,
      body: m == null
          ? const SafeArea(child: Padding(padding: EdgeInsets.all(kGutter), child: Column(children: [Skeleton(height: 240, radius: 12), SizedBox(height: 14), Skeleton(height: 30)])))
          : _content(m),
    );
  }

  /// Chapters are oldest first, so "next 10" starts at the resume point or the first unread one.
  void _bulkDownload(MediaDetail m, List<MChapter> readable, Set<String> read) {
    final snap = Fmt.snapshotOfDetail(m, lang: Store.i.settings.titleLanguage);
    final unread = readable.where((c) => !read.contains(c.id)).toList();
    final resumeId = Store.i.readingEntry(m.id)?.chapterId;
    var from = readable.indexWhere((c) => c.id == resumeId);
    if (from < 0) from = readable.indexWhere((c) => !read.contains(c.id));
    final next10 = readable.skip(from < 0 ? 0 : from).take(10).toList();
    void pick(List<MChapter> list) {
      Navigator.pop(context);
      downloadChapters(context, snap, list);
    }

    pzSheet<void>(context, title: 'Download chapters', builder: (c) => ListView(shrinkWrap: true, children: [
          SheetOption('Next ${next10.length}', sub: 'From ${next10.first.label}', selected: false, onTap: () => pick(next10)),
          if (unread.isNotEmpty && unread.length != readable.length)
            SheetOption('Unread (${unread.length})', selected: false, onTap: () => pick(unread)),
          SheetOption('All ${readable.length}', selected: false, onTap: () => pick(readable)),
        ]));
  }

  Widget _content(MediaDetail m) {
    final lang = Store.i.settings.titleLanguage;
    final top = MediaQuery.of(context).padding.top;
    final read = Store.i.readChapters(m.id).toSet();
    final resume = Store.i.readingEntry(m.id);
    final chapters = _list?.chapters ?? const <MChapter>[];
    final ordered = _newestFirst ? chapters.reversed.toList() : chapters;
    final status = Store.i.libraryEntry(m.id)?.status;
    final readable = chapters.where((c) => c.externalUrl == null).toList();
    var resumeIndex = resume == null ? -1 : readable.indexWhere((c) => c.id == resume.chapterId);
    // Read on another source: carry on from the same chapter number here.
    final crossSource = resume != null && resumeIndex < 0 && resume.chapterNumber != null;
    if (crossSource) resumeIndex = readable.indexWhere((c) => c.number == resume.chapterNumber);
    final resumeNum = double.tryParse(resume?.chapterNumber ?? '');
    bool isReadCh(MChapter c) => read.contains(c.id) || (crossSource && resumeNum != null && c.sortKey >= 0 && c.sortKey < resumeNum);
    final firstUnread = readable.indexWhere((c) => !isReadCh(c));
    final missing = _missingSource(resume?.chapterId);
    final providerLabel = _list?.provider == null ? null : providerName(_list!.provider!);

    return RefreshIndicator(
      color: accentOf(context),
      onRefresh: () => _load(force: true),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 280 + top,
              child: Stack(fit: StackFit.expand, children: [
                PzImage(url: m.bannerImage ?? Fmt.coverOf(m)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x990C0B0A), Color(0x660C0B0A), Ink.ink0]),
                  ),
                ),
                Positioned(top: top + 6, left: 8, child: RoundIcon('arrowLeft', onTap: () => Navigator.pop(context))),
                Positioned(
                  left: kGutter,
                  right: kGutter,
                  bottom: 0,
                  child: FadeIn(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      SizedBox(width: 104, child: AspectRatio(aspectRatio: 2 / 3, child: PzImage(url: Fmt.coverOf(m), radius: BorderRadius.circular(8)))),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text([Fmt.mangaKind(m), Fmt.statusLabel(m.status)].whereType<String>().join(' · ').toUpperCase(),
                              style: body(11, color: accentOf(context), weight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(Fmt.titleOf(m, lang: lang), maxLines: 3, overflow: TextOverflow.ellipsis, style: display(30)),
                          if (m.staff?.isNotEmpty ?? false)
                            Text(m.staff!.first.name, maxLines: 1, style: body(12.5, color: Paper.paper3)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: PzBtn(
                      resumeIndex >= 0
                          ? 'Resume Ch ${resume!.chapterNumber ?? ''}'
                          : (firstUnread > 0 ? 'Continue Ch ${readable[firstUnread].number ?? ''}' : 'Start reading'),
                      icon: 'manga',
                      primary: true,
                      busy: _loadingChapters && _list == null,
                      onTap: readable.isEmpty
                          ? null
                          : () => go(context, ReaderView(
                                mediaId: m.id,
                                chapters: readable,
                                index: resumeIndex >= 0 ? resumeIndex : (firstUnread >= 0 ? firstUnread : 0),
                                startPage: resumeIndex >= 0 && !crossSource ? resume!.page : 0,
                              )),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PzBtn(status?.label ?? 'Add to list', icon: status == null ? 'plus' : 'bookmarkFilled',
                      onTap: () => pickListStatus(context, Fmt.snapshotOfDetail(m, lang: lang), status)),
                ]),
                if (m.genres?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 14),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final g in m.genres!) Tag(g)]),
                ],
                if ((m.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Pressable(
                    scale: 0.99,
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: AnimatedSize(
                      duration: kMed,
                      alignment: Alignment.topCenter,
                      child: Text(Fmt.plainText(m.description),
                          maxLines: _expanded ? null : 4, overflow: _expanded ? null : TextOverflow.ellipsis, style: body(13.5, color: Paper.paper2, height: 1.5)),
                    ),
                  ),
                ],
              ]),
            ),
          ),
          if (missing != null)
            SliverToBoxAdapter(
              child: _Notice(
                title: 'You were reading this on ${missing.name}',
                text: '${missing.name} isn’t installed any more. Reinstall it, or carry on from Ch ${resume?.chapterNumber ?? '?'} on ${providerLabel ?? 'another source'}.',
                action: 'Reinstall',
                onAction: () => _reinstall(missing),
              ),
            ),
          if (_list != null && !_loadingChapters && _thin(m, readable))
            SliverToBoxAdapter(
              child: _Notice(
                title: readable.isEmpty ? 'No chapters found' : 'Missing chapters?',
                text: readable.isEmpty
                    ? 'None of your sources has this title. An extension probably does.'
                    : 'Your sources stop at ${readable.isEmpty ? 0 : readable.last.number}${m.chapters != null ? ' of ${m.chapters}' : ''}. Another extension may be further along.',
                action: 'Install an extension',
                onAction: () async {
                  await go(context, ExtensionsPage(query: null));
                  _chapters(force: true);
                },
              ),
            ),
          SliverToBoxAdapter(
            child: SectionHeader(
              'Chapters',
              subtitle: _loadingChapters
                  ? 'Asking every source…'
                  : _list == null
                      ? null
                      : '${chapters.length} from ${providerLabel ?? 'no source'}',
              action: 'Source',
              onAction: _list == null ? null : _pickSource,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
              child: Row(children: [
                Pressable(
                  onTap: () => setState(() => _newestFirst = !_newestFirst),
                  child: Row(children: [
                    const PzIcon('sort', size: 16, color: Paper.paper2),
                    const SizedBox(width: 6),
                    Text(_newestFirst ? 'Newest first' : 'Oldest first', style: body(12.5, color: Paper.paper2, weight: FontWeight.w600)),
                  ]),
                ),
                const Spacer(),
                if (readable.isNotEmpty) ...[
                  Pressable(
                    onTap: () => _bulkDownload(m, readable, read),
                    child: Row(children: [
                      const PzIcon('downloads', size: 16, color: Paper.paper2),
                      const SizedBox(width: 6),
                      Text('Download…', style: body(12.5, color: Paper.paper2, weight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(width: 16),
                ],
                if (readable.isNotEmpty)
                  Pressable(
                    onTap: () {
                      final all = readable.every(isReadCh);
                      Store.i.setRead(m.id, readable.map((c) => c.id).toList(), !all);
                    },
                    child: Text(readable.every(isReadCh) ? 'Mark all unread' : 'Mark all read', style: body(12.5, color: Paper.paper3, weight: FontWeight.w600)),
                  ),
              ]),
            ),
          ),
          if (_chError != null)
            SliverToBoxAdapter(child: StatePanel(title: 'Couldn’t list chapters', message: '$_chError', icon: 'alert', action: 'Try again', onAction: () => _chapters(force: true)))
          else if (_list == null)
            SliverList.builder(
              itemCount: 6,
              itemBuilder: (_, __) => const Padding(padding: EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8), child: Skeleton(height: 54)),
            )
          else if (chapters.isEmpty)
            SliverToBoxAdapter(
              child: StatePanel(
                title: 'No source has this title yet',
                message: 'Try another source, or check Manga → Sources.',
                icon: 'manga',
                action: 'Check again',
                onAction: () => _chapters(force: true),
              ),
            )
          else
            SliverList.builder(
              itemCount: ordered.length,
              itemBuilder: (c, i) {
                final ch = ordered[i];
                final isRead = isReadCh(ch);
                final current = resume?.chapterId == ch.id || (crossSource && ch.number == resume.chapterNumber);
                return Pressable(
                  scale: 0.985,
                  onTap: ch.externalUrl != null
                      ? () => toast(context, 'This chapter is only on the publisher’s site.')
                      : () => go(context, ReaderView(mediaId: m.id, chapters: readable, index: readable.indexOf(ch), startPage: current && !crossSource ? resume!.page : 0)),
                  onLongPress: () => Store.i.setRead(m.id, [ch.id], !isRead),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: current ? Ink.ink2 : Ink.ink1,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: current ? accentOf(context) : Lines.line),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(ch.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: body(14, weight: FontWeight.w700, color: isRead ? Paper.paper4 : Paper.paper)),
                          if (ch.group != null || ch.publishedAt != null)
                            Text(
                              [ch.group, if (ch.publishedAt != null) Fmt.relativeTime(ch.publishedAt!)].whereType<String>().join(' · '),
                              maxLines: 1,
                              style: body(11.5, color: Paper.paper3),
                            ),
                        ]),
                      ),
                      if (ch.externalUrl != null) const PzIcon('external', size: 16, color: Paper.paper3),
                      if (current) Tag('p${resume!.page + 1}'),
                      if (isRead && !current) const PzIcon('check', size: 16, color: Paper.paper4),
                      if (ch.externalUrl == null)
                        DownloadMark(
                          jobKey: Downloader.chapterKey(ch.id),
                          done: () => Downloader.i.chapterFile(ch.id) != null,
                          onDownload: () => downloadChapters(context, Fmt.snapshotOfDetail(m, lang: lang), [ch]),
                        ),
                    ]),
                  ),
                );
              },
            ),
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.bottom + 32)),
        ],
      ),
    );
  }

  /// The extension a reading entry came from, when it has since been removed.
  Extension? _missingSource(String? chapterId) {
    if (chapterId == null || !chapterId.startsWith('x')) return null;
    final provider = chapterId.substring(0, chapterId.indexOf(':'));
    if (Extensions.i.byProvider(provider) != null) return null;
    return Extensions.i.extensionForSource(provider);
  }

  bool _thin(MediaDetail m, List<MChapter> readable) {
    if (readable.isEmpty) return true;
    final total = m.chapters;
    final last = readable.last.sortKey;
    return total != null && total > 0 && last >= 0 && last < total * 0.8;
  }

  Future<void> _reinstall(Extension e) async {
    toast(context, 'Installing ${e.name}…');
    final err = await Extensions.i.install(e);
    if (!mounted) return;
    if (err != null) {
      toast(context, '${e.name}: $err');
      return;
    }
    final provider = Extensions.i.installed.where((s) => s.pkg == e.pkg).map((s) => s.provider).firstOrNull;
    if (provider != null) Store.i.pinSource(widget.mediaId, provider);
    _chapters(force: true, provider: provider);
  }

  /// After switching source, offer to continue from the same chapter number.
  Future<void> _offerContinue() async {
    final resume = Store.i.readingEntry(widget.mediaId);
    final list = _list;
    if (resume?.chapterNumber == null || list == null || !mounted) return;
    final readable = list.chapters.where((c) => c.externalUrl == null).toList();
    final i = readable.indexWhere((c) => c.number == resume!.chapterNumber);
    if (i < 0 || readable[i].id == resume!.chapterId) return;
    final ok = await confirm(
      context,
      title: 'Continue where you left off?',
      message: 'You were on Chapter ${resume.chapterNumber}. ${providerName(list.provider ?? '')} has it too.',
      action: 'Continue Ch ${resume.chapterNumber}',
    );
    if (ok && mounted) go(context, ReaderView(mediaId: widget.mediaId, chapters: readable, index: i));
  }

  void _pickSource() {
    final list = _list!;
    final more = Extensions.i.searchable.length > list.providers.where((p) => p.provider.startsWith('x')).length;
    pzSheet<void>(context, title: 'Read from', builder: (c) => ListView(shrinkWrap: true, children: [
          SheetOption('Auto pick', sub: 'The source furthest along', selected: Store.i.pinnedSource(widget.mediaId) == null, onTap: () {
            Navigator.pop(c);
            Store.i.pinSource(widget.mediaId, null);
            _chapters();
          }),
          for (final s in list.providers)
            SheetOption(
              providerName(s.provider),
              sub: s.error != null
                  ? 'Unavailable'
                  : s.chapterCount == 0
                      ? 'Doesn’t have this title'
                      : '${s.chapterCount} chapters${s.latest != null ? ' · up to ${s.latest}' : ''}',
              selected: list.provider == s.provider,
              onTap: () async {
                Navigator.pop(c);
                Store.i.pinSource(widget.mediaId, s.provider);
                await _chapters(provider: s.provider);
                _offerContinue();
              },
            ),
          if (more)
            SheetOption('Search every extension', sub: 'Slower: asks all ${Extensions.i.searchable.length} installed', selected: false, onTap: () {
              Navigator.pop(c);
              _chapters(all: true);
            }),
          SheetOption('Install more extensions', sub: 'Mihon extensions add more sites', selected: false, onTap: () async {
            Navigator.pop(c);
            await go(context, const ExtensionsPage());
            _chapters(force: true);
          }),
        ]));
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.text, required this.action, required this.onAction});

  final String title;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accentOf(context).withAlpha(0x1C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accentOf(context).withAlpha(0x55)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: body(14.5, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(text, style: body(12.5, color: Paper.paper2, height: 1.4)),
          const SizedBox(height: 10),
          PzBtn(action, compact: true, primary: true, icon: 'plus', onTap: onAction),
        ]),
      );
}
