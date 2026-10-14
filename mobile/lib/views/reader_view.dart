import 'dart:async';

import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/local.dart';
import '../services/anilist.dart';
import '../services/downloader.dart';
import '../services/format.dart';
import '../services/store.dart';
import '../sources/manga/providers.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_icon.dart';
import '../widgets/pz_image.dart';

/// Mihon's reading modes.
enum ReadMode {
  pagedLtr('Paged (left to right)', 'arrowRight'),
  pagedRtl('Paged (right to left)', 'arrowLeft'),
  pagedVertical('Paged (vertical)', 'chevronDown'),
  strip('Long strip', 'list'),
  stripGaps('Long strip with gaps', 'grid');

  const ReadMode(this.label, this.icon);
  final String label;
  final String icon;

  bool get isStrip => this == strip || this == stripGaps;

  static ReadMode parse(String v) => values.firstWhere((m) => m.name == v, orElse: () => strip);
}

/// The reader: long strip (with an adjustable page width) or paged in any
/// direction. Tap the middle for the controls, the edges to turn pages.
class ReaderView extends StatefulWidget {
  const ReaderView({super.key, required this.mediaId, required this.chapters, required this.index, this.startPage = 0});

  final int mediaId;
  final List<MChapter> chapters;
  final int index;
  final int startPage;

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  late int _i = widget.index;
  List<MPage>? _pages;
  Object? _error;
  int _page = 0;
  bool _chrome = true;
  late ReadMode _mode = ReadMode.parse(Store.i.settings.readMode);
  late double _width = Store.i.settings.readerWidth.clamp(0.5, 1.0);
  late ReaderFit _fit = Store.i.settings.readerFit == ReaderFit.height ? ReaderFit.height : ReaderFit.width;
  late String _bg = Store.i.settings.readerBackground;
  PageController? _pc;
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _token = 0;

  MChapter get _ch => widget.chapters[_i];

