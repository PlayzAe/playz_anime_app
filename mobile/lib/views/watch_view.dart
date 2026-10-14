import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/local.dart';
import '../models/media.dart';
import '../models/stream.dart';
import '../services/anilist.dart';
import '../services/downloader.dart';
import '../services/format.dart';
import '../services/native.dart';
import '../services/net.dart';
import '../services/store.dart';
import '../services/stream_resolver.dart';
import '../sources/ani/episodes.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../widgets/pz_icon.dart';
import '../widgets/pz_image.dart';
import '../widgets/subtitle_style.dart';
import 'download_sheet.dart';

/// The watch page. Port of `Watch.tsx` + `DirectPlayer.tsx`, rebuilt for touch.
///
/// Opens straight into landscape fullscreen (Settings → Watching → Auto-rotate),
/// with VLC-style gestures: double-tap seeks, swipe left edge for brightness,
/// right edge for volume, sideways to scrub, hold for 2×. No demo stream exists
/// anywhere: when an episode can't be resolved the user gets the reason and a
/// way forward.
class WatchView extends StatefulWidget {
  const WatchView({super.key, required this.mediaId, this.episode = 1});

  final int mediaId;
  final int episode;

  @override
  State<WatchView> createState() => _WatchViewState();
}

enum _Fit { fit, fill, zoom }

class _WatchViewState extends State<WatchView> with WidgetsBindingObserver {
  MediaDetail? _media;
  EpisodeList? _eps;
  String? _loadError;

  late int _ep = widget.episode;
  late Audio _audio = Store.i.settings.preferDub ? Audio.dub : Audio.sub;

  VideoPlayerController? _vc;
  ResolvedStream? _stream;
  StreamVariant? _variant;
  String? _playError;
  bool _resolving = false;
  bool _slow = false;
  Timer? _slowTimer;
  bool _embed = Store.i.settings.player == PlayerMode.embed;
  String? _embedError;
  int _token = 0;

  /// Some phones (seen on a Galaxy Fold) never draw frames into the texture
  /// view; a platform view fixes them. Switched on by the stall watchdog.
  static bool _surfaceView = false;
  Duration _lastPos = Duration.zero;
  DateTime _lastMove = DateTime.now();
  bool _wantPlay = false;
  int _stalls = 0;
  Timer? _watchdog;

  List<_Cue> _cues = const [];
  SubtitleTrack? _sub;
  late SubStyle _subStyle = SubStyle.of(Store.i.settings);

  bool _controls = true;
  bool _locked = false;
  bool _full = false;
  bool _pip = false;
  bool _pipOk = false;
  double _speed = 1;
  bool _boost = false;
  _Fit _fit = _Fit.fit;
  Timer? _hideTimer;
  Timer? _saveTimer;
  bool _markedWatched = false;
  bool _skippedIntro = false;
  bool _addedToList = false;

  // Gesture feedback.
  int _flashSide = 0; // -1 left, 1 right
  int _flashSeconds = 0;
  Timer? _flashTimer;
  Offset? _tapAt;
  double? _dragStartX;
  Duration? _dragFrom;
  Duration? _dragTo;

  // Vertical swipes: brightness on the left, volume on the right.
  String? _hud; // 'brightness' | 'volume'
  double _hudValue = 0;
  Timer? _hudTimer;
  double? _vStartY;
  double _vStartValue = 0;

  // Autoplay countdown.
  int? _nextIn;
  Timer? _nextTimer;

  StreamSubscription<String>? _mediaSub;

  int get _step => Store.i.settings.seekSeconds.clamp(3, 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    Native.pip.addListener(_onPip);
    _mediaSub = Native.media.stream.listen(_onMediaButton);
    Native.pipSupported().then((v) {
      if (mounted) setState(() => _pipOk = v);
    });
    if (Store.i.settings.autoRotate) _setFull(true);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveHistory();
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _flashTimer?.cancel();
    _nextTimer?.cancel();
    _hudTimer?.cancel();
    _slowTimer?.cancel();
    _watchdog?.cancel();
    _mediaSub?.cancel();
    Native.pip.removeListener(_onPip);
    Native.armPip(false);
    Native.stopPlaying();
    Native.setBrightness(-1);
    _vc?.removeListener(_tick);
    _vc?.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause when the app leaves the screen, unless it went into picture-in-picture.
    if (state == AppLifecycleState.paused && !_pip) {
      _saveHistory();
      _vc?.pause();
    }
  }

  void _onPip() {
    if (!mounted) return;
    setState(() => _pip = Native.pip.value);
  }

