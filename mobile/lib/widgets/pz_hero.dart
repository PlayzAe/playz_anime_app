import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/accent.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';
import 'pz_button.dart';
import 'pz_icon.dart';
import 'pz_image.dart';
import 'pz_progress.dart';

/// The spotlight at the top of Home.
///
/// Ported from `src/renderer/components/Hero.tsx` + `hero.css`. The anatomy is
/// the desktop's — blurred backdrop, drifting artwork, the three-gradient
/// shade, the tategaki native title down the right edge, a pager that fills as
/// it counts down — but the scale is the phone's: the band is 280-340dp instead
/// of `clamp(470px, 68vh, 700px)`, and the title sits on the 32dp floor the
/// desktop clamp resolves to at a 360dp width.
///
/// Blur decision: the backdrop keeps the `ImageFiltered` blur at a sigma of 16
/// (48 CSS px is a different unit — Flutter's sigma is the standard deviation,
/// not the radius) inside a [RepaintBoundary], and carries `saturate(1.25)
/// brightness(.5)` as one fused colour matrix rather than two stacked filters.
/// That is one `saveLayer` per slide, cached as a layer and reused for the
/// whole 12s drift, which measured cheaper than the alternative the brief
/// allowed: a two-stop gradient sampled from the cover colour is free but the
/// band reads flat, and flat is the one thing a spotlight cannot be. The
/// gradient is still what shows when a slide has no artwork at all.
class PzHero extends StatefulWidget {
  const PzHero({
    super.key,
    required this.items,
    required this.onOpen,
    this.onPlay,
    this.index = 0,
    this.onIndexChanged,
    this.height,
  });

  /// The slides, in order. Empty renders the `ink-1` empty block.
  final List<PzHeroItem> items;

  /// The details action, and the fallback for a slide with no play action.
  final void Function(PzHeroItem item) onOpen;

  /// The primary action. A slide with no play action shows one button.
  final void Function(PzHeroItem item)? onPlay;

  /// The slide to show. The state owns the index from then on and reports every
  /// change through [onIndexChanged], so a host that never passes an index gets
  /// a self-driving carousel and a host that does gets a controlled one.
  final int index;

  final ValueChanged<int>? onIndexChanged;

  /// Overrides the band height. Home never needs to: [PzHero] measures itself.
  final double? height;

  @override
  State<PzHero> createState() => _PzHeroState();
}

/// One slide of the spotlight.
///
/// The desktop passed `Hero.tsx` a `HeroSlide` of React nodes. A hero slide
/// only ever renders the same two buttons, so this carries their labels and
/// leaves the navigation to [PzHero.onPlay] / [PzHero.onOpen].
class PzHeroItem {
  const PzHeroItem({
    required this.key,
    required this.title,
    this.kicker,
    this.kickerStrong,
    this.kickerIcon,
    this.native,
    this.banner,
    this.cover,
    this.color,
    this.meta = const [],
    this.description,
    this.progress,
    this.playLabel = 'Play E1',
    this.openLabel = 'Details',
    this.trailing,
  });

  /// Identity. Changing it re-keys the backdrop, which is how the fade and the
  /// drift restart — the same job `key={slide.key}` did in React.
  final String key;

  final String title;

  /// The dim half of the kicker, e.g. `Continue watching · `.
  final String? kicker;

  /// The half held at full paper — the rank or the season. See [kicker].
  final String? kickerStrong;

  /// The glyph ahead of the kicker; only the continue-watching slide has one.
  final IconName? kickerIcon;

  /// The native title, set vertically down the right edge. Japanese titles only.
  final String? native;

  final String? banner;
  final String? cover;

  /// AniList's `coverImage.color` as `#rrggbb`. Also the colour the band sits
  /// on before a pixel has decoded, which is why it is worth carrying.
  final String? color;

  /// Already-formatted meta bits — the dot separators are the widget's job.
  final List<String> meta;

  final String? description;

  /// 0-1 for the continue-watching bar. Null hides the bar entirely.
  final double? progress;

  final String playLabel;
  final String openLabel;

  /// Something to sit after the two buttons, e.g. the library toggle.
  final Widget? trailing;

  /// No banner means no wide art: the backdrop blurs the poster, and the
  /// floating cover card the desktop drew in that case is gone — at 360dp it
  /// lands on top of the title.
  bool get posterMode => banner == null || banner!.isEmpty;