  Color get _bgColor => switch (_bg) {
        'white' => const Color(0xFFF4F1EA),
        'ink' => Ink.ink0,
        _ => Colors.black,
      };

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (Store.i.settings.keepScreenOn) WakelockPlus.enable();
    _scroll.addListener(_onScroll);
    _open(_i, widget.startPage);
  }

  @override
  void dispose() {
    _save();
    _pc?.dispose();
    _scroll.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _open(int i, int startPage) async {
    _save();
    final token = ++_token;
    setState(() {
      _i = i;
      _pages = null;
      _error = null;
      _page = startPage;
      _keys.clear();
    });
    try {
      // A downloaded chapter reads from disk, so it works offline.
      final pages = await Downloader.i.offlinePages(widget.chapters[i].id) ?? await MangaProviders.i.pages(widget.chapters[i]);
      if (token != _token || !mounted) return;
      if (pages.isEmpty) throw StateError('This chapter has no pages on the source.');
      _pc?.dispose();
      _pc = PageController(initialPage: startPage.clamp(0, pages.length - 1));
      setState(() => _pages = pages);
      if (_mode.isStrip && startPage > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpStrip(startPage));
      }
      _precache(startPage);
      _save();
    } catch (e) {
      if (token == _token && mounted) setState(() => _error = e);
    }
  }

  /// Warm the next two pages so turning is instant.
  void _precache(int from) {
    final pages = _pages;
    if (pages == null || _mode.isStrip) return;
    for (var n = from + 1; n <= from + 2 && n < pages.length; n++) {
      precacheImage(pageImageProvider(pages[n]), context).catchError((_) {});
    }
  }

  void _jumpStrip(int page) {
    final ctx = _keys[page]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 1));
    } else if (_scroll.hasClients) {
      _scroll.jumpTo((page * 900.0).clamp(0, _scroll.position.maxScrollExtent));
    }
  }

  void _onScroll() {
    final pages = _pages;
    if (pages == null || !_mode.isStrip) return;
    // The page that covers the middle of the screen.
    final mid = MediaQuery.of(context).size.height / 2;
    var best = _page;
    for (final e in _keys.entries) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y <= mid && y + box.size.height > mid) {
        best = e.key;
        break;
      }
    }
    if (best != _page) setState(() => _page = best);
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 4) _markRead();
  }

  Future<void> _save() async {
    final pages = _pages;
    if (pages == null || widget.mediaId <= 0) return;
    try {
      final m = await AniList.i.media(widget.mediaId);
      Store.i.saveReading(ReadingEntry(
        media: Fmt.snapshotOfDetail(m, lang: Store.i.settings.titleLanguage),
        chapterId: _ch.id,
        chapterNumber: _ch.number,
        chapterTitle: _ch.title,
        page: _page,
        pages: pages.length,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      if (_page >= pages.length - 1) _markRead();
    } catch (_) {}
  }

  void _markRead() {
    if (widget.mediaId <= 0) return;
    if (!Store.i.readChapters(widget.mediaId).contains(_ch.id)) Store.i.setRead(widget.mediaId, [_ch.id], true);
  }

  void _turn(int delta) {
    final pages = _pages;
    if (pages == null) return;
    final next = _page + delta;
    if (next < 0) {
      if (_i > 0) _open(_i - 1, 0);
      return;
    }
    if (next >= pages.length) {
      _markRead();
      if (_i + 1 < widget.chapters.length) {
        _open(_i + 1, 0);
      } else {
        toast(context, 'That’s the latest chapter');
      }
      return;
    }
    _pc?.animateToPage(next, duration: const Duration(milliseconds: 240), curve: kEase);
  }

  void _tap(TapUpDetails d, Size size) {
    if (_mode.isStrip) {
      setState(() => _chrome = !_chrome);
      return;
    }
    final vertical = _mode == ReadMode.pagedVertical;
    final pos = vertical ? d.localPosition.dy / size.height : d.localPosition.dx / size.width;
    if (pos > 0.3 && pos < 0.7) {
      setState(() => _chrome = !_chrome);
      return;
    }
    final forward = _mode == ReadMode.pagedRtl ? pos < 0.3 : pos > 0.7;
    _turn(forward ? 1 : -1);
  }

  void _setMode(ReadMode m) {
    if (m == _mode) return;
    final keep = _page;
    Store.i.patchSettings((s) => s.copyWith(readMode: m.name));
    _pc?.dispose();
    _pc = PageController(initialPage: keep);
    setState(() {
      _mode = m;
      _keys.clear();
    });
    if (m.isStrip) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpStrip(keep));
  }

  void _settings() {
    pzSheet<void>(context,
        title: 'Reading mode',
        builder: (c) => StatefulBuilder(
              builder: (c, set) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  LayoutBuilder(builder: (c, box) {
                    final w = (box.maxWidth - 10) / 2;
                    return Wrap(spacing: 10, runSpacing: 10, children: [
                      for (final m in ReadMode.values)
                        SizedBox(
                          width: w,
                          child: _ModeButton(
                            mode: m,
                            on: _mode == m,
                            onTap: () {
                              _setMode(m);
                              set(() {});
                            },
                          ),
                        ),
                    ]);
                  }),
                  const SizedBox(height: 18),
                  if (_mode.isStrip) ...[
                    Row(children: [
                      Text('Page width', style: body(13, color: Paper.paper3, weight: FontWeight.w700)),
                      const Spacer(),
                      Text('${(_width * 100).round()}%', style: body(13, weight: FontWeight.w700)),
                    ]),
                    Slider(
                      value: _width,
                      min: 0.5,
                      max: 1,
                      divisions: 10,
                      activeColor: accentOf(context),
                      onChanged: (v) {
                        setState(() => _width = v);
                        set(() {});
                      },
                      onChangeEnd: (v) => Store.i.patchSettings((s) => s.copyWith(readerWidth: v)),
                    ),
                  ] else ...[
                    Text('Scale', style: body(13, color: Paper.paper3, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Segmented<ReaderFit>(
                      value: _fit,
                      options: const [(ReaderFit.width, 'Fit width'), (ReaderFit.height, 'Fit screen')],
                      onChanged: (v) {
                        Store.i.patchSettings((s) => s.copyWith(readerFit: v));
                        setState(() => _fit = v);
                        set(() {});
                      },
                    ),
                    const SizedBox(height: 6),
                    Text('Fit width fills the screen side to side and scrolls tall pages. Pinch to zoom either way.',
                        style: body(12, color: Paper.paper3)),
                  ],
                  const SizedBox(height: 16),
                  Text('Background', style: body(13, color: Paper.paper3, weight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Segmented<String>(
                    value: _bg,
                    options: const [('black', 'Black'), ('ink', 'Ink'), ('white', 'White')],
                    onChanged: (v) {
                      Store.i.patchSettings((s) => s.copyWith(readerBackground: v));
                      setState(() => _bg = v);
                      set(() {});
                    },
                  ),
                ]),
              ),
            ));
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Scaffold(
      backgroundColor: _bgColor,
      body: LayoutBuilder(builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d, size),
              child: _error != null
                  ? Center(
                      child: StatePanel(
                        title: 'Couldn’t open ${_ch.label}',
                        message: '$_error',
                        icon: 'alert',
                        action: 'Try again',
                        onAction: () => _open(_i, _page),
                      ),
                    )
                  : pages == null
                      ? Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: accentOf(context))))
                      : _mode.isStrip
                          ? _stripView(pages, size)
                          : _pagedView(pages, size),
            ),
          ),
          _topBar(),
          if (pages != null) _bottomBar(pages),
        ]);
      }),
    );
  }

  Widget _stripView(List<MPage> pages, Size size) {
    final w = size.width * _width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final gap = _mode == ReadMode.stripGaps ? 14.0 : 0.0;
    return ListView.builder(
      controller: _scroll,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.zero,
      cacheExtent: size.height * 2.5,
      itemCount: pages.length + 1,
      itemBuilder: (c, i) {
        if (i == pages.length) return _chapterEnd();
        final key = _keys.putIfAbsent(i, GlobalKey.new);
        return Padding(
          key: key,
          padding: EdgeInsets.only(bottom: gap),
          child: Center(
            child: SizedBox(
              width: w,
              child: Image(
                // Decode at screen width: long webtoon strips stay light on memory.
                image: ResizeImage.resizeIfNeeded((w * dpr).round(), null, pageImageProvider(pages[i])),
                width: w,
                fit: BoxFit.fitWidth,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                frameBuilder: (c, child, frame, sync) => frame == null && !sync
                    ? SizedBox(height: w * 1.4, child: Center(child: Text('${i + 1}', style: display(40, color: Paper.paper4))))
                    : child,
                errorBuilder: (c, e, s) => _pageError(i, w),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pageError(int i, double h) => SizedBox(
        height: 260,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Page ${i + 1} didn’t load', style: body(13, color: Paper.paper3)),
            const SizedBox(height: 8),
            PzBtn('Reload chapter', compact: true, icon: 'refresh', onTap: () => _open(_i, i)),
          ]),
        ),
      );

  Widget _pagedView(List<MPage> pages, Size size) => PageView.builder(
        controller: _pc,
        scrollDirection: _mode == ReadMode.pagedVertical ? Axis.vertical : Axis.horizontal,
        reverse: _mode == ReadMode.pagedRtl,
        itemCount: pages.length,
        onPageChanged: (p) {
          setState(() => _page = p);
          _precache(p);
          if (p == pages.length - 1) _markRead();
        },
        itemBuilder: (c, i) => _PagedPage(
          page: pages[i],
          size: size,
          fitWidth: _fit == ReaderFit.width && _mode != ReadMode.pagedVertical,
          index: i,
          onError: () => _pageError(i, size.height),
        ),
      );

  Widget _chapterEnd() {
    final next = _i + 1 < widget.chapters.length ? widget.chapters[_i + 1] : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 120),
      child: Column(children: [
        Text('End of ${_ch.label}', style: body(14, color: Paper.paper3, weight: FontWeight.w700)),
        const SizedBox(height: 14),
        if (next != null)
          PzBtn('Next: ${next.label}', icon: 'arrowRight', primary: true, onTap: () {
            _markRead();
            _open(_i + 1, 0);
          })
        else
          Text('You’re caught up.', style: body(14)),
      ]),
    );
  }

  Widget _topBar() => AnimatedPositioned(
        duration: kMed,
        curve: kEase,
        top: _chrome ? 0 : -110,
        left: 0,
        right: 0,
        child: Container(
          padding: EdgeInsets.fromLTRB(6, MediaQuery.of(context).padding.top + 6, 6, 10),
          decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xF00C0B0A), Color(0x000C0B0A)])),
          child: Row(children: [
            RoundIcon('arrowLeft', filled: false, onTap: () => Navigator.pop(context)),
            const SizedBox(width: 4),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_ch.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(14.5, weight: FontWeight.w700)),
                Text(providerName(_ch.provider), style: body(11.5, color: Paper.paper3)),
              ]),
            ),
            RoundIcon('settings', filled: false, onTap: _settings),
          ]),
        ),
      );

  Widget _bottomBar(List<MPage> pages) {
    final rtl = _mode == ReadMode.pagedRtl;
    return AnimatedPositioned(
      duration: kMed,
      curve: kEase,
      bottom: _chrome ? 0 : -130,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(10, 18, 10, MediaQuery.of(context).padding.bottom + 10),
        decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xF00C0B0A), Color(0x000C0B0A)])),
        child: Directionality(
          // Right-to-left reading puts page 1 on the right, like the book.
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Row(children: [
            RoundIcon('prev', size: 38, iconSize: 16, onTap: _i > 0 ? () => _open(_i - 1, 0) : null),
            const SizedBox(width: 8),
            Text('${_page + 1}', style: body(12.5, weight: FontWeight.w700)),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  activeTrackColor: accentOf(context),
                  inactiveTrackColor: Colors.white24,
                  thumbColor: accentOf(context),
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: _page.clamp(0, pages.length - 1).toDouble(),
                  max: (pages.length - 1).toDouble().clamp(1, double.infinity),
                  onChanged: (v) {
                    final p = v.round();
                    setState(() => _page = p);
                    if (_mode.isStrip) {
                      _jumpStrip(p);
                    } else {
                      _pc?.jumpToPage(p);
                    }
                  },
                ),
              ),
            ),
            Text('${pages.length}', style: body(12.5, color: Paper.paper3)),
            const SizedBox(width: 8),
            RoundIcon('next', size: 38, iconSize: 16, onTap: _i + 1 < widget.chapters.length ? () => _open(_i + 1, 0) : null),
          ]),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.mode, required this.on, required this.onTap});

  final ReadMode mode;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = accentOf(context);
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: kFast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: on ? a.withAlpha(0x2A) : Ink.ink2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? a : Lines.line),
        ),
        child: Row(children: [
          PzIcon(mode.icon, size: 18, color: on ? a : Paper.paper2),
          const SizedBox(width: 10),
          Expanded(
            child: Text(mode.label, maxLines: 2, style: body(12.5, weight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Paper.paper : Paper.paper2)),
          ),
        ]),
      ),
    );
  }
}

/// One page in paged mode. Fit width fills the screen side to side and lets a
/// tall page scroll; fit screen shows the whole page. Pinch-zoom on both.
class _PagedPage extends StatelessWidget {
  const _PagedPage({required this.page, required this.size, required this.fitWidth, required this.index, required this.onError});

  final MPage page;
  final Size size;
  final bool fitWidth;
  final int index;
  final Widget Function() onError;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final image = Image(
      image: ResizeImage.resizeIfNeeded((size.width * dpr * 1.5).round(), null, pageImageProvider(page)),
      width: fitWidth ? size.width : null,
      fit: fitWidth ? BoxFit.fitWidth : BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (c, child, frame, sync) => frame == null && !sync
          ? SizedBox(width: size.width, height: size.height, child: Center(child: Text('${index + 1}', style: display(48, color: Paper.paper4))))
          : child,
      errorBuilder: (c, e, s) => onError(),
    );
    return InteractiveViewer(
      maxScale: 4,
      child: fitWidth
          ? SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(constraints: BoxConstraints(minHeight: size.height), child: Center(child: image)),
            )
          : Center(child: image),
    );
  }
}