  void _onMediaButton(String action) {
    final vc = _vc;
    if (vc == null) return;
    switch (action) {
      case 'play':
        _wantPlay = true;
        vc.play();
      case 'pause':
        _wantPlay = false;
        vc.pause();
      case 'next':
        if (_next != null) _play(_next!.number);
      case 'back':
        _seekBy(-_step);
      case 'forward':
        _seekBy(_step);
    }
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _load({bool force = false}) async {
    setState(() => _loadError = null);
    try {
      final media = await AniList.i.media(widget.mediaId);
      if (!mounted) return;
      setState(() => _media = media);
      final eps = await listEpisodes(widget.mediaId, force: force);
      if (!mounted) return;
      setState(() => _eps = eps);
      if (!eps.hasDub) _audio = Audio.sub;
      if (!eps.available) {
        setState(() => _playError = 'unavailable');
        return;
      }
      // "Play E1" on a show whose source numbers from 13 (split cours): start at its first episode.
      if (_episode(_ep) == null && eps.episodes.isNotEmpty && widget.episode == 1) _ep = eps.episodes.first.number;
      _play(_ep, resume: true);
    } catch (e) {
      if (!mounted) return;
      // Offline: the downloads still play, listed as the episode set.
      final local = Downloader.i.episodesFor(widget.mediaId)..sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
      if (local.isNotEmpty) {
        setState(() => _eps = EpisodeList(
              mediaId: widget.mediaId,
              fallback: true,
              hasDub: false,
              episodes: [for (final j in local) Episode(number: j.episode ?? 0, title: j.label)],
            ));
        if (local.every((j) => j.episode != _ep)) _ep = local.first.episode ?? _ep;
        _play(_ep, resume: true);
        return;
      }
      setState(() => _loadError = '$e');
    }
  }

  Episode? _episode(int n) {
    for (final e in _eps?.episodes ?? const <Episode>[]) {
      if (e.number == n) return e;
    }
    return null;
  }

  Episode? get _current => _episode(_ep);
  Episode? get _next {
    final list = _eps?.episodes ?? const <Episode>[];
    final i = list.indexWhere((e) => e.number == _ep);
    return i >= 0 && i + 1 < list.length ? list[i + 1] : null;
  }

  Episode? get _prev {
    final list = _eps?.episodes ?? const <Episode>[];
    final i = list.indexWhere((e) => e.number == _ep);
    return i > 0 ? list[i - 1] : null;
  }

  /// Episode title only when it says more than "Episode N".
  String? _titleOf(Episode? e) {
    final t = e?.title;
    return t == null || RegExp(r'^episode\s*\d+$', caseSensitive: false).hasMatch(t.trim()) ? null : t;
  }

  String get _title => _media == null ? '' : Fmt.titleOf(_media!, lang: Store.i.settings.titleLanguage);

  Future<void> _play(int ep, {bool resume = false, bool force = false, Duration? at, bool retried = false}) async {
    _saveHistory();
    final token = ++_token;
    _nextTimer?.cancel();
    _watchdog?.cancel();
    _slowTimer?.cancel();
    final old = _vc;
    old?.removeListener(_tick);
    setState(() {
      _ep = ep;
      _vc = null;
      _stream = null;
      _playError = null;
      _embedError = null;
      _resolving = true;
      _slow = false;
      _nextIn = null;
      _cues = const [];
      _sub = null;
      _markedWatched = false;
      _skippedIntro = false;
    });
    await old?.dispose();

    // A downloaded copy plays from disk first, so offline viewing just works.
    final local = Downloader.i.episodeFile(widget.mediaId, ep, _audio);
    if (local != null && File(local.outputFile!).existsSync()) {
      try {
        final stream = _offlineStream(local);
        await _open(stream, stream.variants.first, at ?? (resume ? _resumeAt(ep) : null), token);
        _pickSubtitle(stream);
        return;
      } catch (_) {
        // Fall through to streaming if the file can't be opened.
      }
    }

    final episode = _episode(ep);
    final url = episode?.urlFor(_audio);
    if (url == null) {
      setState(() {
        _resolving = false;
        _playError = 'This episode has no ${_audio.wire} stream yet.';
      });
      return;
    }
    if (_embed) {
      setState(() => _resolving = false);
      _notify(false);
      return;
    }

    _slowTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && token == _token && _resolving) setState(() => _slow = true);
    });
    try {
      final stream = await StreamResolver.i.resolve(url, force: force);
      if (token != _token || !mounted) return;
      final variant = _pickVariant(stream);
      await _open(stream, variant, at ?? (resume ? _resumeAt(ep) : null), token);
      _pickSubtitle(stream);
    } catch (e) {
      if (token != _token || !mounted) return;
      final msg = e is StreamException ? e.message : '$e';
      // A slow host often answers on the second try; only then show the error.
      if (!retried && !msg.contains('isn’t on the source')) {
        _play(ep, resume: resume, force: true, at: at, retried: true);
        return;
      }
      setState(() {
        _resolving = false;
        _playError = msg;
      });
    }
  }

  Duration? _resumeAt(int ep) {
    final h = Store.i.history().where((h) => h.media.id == widget.mediaId && h.episode == ep).firstOrNull;
    if (h != null && h.duration > 0 && h.position < h.duration - 30) {
      return Duration(milliseconds: (h.position * 1000).round());
    }
    return null;
  }

  /// A downloaded episode dressed as a stream: one variant, sidecar subtitles.
  ResolvedStream _offlineStream(DownloadJob job) => ResolvedStream(
        embedUrl: 'offline:${job.id}',
        master: 'file://${job.outputFile}',
        host: 'Downloaded',
        variants: [StreamVariant(label: job.resolution ?? 'Downloaded', height: 0, bandwidth: 0, url: 'file://${job.outputFile}')],
        subtitles: [
          for (final e in Downloader.sidecars(job.outputFile!).entries) SubtitleTrack(label: e.key, url: 'file://${e.value}'),
        ],
        resolvedAt: 0,
      );

  StreamVariant _pickVariant(ResolvedStream s) {
    final s0 = Store.i.settings;
    final max = s0.dataSaver ? 480 : s0.quality.maxHeight;
    // Never fails: when nothing is at or under the cap, the lowest variant plays.
    return s.pick(max) ?? (([...s.variants]..sort((a, b) => a.height.compareTo(b.height))).firstOrNull ?? s.variants.first);
  }

  Future<void> _open(ResolvedStream stream, StreamVariant variant, Duration? start, int token) async {
    final viewType = _surfaceView ? VideoViewType.platformView : VideoViewType.textureView;
    final vc = variant.url.startsWith('file://')
        ? VideoPlayerController.file(File(variant.url.substring(7)), viewType: viewType)
        : VideoPlayerController.networkUrl(
            Uri.parse(variant.url),
            formatHint: VideoFormat.hls,
            httpHeaders: StreamResolver.headersFor(stream),
            viewType: viewType,
          );
    try {
      await vc.initialize().timeout(const Duration(seconds: 30));
    } catch (e) {
      await vc.dispose();
      rethrow;
    }
    if (token != _token || !mounted) {
      await vc.dispose();
      return;
    }
    if (start != null && start > Duration.zero) await vc.seekTo(start);
    await vc.setPlaybackSpeed(_speed);
    vc.addListener(_tick);
    _wantPlay = true;
    await vc.play();
    _slowTimer?.cancel();
    setState(() {
      _vc = vc;
      _stream = stream;
      _variant = variant;
      _resolving = false;
      _slow = false;
    });
    _lastPos = vc.value.position;
    _lastMove = DateTime.now();
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _checkStall(token));
    _bumpControls();
    _addToList();
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveHistory());
    Native.armPip(Store.i.settings.autoPip, w: vc.value.size.width.round(), h: vc.value.size.height.round());
    _notify(true);
  }

  /// Watching a show puts it on the list as Watching, like the desktop app.
  void _addToList() {
    final m = _media;
    if (_addedToList || m == null) return;
    _addedToList = true;
    if (Store.i.libraryEntry(widget.mediaId) == null) {
      Store.i.setLibrary(Fmt.snapshotOfDetail(m, lang: Store.i.settings.titleLanguage), ListStatus.watching);
    }
  }

  /// Playing but the clock isn't moving: reopen once on a platform view
  /// (fixes black/frozen video on some phones), then say so.
  void _checkStall(int token) {
    final vc = _vc;
    if (vc == null || token != _token || !mounted) return;
    final v = vc.value;
    if (v.position != _lastPos || !_wantPlay || v.isCompleted || _pip && !v.isPlaying) {
      _lastPos = v.position;
      _lastMove = DateTime.now();
      return;
    }
    final still = DateTime.now().difference(_lastMove);
    if (still < const Duration(seconds: 14)) return;
    _lastMove = DateTime.now();
    _stalls++;
    if (_stalls == 1 && !_surfaceView) {
      _surfaceView = true;
      toast(context, 'Video stuck — switching the video output');
      _reopen();
    } else if (_stalls <= 2) {
      _reopen(force: true);
    } else {
      setState(() => _playError = 'Playback stalled. The host stopped sending video.');
    }
  }

  Future<void> _reopen({bool force = false}) async {
    final at = _vc?.value.position;
    if (force) {
      await _play(_ep, at: at, force: true);
      return;
    }
    final s = _stream;
    final v = _variant;
    if (s == null || v == null) return;
    final token = ++_token;
    final old = _vc;
    old?.removeListener(_tick);
    setState(() {
      _vc = null;
      _resolving = true;
    });
    await old?.dispose();
    try {
      await _open(s, v, at, token);
      if (_sub != null) _loadSubtitle(_sub, manual: false);
    } catch (e) {
      if (mounted) setState(() => _playError = '$e');
    }
  }

  Future<void> _switchVariant(StreamVariant v) async {
    if (v.url == _variant?.url) return;
    _variant = v;
    await _reopen();
  }

  void _pickSubtitle(ResolvedStream s) {
    if (s.subtitles.isEmpty) return;
    final want = Store.i.settings.subtitleLanguage.toLowerCase();
    if (want == 'off') return;
    final track = s.subtitles.where((t) => t.label.toLowerCase().startsWith(want)).firstOrNull ??
        s.subtitles.where((t) => t.isDefault).firstOrNull ??
        s.subtitles.first;
    _loadSubtitle(track, manual: false);
  }

  Future<void> _loadSubtitle(SubtitleTrack? track, {required bool manual}) async {
    setState(() {
      _sub = track;
      _cues = const [];
    });
    if (track == null) return;
    final token = _token;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final text = track.url.startsWith('file://')
            ? await File(track.url.substring(7)).readAsString()
            : await Net.i.getText(
                track.url,
                NetOptions(headers: _stream == null ? const {} : StreamResolver.headersFor(_stream!), timeout: const Duration(seconds: 12)),
              );
        final cues = _Cue.parseVtt(text);
        if (!mounted || token != _token || _sub != track) return;
        if (cues.isEmpty && attempt == 0) continue;
        setState(() => _cues = cues);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    // Only bother the viewer about a track they picked; an automatic pick
    // that fails just leaves subtitles off.
    if (mounted && manual && token == _token && _sub == track && _cues.isEmpty) toast(context, 'Couldn’t load ${track.label} subtitles');
  }

  void _saveHistory() {
    final vc = _vc;
    final media = _media;
    if (vc == null || media == null || !vc.value.isInitialized) return;
    final pos = vc.value.position.inMilliseconds / 1000;
    final dur = vc.value.duration.inMilliseconds / 1000;
    if (pos < 5 || dur <= 0) return;
    Store.i.saveHistory(HistoryEntry(
      media: Fmt.snapshotOfDetail(media, lang: Store.i.settings.titleLanguage),
      episode: _ep,
      episodeTitle: _current?.title,
      thumbnail: _current?.thumbnail,
      position: pos,
      duration: dur,
      audio: _audio,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  bool _wasPlaying = false;

  /// Runs on every player update: intro skip, watched mark, autoplay.
  void _tick() {
    final vc = _vc;
    if (vc == null || !mounted) return;
    final v = vc.value;
    if (v.hasError && _playError == null) {
      setState(() => _playError = v.errorDescription ?? 'Playback failed.');
      return;
    }
    if (!v.isInitialized || v.duration == Duration.zero) return;
    if (v.isPlaying != _wasPlaying) {
      _wasPlaying = v.isPlaying;
      _notify(v.isPlaying);
    }
    final t = v.position.inMilliseconds / 1000;
    final d = v.duration.inMilliseconds / 1000;

    final intro = _stream?.intro;
    if (Store.i.settings.autoSkipIntro && !_skippedIntro && intro != null && intro.contains(t) && intro.end - t > 2) {
      _skippedIntro = true;
      vc.seekTo(Duration(milliseconds: (intro.end * 1000).round()));
      toast(context, 'Skipped intro');
    }
    if (!_markedWatched && t / d >= 0.85) {
      _markedWatched = true;
      Store.i.setWatched(widget.mediaId, [_ep], true);
      final total = _media?.episodes;
      final m = _media;
      if (m != null && total != null && _ep >= total) {
        Store.i.setLibrary(Fmt.snapshotOfDetail(m, lang: Store.i.settings.titleLanguage), ListStatus.completed);
      }
    }
    // HLS often stops a second short of the reported duration, so finishing is
    // "completed" or "stopped within 1.5 s of the end".
    final ended = v.isCompleted || (t >= d - 1.5 && !v.isPlaying && _wantPlay);
    if (ended && _nextIn == null && _next != null && Store.i.settings.autoplayNext) {
      _wantPlay = false;
      _startCountdown();
    }
  }

  void _startCountdown() {
    setState(() => _nextIn = 5);
    _nextTimer?.cancel();
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      final n = (_nextIn ?? 0) - 1;
      if (n <= 0) {
        t.cancel();
        final next = _next;
        if (next != null) _play(next.number);
      } else {
        setState(() => _nextIn = n);
      }
    });
  }

  void _notify(bool playing) {
    if (_media == null) return;
    Native.nowPlaying(
      title: _title,
      text: _titleOf(_current) == null ? 'Episode $_ep' : 'E$_ep · ${_titleOf(_current)}',
      playing: playing,
      hasNext: _next != null,
    );
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  void _bumpControls() {
    _hideTimer?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_vc?.value.isPlaying ?? false)) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    if (_controls) {
      _hideTimer?.cancel();
      setState(() => _controls = false);
    } else {
      _bumpControls();
    }
  }

  void _togglePlay() {
    final vc = _vc;
    if (vc == null) return;
    if (vc.value.isPlaying) {
      _wantPlay = false;
      vc.pause();
      _saveHistory();
    } else {
      _wantPlay = true;
      if (vc.value.isCompleted) vc.seekTo(Duration.zero);
      vc.play();
    }
    _bumpControls();
    setState(() {});
  }

  void _seekBy(int seconds) {
    final vc = _vc;
    if (vc == null) return;
    final to = vc.value.position + Duration(seconds: seconds);
    vc.seekTo(to < Duration.zero ? Duration.zero : (to > vc.value.duration ? vc.value.duration : to));
  }

  void _doubleTap(double width) {
    if (_locked || _tapAt == null) return;
    final x = _tapAt!.dx / width;
    if (x > 0.38 && x < 0.62) {
      _togglePlay();
      return;
    }
    final side = x < 0.5 ? -1 : 1;
    HapticFeedback.lightImpact();
    _seekBy(_step * side);
    _flashTimer?.cancel();
    setState(() {
      _flashSeconds = _flashSide == side ? _flashSeconds + _step : _step;
      _flashSide = side;
    });
    _flashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _flashSide = 0);
    });
  }

  Future<void> _vStart(DragStartDetails d, double width) async {
    if (_locked || !Store.i.settings.swipeGestures) return;
    final left = d.localPosition.dx < width / 2;
    _vStartY = d.localPosition.dy;
    _hud = left ? 'brightness' : 'volume';
    _vStartValue = left ? await Native.brightness() : await Native.volume();
    _hudValue = _vStartValue;
  }

  void _vUpdate(DragUpdateDetails d, double height) {
    if (_vStartY == null || _hud == null) return;
    final delta = (_vStartY! - d.localPosition.dy) / (height * 0.8);
    final v = (_vStartValue + delta).clamp(0.0, 1.0);
    _hudTimer?.cancel();
    setState(() => _hudValue = v);
    if (_hud == 'brightness') {
      Native.setBrightness(v);
    } else {
      Native.setVolume(v);
    }
  }

  void _vEnd() {
    _vStartY = null;
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _hud = null);
    });
  }

  Future<void> _setFull(bool full) async {
    setState(() => _full = full);
    if (full) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    }
    _bumpControls();
  }

  void _setAudio(Audio a) {
    if (a == _audio) return;
    final at = _vc?.value.position;
    setState(() => _audio = a);
    _play(_ep, at: at);
  }

  void _setEmbed(bool on) {
    Store.i.patchSettings((s) => s.copyWith(player: on ? PlayerMode.embed : PlayerMode.direct));
    final at = _vc?.value.position;
    setState(() {
      _embed = on;
      _playError = null;
      _embedError = null;
    });
    _play(_ep, at: at, resume: at == null);
  }

  Future<void> _download([List<Episode>? targets]) async {
    final m = _media;
    final eps = _eps;
    if (m == null || eps == null) return;
    if (_full) await _setFull(false);
    if (!mounted) return;
    await showEpisodeDownload(
      context,
      media: Fmt.snapshotOfDetail(m, lang: Store.i.settings.titleLanguage),
      eps: eps,
      targets: targets ?? [if (_current != null) _current!],
      minutes: m.duration,
    );
  }

  // ── Sheets ────────────────────────────────────────────────────────────────

  Widget _row(String label, String value, String icon, VoidCallback onTap) => Pressable(
        onTap: onTap,
        scale: 0.98,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(children: [
            PzIcon(icon, size: 20, color: Paper.paper2),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: body(15))),
            Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(14, color: Paper.paper3))),
            const SizedBox(width: 6),
            const PzIcon('chevronRight', size: 16, color: Paper.paper3),
          ]),
        ),
      );

  void _openSettings() {
    _hideTimer?.cancel();
    final s = _stream;
    final variants = s == null ? const <StreamVariant>[] : ([...s.variants]..sort((a, b) => b.height.compareTo(a.height)));
    pzSheet<void>(context, title: 'Playback', builder: (c) {
      void sub(String title, Widget Function(BuildContext) b) {
        Navigator.pop(c);
        pzSheet<void>(context, title: title, builder: b).whenComplete(_bumpControls);
      }

      return ListView(shrinkWrap: true, physics: const ClampingScrollPhysics(), children: [
        if (!_embed)
          _row('Quality', _variant == null ? 'Auto' : (variants.length <= 1 ? '${_variant!.label} · only one' : _variant!.label), 'layers', () {
            sub('Quality', (c2) => ListView(shrinkWrap: true, children: [
                  for (final v in variants)
                    SheetOption(v.label, selected: v.url == _variant?.url, onTap: () {
                      Navigator.pop(c2);
                      _switchVariant(v);
                    }),
                  if (variants.length <= 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                      child: Text(
                        'The source only sends ${_variant?.label ?? 'one quality'} for this episode, so there is nothing smaller to switch to. '
                        'New releases often start this way; lower qualities usually appear within a few days.',
                        style: body(12.5, color: Paper.paper3, height: 1.45),
                      ),
                    ),
                ]));
          }),
        if (!_embed)
          _row('Subtitles', _sub?.label ?? 'Off', 'subtitles', () {
            sub('Subtitles', (c2) => ListView(shrinkWrap: true, children: [
                  SheetOption('Off', selected: _sub == null, onTap: () {
                    Navigator.pop(c2);
                    _loadSubtitle(null, manual: true);
                  }),
                  for (final t in _stream?.subtitles ?? const <SubtitleTrack>[])
                    SheetOption(t.label, selected: t.url == _sub?.url, onTap: () {
                      Navigator.pop(c2);
                      _loadSubtitle(t, manual: true);
                    }),
                ]));
          }),
        if (!_embed)
          _row('Subtitle style', '${(_subStyle.size * 100).round()}%', 'eye', () {
            sub('Subtitle style', (c2) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: SubtitleStyleEditor(onChanged: () {
                    if (mounted) setState(() => _subStyle = SubStyle.of(Store.i.settings));
                  }),
                ));
          }),
        if (_eps?.hasDub == true)
          _row('Audio', _audio == Audio.dub ? 'English dub' : 'Japanese (sub)', 'volume', () {
            sub('Audio', (c2) => ListView(shrinkWrap: true, children: [
                  SheetOption('Japanese with subtitles', selected: _audio == Audio.sub, onTap: () {
                    Navigator.pop(c2);
                    _setAudio(Audio.sub);
                  }),
                  SheetOption('English dub', selected: _audio == Audio.dub, onTap: () {
                    Navigator.pop(c2);
                    _setAudio(Audio.dub);
                  }),
                ]));
          }),
        if (!_embed)
          _row('Speed', _speed == 1 ? 'Normal' : '$_speed×', 'speed', () {
            sub('Speed', (c2) => ListView(shrinkWrap: true, children: [
                  for (final sp in const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
                    SheetOption(sp == 1 ? 'Normal' : '$sp×', selected: sp == _speed, onTap: () {
                      Navigator.pop(c2);
                      setState(() => _speed = sp);
                      _vc?.setPlaybackSpeed(sp);
                    }),
                ]));
          }),
        if (!_embed)
          _row('Picture', switch (_fit) { _Fit.fit => 'Fit', _Fit.fill => 'Stretch', _Fit.zoom => 'Zoom to fill' }, 'fullscreen', () {
            sub('Picture', (c2) => ListView(shrinkWrap: true, children: [
                  for (final (f, l) in const [(_Fit.fit, 'Fit'), (_Fit.zoom, 'Zoom to fill'), (_Fit.fill, 'Stretch')])
                    SheetOption(l, selected: _fit == f, onTap: () {
                      Navigator.pop(c2);
                      setState(() => _fit = f);
                    }),
                ]));
          }),
        _row('Player', _embed ? 'Source player' : 'PlayzAnime', 'tv', () {
          sub('Player', (c2) => ListView(shrinkWrap: true, children: [
                SheetOption('PlayzAnime player', selected: !_embed, onTap: () {
                  Navigator.pop(c2);
                  _setEmbed(false);
                }),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Gestures, quality, subtitle style, picture-in-picture, downloads.', style: body(12, color: Paper.paper3)),
                ),
                SheetOption('Source player', selected: _embed, onTap: () {
                  Navigator.pop(c2);
                  _setEmbed(true);
                }),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text('The host’s own web player. Use it when an episode won’t start here.', style: body(12, color: Paper.paper3)),
                ),
              ]));
        }),
        if (_media != null && _eps != null)
          _row('Download', Downloader.i.episodeFile(widget.mediaId, _ep) != null ? 'Saved' : 'This episode', 'downloads', () {
            Navigator.pop(c);
            _download();
          }),
        const SizedBox(height: 12),
      ]);
    }).whenComplete(_bumpControls);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_pip) {
      final vc = _vc;
      return Scaffold(
        backgroundColor: Colors.black,
        body: vc == null
            ? const SizedBox.expand()
            : Stack(fit: StackFit.expand, children: [_video(vc), if (_cues.isNotEmpty) _subtitles(vc, false)]),
      );
    }
    final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final full = _full || landscape;
    return PopScope(
      canPop: !_full,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _full) _setFull(false);
      },
      child: Scaffold(
        backgroundColor: full ? Colors.black : Ink.ink0,
        body: _loadError != null
            ? SafeArea(
                child: Column(children: [
                  _BackBar(onBack: () => Navigator.pop(context)),
                  Expanded(
                    child: Center(
                      child: StatePanel(title: 'Couldn’t load this show', message: _loadError, icon: 'alert', action: 'Try again', onAction: _load),
                    ),
                  ),
                ]),
              )
            : full
                ? _player(full: true)
                : Column(children: [
                    Container(color: Colors.black, height: MediaQuery.of(context).padding.top),
                    AspectRatio(aspectRatio: 16 / 9, child: _player(full: false)),
                    Expanded(child: _details()),
                  ]),
      ),
    );
  }

  Widget _player({required bool full}) {
    return LayoutBuilder(builder: (context, box) {
      final vc = _vc;
      final gestures = !_embed && vc != null;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _embed ? null : _toggleControls,
        onDoubleTapDown: (d) => _tapAt = d.localPosition,
        onDoubleTap: gestures ? () => _doubleTap(box.maxWidth) : null,
        onLongPressStart: !gestures || _locked
            ? null
            : (_) {
                HapticFeedback.mediumImpact();
                setState(() => _boost = true);
                vc.setPlaybackSpeed(2);
              },
        onLongPressEnd: !gestures
            ? null
            : (_) {
                setState(() => _boost = false);
                vc.setPlaybackSpeed(_speed);
              },
        onVerticalDragStart: gestures && full ? (d) => _vStart(d, box.maxWidth) : null,
        onVerticalDragUpdate: gestures && full ? (d) => _vUpdate(d, box.maxHeight) : null,
        onVerticalDragEnd: gestures && full ? (_) => _vEnd() : null,
        onHorizontalDragStart: !gestures || _locked
            ? null
            : (d) {
                _dragStartX = d.localPosition.dx;
                _dragFrom = vc.value.position;
              },
        onHorizontalDragUpdate: !gestures || _locked || _dragStartX == null
            ? null
            : (d) {
                final dx = d.localPosition.dx - _dragStartX!;
                final secs = dx / box.maxWidth * 120;
                var to = _dragFrom! + Duration(milliseconds: (secs * 1000).round());
                if (to < Duration.zero) to = Duration.zero;
                if (to > vc.value.duration) to = vc.value.duration;
                setState(() => _dragTo = to);
              },
        onHorizontalDragEnd: !gestures
            ? null
            : (_) {
                if (_dragTo != null) vc.seekTo(_dragTo!);
                setState(() {
                  _dragTo = null;
                  _dragStartX = null;
                });
              },
        child: ColoredBox(
          color: Colors.black,
          child: Stack(fit: StackFit.expand, children: [
            if (_embed && _current != null)
              _EmbedPlayer(
                url: _current!.urlFor(_audio) ?? '',
                onMissing: () {
                  if (mounted) setState(() => _embedError = 'The source player has no copy of this episode.');
                },
              )
            else if (vc != null)
              _video(vc)
            else if (_media?.bannerImage != null || _current?.thumbnail != null)
              Opacity(opacity: 0.35, child: PzImage(url: _current?.thumbnail ?? _media!.bannerImage!)),
            if (gestures && _cues.isNotEmpty) _subtitles(vc, full),
            if (_resolving) _resolvingOverlay(),
            if (_playError == 'unavailable') _unavailableOverlay() else if (_playError != null) _errorOverlay(),
            if (_embed && _embedError != null) _embedErrorOverlay(),
            if (gestures) ...[
              _flash(),
              if (_boost) const Positioned(top: 16, left: 0, right: 0, child: Center(child: Tag('2× speed', icon: 'speed'))),
              if (_dragTo != null) Center(child: _dragLabel(vc)),
              if (_hud != null) _hudLayer(),
              _controlsLayer(vc, full),
              _skipPill(vc, full),
              if (_nextIn != null) _countdown(),
            ],
            if (_embed) _embedBar(full),
          ]),
        ),
      );
    });
  }

  Widget _video(VideoPlayerController vc) {
    final size = vc.value.size;
    final fit = switch (_fit) { _Fit.fit => BoxFit.contain, _Fit.fill => BoxFit.fill, _Fit.zoom => BoxFit.cover };
    return ClipRect(
      child: FittedBox(
        fit: fit,
        child: SizedBox(
          width: size.width == 0 ? 16 : size.width,
          height: size.height == 0 ? 9 : size.height,
          child: VideoPlayer(vc),
        ),
      ),
    );
  }

  Widget _subtitles(VideoPlayerController vc, bool full) => ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: vc,
        builder: (_, v, __) {
          final t = v.position.inMilliseconds / 1000;
          final cue = _cues.where((c) => t >= c.start && t <= c.end).map((c) => c.text).join('\n');
          if (cue.isEmpty) return const SizedBox.shrink();
          final base = _controls && !_pip ? (full ? 92.0 : 56.0) : (full ? 32.0 : 14.0);
          return Positioned(
            left: 24,
            right: 24,
            bottom: base + _subStyle.lift * (full ? 120 : 50),
            child: Center(child: _subStyle.render(cue, full: full && !_pip)),
          );
        },
      );

  Widget _resolvingOverlay() => Center(
        child: FadeIn(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2.5, color: accentOf(context))),
            const SizedBox(height: 12),
            Text(_stream == null ? 'Finding the stream…' : 'Loading…', style: body(13, color: Paper.paper2)),
            if (_slow) ...[
              const SizedBox(height: 6),
              Text('This host is slow today. Still trying.', style: body(12, color: Paper.paper3)),
              const SizedBox(height: 10),
              PzBtn('Use source player', icon: 'tv', compact: true, onTap: () => _setEmbed(true)),
            ],
          ]),
        ),
      );

  Widget _unavailableOverlay() => Container(
        color: Colors.black.withAlpha(0xD9),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const PzIcon('clock', size: 26, color: Paper.paper2),
              const SizedBox(height: 8),
              Text('Not on the source yet', style: body(15, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('PlayzAnime’s source doesn’t carry this title. Niche and Chinese releases are often added late.',
                  textAlign: TextAlign.center, style: body(12, color: Paper.paper3)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                PzBtn('Check again', icon: 'refresh', compact: true, primary: true, onTap: () => _load(force: true)),
                PzBtn('Back', compact: true, onTap: () => Navigator.pop(context)),
              ]),
            ]),
          ),
        ),
      );

  Widget _errorOverlay() {
    final hasOther = (_audio == Audio.sub ? _current?.dubUrl : _current?.subUrl) != null;
    return Container(
      color: Colors.black.withAlpha(0xCC),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const PzIcon('alert', size: 26, color: Paper.paper2),
            const SizedBox(height: 8),
            Text('Couldn’t play episode $_ep', style: body(15, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_playError!, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: body(12, color: Paper.paper3)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              PzBtn('Retry', icon: 'refresh', compact: true, primary: true, onTap: () {
                _stalls = 0;
                _play(_ep, force: true, resume: true);
              }),
              if (hasOther) PzBtn(_audio == Audio.sub ? 'Try dub' : 'Try sub', compact: true, onTap: () => _setAudio(_audio == Audio.sub ? Audio.dub : Audio.sub)),
              PzBtn('Source player', icon: 'tv', compact: true, onTap: () => _setEmbed(true)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _embedErrorOverlay() => Container(
        color: Colors.black.withAlpha(0xE6),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const PzIcon('alert', size: 26, color: Paper.paper2),
            const SizedBox(height: 8),
            Text(_embedError!, textAlign: TextAlign.center, style: body(14, weight: FontWeight.w700)),
            const SizedBox(height: 12),
            PzBtn('Back to PlayzAnime player', icon: 'play', compact: true, primary: true, onTap: () => _setEmbed(false)),
          ]),
        ),
      );

  /// In source-player mode there are no PlayzAnime controls, so keep a way back.
  Widget _embedBar(bool full) => Positioned(
        top: full ? 10 : 6,
        left: 8,
        right: 8,
        child: Row(children: [
          RoundIcon('arrowLeft', size: 36, iconSize: 18, onTap: () => full && _full ? _setFull(false) : Navigator.pop(context)),
          const Spacer(),
          Pressable(
            onTap: () => _setEmbed(false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.black.withAlpha(0xB3), borderRadius: BorderRadius.circular(18), border: Border.all(color: Lines.line2)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                PzIcon('play', size: 14, color: accentOf(context)),
                const SizedBox(width: 6),
                Text('PlayzAnime player', style: body(12.5, weight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          RoundIcon(full ? 'fullscreenExit' : 'fullscreen', size: 36, iconSize: 18, onTap: () => _setFull(!_full)),
        ]),
      );

  Widget _flash() => IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _flashSide == 0 ? 0 : 1,
          child: Align(
            alignment: _flashSide < 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.36,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(0x1A),
                  borderRadius: _flashSide < 0
                      ? const BorderRadius.horizontal(right: Radius.circular(999))
                      : const BorderRadius.horizontal(left: Radius.circular(999)),
                ),
                alignment: Alignment.center,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  PzIcon(_flashSide < 0 ? 'back5' : 'fwd5', size: 26, color: Colors.white),
                  const SizedBox(height: 4),
                  Text('${_flashSide < 0 ? '−' : '+'}${_flashSeconds}s', style: body(13, weight: FontWeight.w700, color: Colors.white)),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _hudLayer() => IgnorePointer(
        child: Center(
          child: Container(
            width: 170,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: Colors.black.withAlpha(0xB3), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              PzIcon(_hud == 'brightness' ? 'sun' : (_hudValue == 0 ? 'mute' : 'volume'), size: 18, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: _hudValue, minHeight: 5, backgroundColor: Colors.white24, color: accentOf(context)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 30, child: Text('${(_hudValue * 100).round()}', textAlign: TextAlign.right, style: body(12, color: Colors.white))),
            ]),
          ),
        ),
      );

  Widget _dragLabel(VideoPlayerController vc) {
    final diff = (_dragTo! - _dragFrom!).inSeconds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: Colors.black.withAlpha(0xB3), borderRadius: BorderRadius.circular(8)),
      child: Text(
        '${diff >= 0 ? '+' : '−'}${Fmt.clock(diff.abs())}  ·  ${Fmt.clock(_dragTo!.inSeconds)} / ${Fmt.clock(vc.value.duration.inSeconds)}',
        style: body(15, weight: FontWeight.w700, color: Colors.white),
      ),
    );
  }

  Widget _controlsLayer(VideoPlayerController vc, bool full) {
    final pad = full ? 24.0 : 10.0;
    if (_locked) {
      return AnimatedOpacity(
        duration: kMed,
        opacity: _controls ? 1 : 0,
        child: IgnorePointer(
          ignoring: !_controls,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: pad),
              child: RoundIcon('lock', onTap: () {
                setState(() => _locked = false);
                _bumpControls();
              }),
            ),
          ),
        ),
      );
    }
    final seek = full ? 46.0 : 40.0;
    final play = full ? 62.0 : 52.0;
    return AnimatedOpacity(
      duration: kMed,
      curve: kEase,
      opacity: _controls ? 1 : 0,
      child: IgnorePointer(
        ignoring: !_controls,
        child: Stack(fit: StackFit.expand, children: [
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xB3000000), Color(0x22000000), Color(0x22000000), Color(0xCC000000)],
                  stops: [0, 0.3, 0.6, 1],
                ),
              ),
            ),
          ),
          // Top bar.
          Positioned(
            top: full ? 12 : 4,
            left: pad - 6,
            right: pad - 6,
            child: Row(children: [
              RoundIcon('arrowLeft', filled: false, onTap: () => full && _full ? _setFull(false) : Navigator.pop(context)),
              const SizedBox(width: 4),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(full ? 16 : 13.5, weight: FontWeight.w700, color: Colors.white)),
                  Text(_titleOf(_current) == null ? 'Episode $_ep' : 'E$_ep · ${_titleOf(_current)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: body(11.5, color: Paper.paper2)),
                ]),
              ),
              if (_pipOk) RoundIcon('pip', filled: false, iconSize: 18, onTap: () => Native.enterPip()),
              RoundIcon('lock', filled: false, iconSize: 18, onTap: () {
                setState(() => _locked = true);
                toast(context, 'Screen locked · tap the lock to unlock');
              }),
              RoundIcon('settings', filled: false, onTap: _openSettings),
            ]),
          ),
          // Centre transport.
          Center(
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: vc,
              builder: (_, v, __) => Row(mainAxisSize: MainAxisSize.min, children: [
                RoundIcon(_step == 5 ? 'back5' : 'back10', size: seek, iconSize: full ? 21 : 19, onTap: () {
                  _seekBy(-_step);
                  _bumpControls();
                }),
                SizedBox(width: full ? 44 : 28),
                v.isBuffering && _wantPlay && !v.isPlaying
                    ? SizedBox(
                        width: play,
                        height: play,
                        child: Padding(padding: const EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2.5, color: accentOf(context))),
                      )
                    : Pressable(
                        onTap: _togglePlay,
                        scale: 0.86,
                        child: Container(
                          width: play,
                          height: play,
                          decoration: BoxDecoration(color: accentOf(context), shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: AnimatedSwitcher(
                            duration: kFast,
                            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                            child: PzIcon(v.isPlaying ? 'pause' : 'play', key: ValueKey(v.isPlaying), size: full ? 26 : 22, color: Seal.accentInk),
                          ),
                        ),
                      ),
                SizedBox(width: full ? 44 : 28),
                RoundIcon(_step == 5 ? 'fwd5' : 'fwd10', size: seek, iconSize: full ? 21 : 19, onTap: () {
                  _seekBy(_step);
                  _bumpControls();
                }),
              ]),
            ),
          ),
          // Bottom bar.
          Positioned(
            left: pad,
            right: pad,
            bottom: full ? 14 : 2,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: vc,
              builder: (_, v, __) => Row(children: [
                Text(Fmt.clock(v.position.inSeconds), style: body(11.5, weight: FontWeight.w600, color: Colors.white)),
                const SizedBox(width: 8),
                Expanded(child: _Scrubber(vc: vc, onSeekStart: () => _hideTimer?.cancel(), onSeekEnd: _bumpControls)),
                const SizedBox(width: 8),
                Text(Fmt.clock(v.duration.inSeconds), style: body(11.5, weight: FontWeight.w600, color: Paper.paper2)),
                if (_next != null) RoundIcon('next', filled: false, size: 38, iconSize: 18, onTap: () => _play(_next!.number)),
                RoundIcon(full ? 'fullscreenExit' : 'fullscreen', filled: false, size: 38, iconSize: 18, onTap: () => _setFull(!_full)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _skipPill(VideoPlayerController vc, bool full) => ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: vc,
        builder: (_, v, __) {
          final t = v.position.inMilliseconds / 1000;
          final intro = _stream?.intro;
          final outro = _stream?.outro;
          String? label;
          VoidCallback? go;
          if (intro != null && intro.contains(t) && intro.end - t > 2) {
            label = 'Skip intro';
            go = () => vc.seekTo(Duration(milliseconds: (intro.end * 1000).round()));
          } else if (outro != null && outro.contains(t) && _next != null) {
            label = 'Next episode';
            go = () => _play(_next!.number);
          }
          return Positioned(
            right: full ? 28 : 12,
            bottom: full ? 70 : 44,
            child: AnimatedSwitcher(
              duration: kMed,
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: c)),
              child: label == null
                  ? const SizedBox.shrink()
                  : Pressable(
                      key: ValueKey(label),
                      onTap: go,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(color: Paper.paper, borderRadius: BorderRadius.circular(7)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const PzIcon('skip', size: 16, color: Ink.ink0),
                          const SizedBox(width: 6),
                          Text(label, style: body(13, weight: FontWeight.w800, color: Ink.ink0)),
                        ]),
                      ),
                    ),
            ),
          );
        },
      );

  Widget _countdown() => Container(
        color: Colors.black.withAlpha(0xB3),
        alignment: Alignment.center,
        child: FadeIn(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Up next', style: body(12, color: Paper.paper3, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('E${_next?.number}${_titleOf(_next) == null ? '' : ' · ${_titleOf(_next)}'}',
                textAlign: TextAlign.center, maxLines: 2, style: body(16, weight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 4),
            Text('Starting in $_nextIn', style: body(13, color: Paper.paper2)),
            const SizedBox(height: 12),
            Row(mainAxisSize: MainAxisSize.min, children: [
              PzBtn('Cancel', compact: true, onTap: () {
                _nextTimer?.cancel();
                setState(() => _nextIn = null);
              }),
              const SizedBox(width: 8),
              PzBtn('Play now', icon: 'play', compact: true, primary: true, onTap: () => _play(_next!.number)),
            ]),
          ]),
        ),
      );

  // ── Details panel (portrait) ──────────────────────────────────────────────

  final Set<int> _picked = {};

  Widget _details() {
    final media = _media;
    final eps = _eps;
    if (media == null || eps == null) {
      return const Padding(
        padding: EdgeInsets.all(kGutter),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Skeleton(height: 26, width: 240),
          SizedBox(height: 10),
          Skeleton(height: 14, width: 160),
          SizedBox(height: 24),
          Skeleton(height: 64),
          SizedBox(height: 10),
          Skeleton(height: 64),
        ]),
      );
    }
    final watched = Store.i.watched(widget.mediaId).toSet();
    final list = eps.episodes;
    final picking = _picked.isNotEmpty;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: FadeIn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_title, style: display(30)),
                const SizedBox(height: 8),
                Text('Episode $_ep${_titleOf(_current) != null ? ' · ${_titleOf(_current)}' : ''}',
                    style: body(14, color: Paper.paper2, weight: FontWeight.w600)),
                const SizedBox(height: 14),
                Row(children: [
                  if (eps.hasDub)
                    Segmented<Audio>(
                      value: _audio,
                      options: const [(Audio.sub, 'Sub'), (Audio.dub, 'Dub')],
                      onChanged: _setAudio,
                    ),
                  const Spacer(),
                  RoundIcon('downloads', onTap: () => _download()),
                  const SizedBox(width: 8),
                  RoundIcon('prev', onTap: _prev == null ? null : () => _play(_prev!.number)),
                  const SizedBox(width: 8),
                  RoundIcon('next', onTap: _next == null ? null : () => _play(_next!.number)),
                ]),
              ]),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SectionHeader(
            picking ? '${_picked.length} selected' : 'Episodes',
            subtitle: picking ? 'Tap to add or remove' : '${list.length} total · hold one to select several',
            action: picking ? 'Download' : null,
            onAction: picking
                ? () {
                    final targets = list.where((e) => _picked.contains(e.number)).toList();
                    setState(() => _picked.clear());
                    _download(targets);
                  }
                : null,
          ),
        ),
        SliverList.builder(
          itemCount: list.length,
          itemBuilder: (c, i) {
            final e = list[i];
            final current = e.number == _ep;
            final picked = _picked.contains(e.number);
            final saved = Downloader.i.episodeFile(widget.mediaId, e.number) != null;
            return Pressable(
              onTap: picking
                  ? () => setState(() => picked ? _picked.remove(e.number) : _picked.add(e.number))
                  : (current ? null : () => _play(e.number, resume: true)),
              onLongPress: () {
                HapticFeedback.selectionClick();
                setState(() => _picked.add(e.number));
              },
              scale: 0.98,
              child: AnimatedContainer(
                duration: kMed,
                margin: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: current || picked ? Ink.ink2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: picked || current ? accentOf(context) : Lines.line),
                ),
                child: Row(children: [
                  SizedBox(
                    width: 112,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(fit: StackFit.expand, children: [
                        EpisodeThumb(episode: e, media: media),
                        if (current)
                          Container(
                            decoration: BoxDecoration(color: Colors.black.withAlpha(0x80), borderRadius: BorderRadius.circular(6)),
                            alignment: Alignment.center,
                            child: PzIcon('play', size: 20, color: accentOf(context)),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('E${e.number}', style: body(11.5, color: current ? accentOf(context) : Paper.paper3, weight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(_titleOf(e) ?? 'Episode ${e.number}', maxLines: 2, overflow: TextOverflow.ellipsis, style: body(13.5, weight: FontWeight.w600, height: 1.25)),
                    ]),
                  ),
                  if (picking)
                    PzIcon(picked ? 'check' : 'plus', size: 16, color: picked ? accentOf(context) : Paper.paper3)
                  else if (saved)
                    const PzIcon('downloads', size: 15, color: Paper.paper3)
                  else if (watched.contains(e.number))
                    const PzIcon('check', size: 16, color: Paper.paper3),
                ]),
              ),
            );
          },
        ),
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.bottom + 24)),
      ],
    );
  }
}