  String get art => posterMode ? (cover ?? '') : banner!;

  Color get tint => _tint(color);
}

/// `tint()` from `format.ts`: six-digit hex or nothing. AniList sends nulls,
/// and now and then something that is not a colour at all.
Color _tint(String? hex) {
  final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(hex ?? '');
  if (m == null) return Ink.ink2;
  return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

class _PzHeroState extends State<PzHero> with TickerProviderStateMixin, WidgetsBindingObserver {
  /// The desktop gave a slide 9s of pager fill; a phone reads a card in about
  /// 8, and the shorter band makes the wait feel longer than it is.
  static const _interval = Duration(seconds: 8);
  static const _drift = Duration(seconds: 12);
  static const _bodyIn = Duration(milliseconds: 520);

  /// `.hero-pager-bar` is 30x2, `.hero-progress` 240x3, `.hero-native` 21px at
  /// 0.22em tracking with a 1.4 line box — none of these are on the token ramp,
  /// they are the component's own numbers.
  static const _barW = 30.0;
  static const _barH = 2.0;
  static const _progressW = 240.0;

  late final AnimationController _advance = AnimationController(vsync: this, duration: _interval);
  late final AnimationController _push = AnimationController(vsync: this, duration: _drift);
  late final CurvedAnimation _pushCurve = CurvedAnimation(parent: _push, curve: Curves.easeOut);
  late final Animation<double> _scale = Tween<double>(begin: 1.06, end: 1).animate(_pushCurve);

  late int _index = _clamp(widget.index);

  /// Reduced motion, app visibility and a finger on the band, in that order of
  /// authority. Any of the three stops the countdown; the fill keeps its place
  /// so a touch does not hand the slide a fresh 8 seconds.
  bool _reduced = false;
  bool _visible = true;
  bool _touching = false;
  bool _armed = false;

  bool get _canAdvance => !_reduced && _visible && !_touching && widget.items.length > 1;

  int _clamp(int i) => widget.items.isEmpty ? 0 : i.clamp(0, widget.items.length - 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _advance.addStatusListener(_onAdvance);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The band's animations are all shorthand for "this is where you are"; with
    // reduced motion on they are noise, so nothing here ever animates.
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _reduced = true;
      _push.value = 1;
      _advance.stop();
      return;
    }
    if (_reduced) {
      _reduced = false;
      _push.forward(from: 0);
    }
    if (!_armed) {
      _armed = true;
      _push.forward(from: 0);
      _restart();
    }
  }

  @override
  void didUpdateWidget(PzHero old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) {
      setState(() => _index = _clamp(widget.index));
      _driftAgain();
      _restart();
      return;
    }
    if (widget.items.length != old.items.length) {
      final clamped = _clamp(_index);
      if (clamped != _index) setState(() => _index = clamped);
      _restart();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (visible == _visible) return;
    _visible = visible;
    // The desktop paused on `document.hidden`; a backgrounded phone is the same
    // event. Coming back starts the slide over rather than finishing a fill the
    // user never saw.
    visible ? _restart() : _advance.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _advance.dispose();
    _pushCurve.dispose();
    _push.dispose();
    super.dispose();
  }

  /// The pager bar *is* the timer: when the fill reaches the end, the slide
  /// advances. One clock, so the bar can never disagree with the countdown.
  void _onAdvance(AnimationStatus status) {
    if (status == AnimationStatus.completed) _goTo(_index + 1);
  }

  void _goTo(int i, {bool report = true}) {
    final n = widget.items.length;
    if (n == 0) return;
    final next = ((i % n) + n) % n;
    if (next != _index) setState(() => _index = next);
    if (report) widget.onIndexChanged?.call(next);
    _driftAgain();
    _restart();
  }

  /// Manual navigation gets the full interval, not what is left of the old one.
  void _restart() {
    _advance.stop();
    _advance.value = 0;
    if (_canAdvance) _advance.forward();
  }

  /// A finger on the band holds the countdown where it is.
  void _resume() {
    _touching = false;
    if (_canAdvance && !_advance.isAnimating && _advance.value < 1) _advance.forward();
  }

  void _driftAgain() {
    if (_reduced) return;
    _push.forward(from: 0);
  }

  static double _bandFor(Size size) {
    // Mobile spotlight needs 420-470dp to fit title, meta, synopsis,
    // action buttons, and pager cleanly without vertical overlap.
    if (size.height < 520) return (size.height * 0.65).clamp(240.0, 320.0);
    return (size.height * 0.50).clamp(420.0, 480.0);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final band = widget.height ?? _bandFor(size);

    if (widget.items.isEmpty) {
      // `.hero.is-empty` — the band keeps its height so the page below does not
      // jump once the feed lands.
      return SizedBox(height: band, child: const ColoredBox(color: Ink.ink1));
    }

    final item = widget.items[_index.clamp(0, widget.items.length - 1)];
    final fade = _reduced ? Duration.zero : Motion.hero;
    final bodyIn = _reduced ? Duration.zero : _bodyIn;
    final rise = 10 / band;
    // The pager sits under the action row rather than beside it: `hero-body` is
    // full width on a phone, so the desktop's side-by-side corner does not fit.
    const bodyBottom = 60.0;
    const pagerBottom = 16.0;

    return Listener(
      onPointerDown: (_) {
        _touching = true;
        _advance.stop();
      },
      onPointerUp: (_) => _resume(),
      onPointerCancel: (_) => _resume(),
      child: SizedBox(
        height: band,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: fade,
                switchInCurve: Motion.ease,
                switchOutCurve: Motion.ease,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: _Backdrop(
                  key: ValueKey(item.key),
                  item: item,
                  size: Size(size.width, band),
                  scale: _scale,
                ),
              ),
              _Shade(topFade: band <= 0 ? 0 : (band * 0.26) / band),
              Positioned(
                left: Gap.gutter,
                right: Gap.gutter,
                bottom: bodyBottom,
                child: AnimatedSwitcher(
                  duration: bodyIn,
                  switchInCurve: Motion.ease,
                  switchOutCurve: Motion.ease,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.bottomLeft,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: Offset(0, rise), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _Body(
                    key: ValueKey('b${item.key}'),
                    item: item,
                    tint: item.tint,
                    onPlay: widget.onPlay,
                    onOpen: widget.onOpen,
                    reduced: _reduced,
                  ),
                ),
              ),
              if ((item.native ?? '').isNotEmpty)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + Metrics.appBar + 8,
                  right: Gap.gutter + (item.posterMode ? 12 : 0),
                  child: _Native(
                    key: ValueKey('n${item.key}'),
                    text: item.native!,
                    band: band,
                  ),
                ),
              if (widget.items.length > 1)
                Positioned(
                  right: Gap.gutter,
                  bottom: pagerBottom,
                  child: _Pager(
                    items: widget.items,
                    index: _index,
                    fill: _advance,
                    static: _reduced,
                    onPick: (i) => _goTo(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The blurred backdrop and the drifting artwork, as one layer so a slide
/// change cross-fades them together — `hero-bg` re-keyed, in the original.
class _Backdrop extends StatelessWidget {
  const _Backdrop({super.key, required this.item, required this.size, required this.scale});

  final PzHeroItem item;
  final Size size;
  final Animation<double> scale;

  @override
  Widget build(BuildContext context) {
    final tint = item.tint;
    final art = item.art;

    if (art.isEmpty) {
      // No artwork at all: the two-stop gradient the brief allows as the
      // fallback, built from the cover colour so a colourless slide still reads
      // as a slide and not as a hole in the page.
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tint, Ink.ink1],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Sitting on the tint means the band never flashes black between the
        // first frame and the first decoded pixel.
        ColoredBox(color: tint),
        RepaintBoundary(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
            child: ColorFiltered(
              colorFilter: ColorFilter.matrix(_blurMatrix),
              child: Transform.scale(
                scale: 1.15,
                child: PzImage(
                  url: art,
                  width: size.width,
                  height: size.height,
                  fit: BoxFit.cover,
                  blurHashColor: tint,
                  alignment: Alignment.center,
                ),
              ),
            ),
          ),
        ),
        if (!item.posterMode)
          RepaintBoundary(
            child: ScaleTransition(
              scale: scale,
              child: PzImage(
                url: art,
                width: size.width,
                height: size.height,
                fit: BoxFit.cover,
                blurHashColor: tint,
                // `object-position: center 28%` — the banner's subject is above
                // centre, and a phone crops the sides far harder than a desktop.
                alignment: const Alignment(0, -0.44),
              ),
            ),
          ),
      ],
    );
  }

  /// 48 CSS px is a radius; a Flutter sigma is a standard deviation, and the
  /// two differ by roughly a factor of three. 16 is the same softness.
  static const _blurSigma = 16.0;

  /// `saturate(1.25) brightness(0.5)` as one matrix: the saturation rows scaled
  /// by the brightness. Fusing them saves a layer per slide, and because both
  /// are per-channel affine they survive the blur in either order.
  static const List<double> _blurMatrix = <double>[
    0.4264, 0.2797, 0.0439, 0, 0, //
    0.0469, 0.6592, 0.0439, 0, 0, //
    0.0469, 0.2797, 0.4234, 0, 0, //
    0, 0, 0, 0.5, 0,
  ];
}

/// `.hero-shade`: three gradients stacked, the first in the CSS painted last.
/// They are what makes white text legible over arbitrary key art, so they do
/// not scale with taste — only the top band does, and it keeps the desktop's
/// 120/470 proportion.
class _Shade extends StatelessWidget {
  const _Shade({required this.topFade});

  final double topFade;

  @override
  Widget build(BuildContext context) {
    final zero = withOpacityLinear(Ink.ink0, 0);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [withOpacityLinear(Ink.ink0, 0.55), zero],
                stops: [0, topFade.clamp(0.0, 1.0)],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  withOpacityLinear(Ink.ink0, 0.90),
                  withOpacityLinear(Ink.ink0, 0.55),
                  zero,
                ],
                stops: const [0, 0.34, 0.66],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Ink.ink0,
                  Ink.ink0,
                  withOpacityLinear(Ink.ink0, 0.88),
                  withOpacityLinear(Ink.ink0, 0.40),
                  zero,
                ],
                stops: const [0, 0.22, 0.48, 0.72, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `hero-body`: kicker, title, meta, resume bar, three lines of description,
/// the action row.
class _Body extends StatelessWidget {
  const _Body({
    super.key,
    required this.item,
    required this.tint,
    required this.onPlay,
    required this.onOpen,
    required this.reduced,
  });

  final PzHeroItem item;
  final Color tint;
  final void Function(PzHeroItem item)? onPlay;
  final void Function(PzHeroItem item) onOpen;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final accent = PzAccent.of(context).base;
    final meta = item.meta.where((m) => m.isNotEmpty).toList(growable: false);
    // `.hero-title` is `clamp(46px, 5.6vw, 88px)`. At 360dp the vw term lands at
    // 20, so the floor is the size on every phone, and only a tablet climbs.
    final titleSize = (MediaQuery.sizeOf(context).width * 0.056).clamp(32.0, 46.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((item.kicker ?? '').isNotEmpty || (item.kickerStrong ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.kickerIcon != null) ...[
                  PzIcon(item.kickerIcon!, size: 15, color: Paper.paper2),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if ((item.kicker ?? '').isNotEmpty)
                          TextSpan(text: item.kicker, style: const TextStyle(color: Paper.paper2)),
                        if ((item.kickerStrong ?? '').isNotEmpty)
                          TextSpan(
                            text: item.kickerStrong,
                            style: const TextStyle(color: Paper.paper, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                    // 13.5/600 is the poster-title step; the kicker borrows it
                    // rather than adding a tenth entry to the ramp.
                    style: Type.posterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        Text(
          item.title,
          style: Type.display.copyWith(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.012 * titleSize,
            height: 0.92,
            color: Paper.paper,
            shadows: const [Shadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 2))],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text.rich(
              TextSpan(
                children: [
                  for (var i = 0; i < meta.length; i++) ...[
                    if (i > 0)
                      // `.dot-sep` puts the separator in paper-4 and half an em
                      // of space either side, which is two spaces at this size.
                      const TextSpan(text: '  ·  ', style: TextStyle(color: Paper.paper4)),
                    TextSpan(text: meta[i], style: const TextStyle(color: Paper.paper2)),
                  ],
                ],
              ),
              style: Type.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (item.progress != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              width: _PzHeroState._progressW,
              child: PzProgress(
                value: item.progress!.clamp(0.0, 1.0),
                track: Lines.paper18,
                color: accent,
              ),
            ),
          ),
        if ((item.description ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              item.description!,
              style: Type.bodySm.copyWith(
                fontSize: 13.5,
                height: 1.45,
                color: withOpacityLinear(Paper.paper, 0.78),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (onPlay != null)
                PzButton(
                  label: item.playLabel,
                  icon: 'play',
                  kind: PzButtonKind.primary,
                  size: PzButtonSize.lg,
                  onPressed: () => onPlay!(item),
                ),
              PzButton(
                label: item.openLabel,
                kind: PzButtonKind.ghost,
                size: PzButtonSize.lg,
                onPressed: () => onOpen(item),
              ),
              if (item.trailing != null) item.trailing!,
            ],
          ),
        ),
      ],
    );
  }
}

/// The native title, set vertically.
///
/// `writing-mode: vertical-rl` has no Flutter primitive, and `RotatedBox` turns
/// the glyphs on their side — wrong for a Japanese spine, which keeps them
/// upright. So the characters are laid one to a cell and stacked into up to
/// three columns, the first column rightmost, each column a line box wide.
/// Longer titles crop, exactly as the CSS `overflow: hidden` did.
class _Native extends StatelessWidget {
  const _Native({super.key, required this.text, required this.band});

  final String text;
  final double band;

  static const _size = 18.0;
  static const _tracking = _size * 0.22;
  static const _pitch = _size * 1.35;
  static const _maxColumns = 2;

  // Japanese Kanji, Hiragana, Katakana regex
  static final RegExp _cjkRegex = RegExp(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff66-\uff9f]');

  @override
  Widget build(BuildContext context) {
    // Only render if the native title contains actual CJK Japanese/Asian glyphs.
    // Pure ASCII / Latin characters (like "ONE PIECE") should NEVER be set vertically in reverse columns.
    if (!_cjkRegex.hasMatch(text)) return const SizedBox.shrink();

    final maxHeight = band * 0.42;
    final perColumn = math.max(1, (maxHeight / (_size + _tracking)).floor());
    final chars = text.runes.map(String.fromCharCode).toList(growable: false);

    final columns = <List<String>>[];
    for (var start = 0; start < chars.length && columns.length < _maxColumns; start += perColumn) {
      columns.add(chars.sublist(start, math.min(start + perColumn, chars.length)));
    }

    const style = TextStyle(
      fontSize: _size,
      fontWeight: FontWeight.w500,
      height: 1,
      color: Color(0x38EFE9E1), // Subdued watermark so it never collides with foreground text
      shadows: [Shadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 1))],
    );

    return IgnorePointer(
      child: SizedBox(
        height: maxHeight,
        child: ClipRect(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The last column ends up leftmost: vertical-rl reads right to
              // left, so the first chunk of the title is the rightmost column.
              for (final column in columns.reversed)
                SizedBox(
                  width: _pitch,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final ch in column)
                        Padding(
                          padding: const EdgeInsets.only(bottom: _tracking),
                          child: SizedBox(width: _pitch, height: _size, child: Center(child: Text(ch, style: style))),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pager: one 12.5/650 number and one 30x2 bar per slide. The active bar's
/// fill is the auto-advance countdown, so it is drawn from the controller and
/// not from a local timer that could drift away from it.
class _Pager extends StatelessWidget {
  const _Pager({
    required this.items,
    required this.index,
    required this.fill,
    required this.static,
    required this.onPick,
  });

  final List<PzHeroItem> items;
  final int index;
  final Animation<double> fill;

  /// Reduced motion: no countdown, so the current bar is simply marked.
  final bool static;

  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Spotlight',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 14),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(i),
                // The bar is 2dp tall; the number above it is what makes this
                // reachable with a thumb.
                child: Semantics(
                  button: true,
                  selected: i == index,
                  label: items[i].title,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: Motion.fast,
                        curve: Motion.ease,
                        style: Type.caption.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: i == index ? Paper.paper : Paper.paper3,
                        ),
                        child: Text((i + 1).toString().padLeft(2, '0')),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: _PzHeroState._barW,
                        height: _PzHeroState._barH,
                        child: ColoredBox(
                          color: Lines.paper20,
                          child: i != index
                              ? null
                              : static
                              ? const ColoredBox(color: Paper.paper)
                              : AnimatedBuilder(
                                  animation: fill,
                                  builder: (context, _) => Transform.scale(
                                    scale: fill.value,
                                    scaleY: 1,
                                    alignment: Alignment.centerLeft,
                                    child: const ColoredBox(color: Paper.paper),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