/// An episode still, or the show's banner with the number on it when the
/// source has no still yet (new releases, donghua).
class EpisodeThumb extends StatelessWidget {
  const EpisodeThumb({super.key, required this.episode, required this.media});

  final Episode episode;
  final MediaDetail media;

  @override
  Widget build(BuildContext context) {
    final still = episode.thumbnail;
    if (still != null) return PzImage(url: still, radius: BorderRadius.circular(6));
    final art = media.bannerImage ?? media.coverImage?.large;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(fit: StackFit.expand, children: [
        if (art != null) Opacity(opacity: 0.45, child: PzImage(url: art, alignment: Alignment((episode.number % 5 - 2) / 2, 0))),
        Container(color: Ink.ink3.withAlpha(art == null ? 0xFF : 0x55)),
        Center(child: Text('${episode.number}', style: display(26, color: Paper.paper))),
      ]),
    );
  }
}

class _BackBar extends StatelessWidget {
  const _BackBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Align(alignment: Alignment.centerLeft, child: RoundIcon('arrowLeft', onTap: onBack)),
      );
}

/// Seek bar with buffered range, a growing thumb while dragging.
class _Scrubber extends StatefulWidget {
  const _Scrubber({required this.vc, required this.onSeekStart, required this.onSeekEnd});

  final VideoPlayerController vc;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = widget.vc.value;
    final total = v.duration.inMilliseconds.toDouble();
    final pos = total == 0 ? 0.0 : v.position.inMilliseconds / total;
    final buffered = total == 0 || v.buffered.isEmpty ? 0.0 : v.buffered.last.end.inMilliseconds / total;
    final value = (_drag ?? pos).clamp(0.0, 1.0);
    final accent = accentOf(context);
    return LayoutBuilder(builder: (context, box) {
      void at(double dx) => setState(() => _drag = (dx / box.maxWidth).clamp(0.0, 1.0));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) {
          widget.onSeekStart();
          at(d.localPosition.dx);
        },
        onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
        onHorizontalDragEnd: (_) {
          if (_drag != null) widget.vc.seekTo(Duration(milliseconds: (_drag! * total).round()));
          setState(() => _drag = null);
          widget.onSeekEnd();
        },
        onTapUp: (d) {
          widget.vc.seekTo(Duration(milliseconds: ((d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0) * total).round()));
          widget.onSeekEnd();
        },
        child: SizedBox(
          height: 32,
          child: Stack(alignment: Alignment.centerLeft, children: [
            Container(height: 3, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            FractionallySizedBox(
              widthFactor: buffered.clamp(0.0, 1.0),
              child: Container(height: 3, decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2))),
            ),
            FractionallySizedBox(
              widthFactor: value,
              child: Container(height: 3, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
            ),
            Positioned(
              left: (value * box.maxWidth - (_drag != null ? 8 : 6)).clamp(0.0, box.maxWidth - 12),
              child: AnimatedContainer(
                duration: kFast,
                width: _drag != null ? 16 : 12,
                height: _drag != null ? 16 : 12,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

/// The source's own player in a WebView: the desktop `EmbedPlayer.tsx`.
class _EmbedPlayer extends StatelessWidget {
  const _EmbedPlayer({required this.url, required this.onMissing});

  final String url;
  final VoidCallback onMissing;

  @override
  Widget build(BuildContext context) {
    final origin = Uri.tryParse(url)?.origin ?? '';
    return InAppWebView(
      key: ValueKey(url),
      initialUrlRequest: URLRequest(url: WebUri(url), headers: {'Referer': '$origin/'}),
      initialSettings: InAppWebViewSettings(
        userAgent: kChromeUa,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        supportMultipleWindows: false,
        javaScriptCanOpenWindowsAutomatically: false,
        transparentBackground: true,
      ),
      // Ads try to navigate the frame away; only the embed's own host may load.
      shouldOverrideUrlLoading: (c, action) async {
        final host = action.request.url?.host ?? '';
        return host.isEmpty || host == Uri.parse(url).host ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL;
      },
      onCreateWindow: (c, a) async => false,
      onReceivedHttpError: (c, req, res) {
        if (req.isForMainFrame == true && (res.statusCode ?? 200) >= 400) onMissing();
      },
      onTitleChanged: (c, title) {
        if (RegExp(r'^\s*(error|404|not found)\b', caseSensitive: false).hasMatch(title ?? '')) onMissing();
      },
    );
  }
}

/// One WebVTT cue.
class _Cue {
  const _Cue(this.start, this.end, this.text);

  final double start;
  final double end;
  final String text;

  static double _time(String s) {
    final parts = s.trim().split(':');
    var secs = 0.0;
    for (final p in parts) {
      secs = secs * 60 + (double.tryParse(p.replaceAll(',', '.')) ?? 0);
    }
    return secs;
  }

  static List<_Cue> parseVtt(String text) {
    final out = <_Cue>[];
    final blocks = text.replaceAll('\r', '').split(RegExp(r'\n\s*\n'));
    for (final b in blocks) {
      final lines = b.split('\n');
      final i = lines.indexWhere((l) => l.contains('-->'));
      if (i < 0) continue;
      final times = lines[i].split('-->');
      final end = times[1].trim().split(RegExp(r'\s+')).first;
      final body = lines
          .skip(i + 1)
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&nbsp;', ' ')
          .trim();
      if (body.isEmpty) continue;
      out.add(_Cue(_time(times[0]), _time(end), body));
    }
    return out;
  }
}
