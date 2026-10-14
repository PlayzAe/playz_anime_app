import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

import '../models/local.dart';
import '../models/manga.dart';
import '../models/media.dart';
import '../models/stream.dart';
import '../sources/manga/extensions.dart';
import '../sources/manga/providers.dart';
import 'connectivity.dart';
import 'files_io.dart';
import 'log.dart';
import 'native.dart';
import 'net.dart';
import 'store.dart';
import 'stream_resolver.dart';

/// Download queue for episodes (HLS → one `.ts` file + `.vtt` sidecars) and
/// chapters (pages → `.cbz`). Port of desktop `src/main/downloader.ts`.
///
/// No ffmpeg on the phone: MPEG-TS segments concatenate into a file ExoPlayer
/// plays directly, and AES-128 segments are decrypted as they arrive.
/// Segments are kept as part files until the job finishes, so pause and
/// resume (or an app restart) only fetch what is missing.
class Downloader extends ChangeNotifier {
  Downloader._();

  static final Downloader i = Downloader._();

  final _log = Log('download');
  final _cancel = <String, CancelToken>{};
  List<DownloadJob> _jobs = [];
  Timer? _persist;

  /// Automatic retries per job (network blips, expired stream tokens).
  final Map<String, int> _attempts = {};
  final Map<String, Timer> _retryTimers = {};
  Timer? _notifyTimer;
  bool _hadActive = false;
  int _finishedThisRun = 0;

  static const _maxJobs = 2;
  static const _segmentWorkers = 4;

  /// Separator for the subtitle labels a job keeps (stored in `subtitleLabel`).
  static const subSep = '|';

  List<DownloadJob> get jobs => List.unmodifiable(_jobs);

  void init() {
    _jobs = [
      for (final j in Store.i.downloadRecords())
        // An app kill mid-download leaves a running state behind; part files survive, so requeue.
        j.state.isRunning ? j.copyWith(state: DownloadState.queued, stage: 'Waiting') : j,
    ];
    // Drop finished records whose file the user deleted outside the app.
    _jobs.removeWhere((j) => j.state == DownloadState.done && j.outputFile != null && !File(j.outputFile!).existsSync());
    // Coming back online (or onto wifi) restarts the queue on its own.
    NetWatch.i.addListener(_pump);
    _pump();
  }

  // ── Folder ────────────────────────────────────────────────────────────────

  static Future<String> defaultFolder() async {
    if (Platform.isAndroid) return '/storage/emulated/0/Download/PlayzAnime';
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}${Platform.pathSeparator}PlayzAnime';
  }

  String? _resolvedDefault;

  /// The chosen folder, else `Download/PlayzAnime`. Android 7–10 can't write
  /// there without a storage permission, so those fall back to the app's own
  /// external folder (no permission needed).
  Future<String> folder() async {
    final custom = Store.i.settings.downloadDir;
    if (custom.isNotEmpty) return custom;
    if (_resolvedDefault != null) return _resolvedDefault!;
    final def = await defaultFolder();
    if (!Platform.isAndroid || await canWrite(def)) return _resolvedDefault = def;
    final ext = await getExternalStorageDirectory();
    return _resolvedDefault = ext == null ? def : '${ext.path}/Downloads';
  }

  /// Where chapters go: the Manga folder picked in Settings, else `<downloads>/Manga`.
  Future<String> mangaFolder() async {
    final custom = Store.i.settings.mangaDir;
    if (custom.isNotEmpty) return custom;
    return '${await folder()}${Platform.pathSeparator}Manga';
  }

  /// True when the app can create files in [dir]. Android 11+ only lets apps
  /// write into their own dirs and the shared Download / Movies collections.
  static Future<bool> canWrite(String dir) async {
    try {
      await PlatformPaths.ensure(dir);
      final probe = File('$dir${Platform.pathSeparator}.playzanime-probe');
      await probe.writeAsString('ok');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Lookups ───────────────────────────────────────────────────────────────

  /// A finished episode download, preferring the requested audio.
  DownloadJob? episodeFile(int mediaId, int episode, [Audio? audio]) {
    final done = _jobs.where((j) =>
        j.isEpisode && j.state == DownloadState.done && j.media.id == mediaId && j.episode == episode && j.outputFile != null);
    return done.where((j) => j.audio == audio).firstOrNull ?? done.firstOrNull;
  }

  List<DownloadJob> episodesFor(int mediaId) =>
      _jobs.where((j) => j.isEpisode && j.state == DownloadState.done && j.media.id == mediaId).toList();

  DownloadJob? chapterFile(String chapterId) => _jobs
      .where((j) => !j.isEpisode && j.state == DownloadState.done && j.chapter?.id == chapterId && j.outputFile != null)
      .firstOrNull;

  DownloadJob? active(String key) => _jobs.where((j) => !j.state.isFinished && _key(j) == key).firstOrNull;

  static String episodeKey(int mediaId, int episode) => 'e:$mediaId:$episode';
  static String chapterKey(String chapterId) => 'c:$chapterId';
  static String _key(DownloadJob j) => j.isEpisode ? episodeKey(j.media.id, j.episode ?? 0) : chapterKey(j.chapter?.id ?? '');

  /// Subtitle sidecars saved next to an episode file: label → path.
  static Map<String, String> sidecars(String videoFile) {
    final base = videoFile.substring(0, videoFile.lastIndexOf('.'));
    final dir = Directory(File(videoFile).parent.path);
    final out = <String, String>{};
    if (!dir.existsSync()) return out;
    for (final f in dir.listSync().whereType<File>()) {
      final p = f.path;
      if (p.startsWith('$base.') && p.endsWith('.vtt')) {
        out[p.substring(base.length + 1, p.length - 4)] = p;
      }
    }
    return out;
  }

  // ── Queue ─────────────────────────────────────────────────────────────────

  void enqueueEpisode({
    required MediaSnapshot media,
    required int episode,
    String? episodeTitle,
    required Audio audio,
    required String embedUrl,
    required QualityPref quality,
    List<String> subtitles = const [],
  }) {
    if (active(episodeKey(media.id, episode)) != null) return;
    final t = episodeTitle != null && !RegExp(r'^episode\s*\d+$', caseSensitive: false).hasMatch(episodeTitle.trim())
        ? ' · $episodeTitle'
        : '';
    _add(DownloadJob(
      id: 'e${media.id}-$episode-${DateTime.now().millisecondsSinceEpoch}',
      kind: 'episode',
      media: media,
      label: 'E${episode.toString().padLeft(2, '0')}$t',
      episode: episode,
      audio: audio,
      quality: quality,
      embedUrl: embedUrl,
      subtitleLabel: subtitles.join(subSep),
      state: DownloadState.queued,
      progress: 0,
      bytes: 0,
      speed: 0,
      partsDone: 0,
      partsTotal: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  void enqueueChapter(MediaSnapshot media, MChapter ch) {
    if (active(chapterKey(ch.id)) != null || chapterFile(ch.id) != null) return;
    _add(DownloadJob(
      id: 'c${media.id}-${DateTime.now().microsecondsSinceEpoch}',
      kind: 'chapter',
      media: media,
      label: ch.label,
      chapter: Chapter(
        id: ch.id,
        provider: ch.provider,
        name: ch.label,
        number: ch.number,
        title: ch.title,
        volume: ch.volume,
        group: ch.group,
        pages: ch.pages,
        publishedAt: ch.publishedAt,
      ),
      state: DownloadState.queued,
      progress: 0,
      bytes: 0,
      speed: 0,
      partsDone: 0,
      partsTotal: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  void _add(DownloadJob job) {
    _jobs.insert(0, job);
    _changed();
    _pump();
  }

  void pause(String id) {
    _cancel.remove(id)?.cancel('paused');
    _set(id, (j) => j.copyWith(state: DownloadState.paused, stage: 'Paused', speed: 0));
    _pump();
  }

  void resume(String id) {
    _retryTimers.remove(id)?.cancel();
    _set(id, (j) => j.copyWith(state: DownloadState.queued, stage: 'Waiting', error: ''));
    _pump();
  }

  void pauseAll() {
    for (final j in _jobs.where((j) => !j.state.isFinished && j.state != DownloadState.paused).toList()) {
      _retryTimers.remove(j.id)?.cancel();
      pause(j.id);
    }
  }

  void resumeAll() {
    for (final j in _jobs.where((j) => j.state == DownloadState.paused || j.state == DownloadState.error).toList()) {
      _attempts.remove(j.id);
      resume(j.id);
    }
  }

  int get activeCount => _jobs.where((j) => !j.state.isFinished && j.state != DownloadState.paused).length;

  void retry(String id) => resume(id);

  /// Cancels a running job, or deletes a finished one (and its files when [deleteFiles]).
  Future<void> remove(String id, {bool deleteFiles = true}) async {
    final job = _jobs.where((j) => j.id == id).firstOrNull;
    if (job == null) return;
    _cancel.remove(id)?.cancel('removed');
    _jobs.removeWhere((j) => j.id == id);
    _changed();
    await _deleteParts(id);
    if (deleteFiles && job.outputFile != null) {
      final f = job.outputFile!;
      try {
        if (job.isEpisode) {
          for (final s in sidecars(f).values) {
            await File(s).delete();
          }
        }
        await File(f).delete();
      } catch (_) {}
      await _deleteOfflineCache(id);
    }
    _pump();
  }

  void clearFinished() {
    _jobs.removeWhere((j) => j.state == DownloadState.error || j.state == DownloadState.cancelled);
    _changed();
  }

  void _pump() {
    if (!NetWatch.i.online) return;
    if (Store.i.settings.downloadOnlyOnWifi && NetWatch.i.metered) return;
    final running = _jobs.where((j) => j.state.isRunning).length;
    if (running >= _maxJobs) return;
    // Oldest first.
    final next = _jobs.reversed.where((j) => j.state == DownloadState.queued).firstOrNull;
    if (next == null) return;
    _run(next.id);
    _pump();
  }

  Future<void> _run(String id) async {
    final token = CancelToken();
    _cancel[id] = token;
    _set(id, (j) => j.copyWith(state: DownloadState.resolving, stage: 'Starting', error: ''));
    final job = _jobs.firstWhere((j) => j.id == id);
    try {
      if (job.isEpisode) {
        await _episode(job, token);
      } else {
        await _chapter(job, token);
      }
      _attempts.remove(id);
    } catch (e) {
      if (token.isCancelled) return; // pause/remove already set the state
      _log.warn('job $id failed: $e');
      if (!NetWatch.i.online) {
        // Lost the connection: wait for it, the part files are kept.
        _set(id, (j) => j.copyWith(state: DownloadState.queued, stage: 'Waiting for connection', speed: 0));
        return;
      }
      final n = (_attempts[id] ?? 0) + 1;
      _attempts[id] = n;
      const waits = [5, 15, 30, 60, 120, 300];
      if (n <= waits.length) {
        final wait = waits[n - 1];
        _set(id, (j) => j.copyWith(state: DownloadState.error, stage: 'Retrying in ${wait}s', error: _short(e), speed: 0));
        _retryTimers[id]?.cancel();
        _retryTimers[id] = Timer(Duration(seconds: wait), () {
          _retryTimers.remove(id);
          final j = _jobs.where((j) => j.id == id).firstOrNull;
          if (j != null && j.state == DownloadState.error) resume(id);
        });
      } else {
        _set(id, (j) => j.copyWith(state: DownloadState.error, stage: 'Failed', error: _short(e), speed: 0));
      }
    } finally {
      if (_cancel[id] == token) _cancel.remove(id);
      _pump();
    }
  }

  // ── Episodes ──────────────────────────────────────────────────────────────

  Future<void> _episode(DownloadJob job, CancelToken token) async {
    _set(job.id, (j) => j.copyWith(state: DownloadState.resolving, stage: 'Finding the stream'));
    var stream = await StreamResolver.i.resolve(job.embedUrl!);
    if (token.isCancelled) return;
    final want = job.quality ?? QualityPref.q720;

    // Keep the quality the part files were started with, so a resume after a
    // restart (or a token refresh) continues the same rendition.
    StreamVariant choose(ResolvedStream s) {
      final used = job.resolution;
      if (used != null) {
        final same = s.variants.where((v) => v.label == used).firstOrNull;
        if (same != null) return same;
      }
      return s.pick(want.maxHeight) ?? (([...s.variants]..sort((a, b) => a.height.compareTo(b.height))).firstOrNull ?? s.variants.first);
    }

    var variant = choose(stream);
    var opts = NetOptions(headers: StreamResolver.headersFor(stream), cancelToken: token, timeout: const Duration(seconds: 30));

    Future<MediaPlaylist> playlistOf(StreamVariant v) async {
      var url = v.url;
      var text = await Net.i.getText(url, opts);
      // A "variant" can still be a master playlist when the source sent only one level.
      if (text.contains('#EXT-X-STREAM-INF')) {
        final m = RegExp(r'#EXT-X-STREAM-INF[^\n]*\n\s*([^\s#][^\n]*)').firstMatch(text);
        if (m != null) {
          url = Uri.parse(url).resolve(m.group(1)!.trim()).toString();
          text = await Net.i.getText(url, opts);
        }
      }
      return parseMediaPlaylist(text, url);
    }

    var pl = await playlistOf(variant);
    if (pl.segments.isEmpty) throw StateError('The stream has no video segments.');

    // Segment URLs carry short-lived tokens; a long download outlives them.
    // When fetches start failing, resolve the episode again and carry on.
    var lastRefresh = DateTime.now();
    Future<void>? refreshing;
    Future<void> refresh() => refreshing ??= () async {
          _log.info('refreshing stream for ${job.id}');
          stream = await StreamResolver.i.resolve(job.embedUrl!, force: true);
          variant = choose(stream);
          opts = NetOptions(headers: StreamResolver.headersFor(stream), cancelToken: token, timeout: const Duration(seconds: 30));
          final fresh = await playlistOf(variant);
          if (fresh.segments.length != pl.segments.length) throw StateError('The stream changed; retry to start this episode again.');
          pl = fresh;
          lastRefresh = DateTime.now();
        }()
            .whenComplete(() => refreshing = null);

    final parts = await _partDir(job.id);
    final total = pl.segments.length + (pl.initSegment == null ? 0 : 1);
    var done = 0;
    var bytes = 0;
    for (var n = 0; n < pl.segments.length; n++) {
      final f = File('$parts/$n.part');
      if (f.existsSync()) {
        done++;
        bytes += f.lengthSync();
      }
    }
    _set(job.id, (j) => j.copyWith(
          state: DownloadState.downloading,
          stage: 'Downloading',
          partsTotal: total,
          partsDone: done,
          resolution: variant.label,
        ));

    final keys = <String, Uint8List>{};
    Future<Uint8List> keyFor(String uri) async => keys[uri] ??= await Net.i.getBytes(uri, opts);

    if (pl.initSegment != null) {
      final f = File('$parts/init.part');
      if (!f.existsSync()) await f.writeAsBytes(await Net.i.getBytes(pl.initSegment!, opts));
    }

    Future<Uint8List> segment(int n) async {
      try {
        return await _retry(() => Net.i.getBytes(pl.segments[n].url, opts), token);
      } catch (e) {
        if (token.isCancelled) rethrow;
        if (DateTime.now().difference(lastRefresh) < const Duration(seconds: 20) && refreshing == null) rethrow;
        await refresh();
        return _retry(() => Net.i.getBytes(pl.segments[n].url, opts), token);
      }
    }

    // Workers pull segment indexes; progress and speed update as each lands.
    var cursor = 0;
    final started = DateTime.now();
    var fetched = 0;
    Future<void> worker() async {
      while (true) {
        if (token.isCancelled) return;
        final n = cursor++;
        if (n >= pl.segments.length) return;
        final f = File('$parts/$n.part');
        if (f.existsSync()) continue;
        var data = await segment(n);
        final seg = pl.segments[n];
        if (seg.key != null && seg.key!.method == 'AES-128' && seg.key!.uri != null) {
          data = decryptAes128(data, await keyFor(seg.key!.uri!), seg.key!.iv ?? _seqIv(seg.seq));
        }
        data = alignTs(data);
        final tmp = File('$parts/$n.tmp');
        await tmp.writeAsBytes(data, flush: true);
        await tmp.rename(f.path);
        done++;
        bytes += data.length;
        fetched += data.length;
        final secs = DateTime.now().difference(started).inMilliseconds / 1000;
        _set(job.id, (j) => j.copyWith(
              partsDone: done,
              progress: done / total,
              bytes: bytes,
              speed: secs > 0 ? fetched / secs : 0,
            ));
      }
    }

    await Future.wait([for (var w = 0; w < _segmentWorkers; w++) worker()]);
    if (token.isCancelled) return;

    _set(job.id, (j) => j.copyWith(state: DownloadState.muxing, stage: 'Saving the file', speed: 0));
    final show = safeName(job.media.title.isEmpty ? 'Anime ${job.media.id}' : job.media.title);
    final dir = '${await folder()}${Platform.pathSeparator}$show';
    await PlatformPaths.ensure(dir);
    final q = job.resolution ?? variant.label;
    final out = await uniquePath('$dir${Platform.pathSeparator}$show - E${job.episode.toString().padLeft(2, '0')} [${(job.audio ?? Audio.sub).wire} $q].ts');
    final sink = File(out).openWrite();
    try {
      final init = File('$parts/init.part');
      if (init.existsSync()) await sink.addStream(init.openRead());
      for (var n = 0; n < pl.segments.length; n++) {
        await sink.addStream(File('$parts/$n.part').openRead());
      }
    } finally {
      await sink.close();
    }

    // Subtitles: the labels the user picked, matched by prefix ("English" keeps
    // "English [CC]"); "*" keeps every track.
    final wanted = (job.subtitleLabel ?? '').split(subSep).where((s) => s.isNotEmpty).map((s) => s.toLowerCase()).toList();
    String? firstSub;
    if (wanted.isNotEmpty) {
      final base = out.substring(0, out.lastIndexOf('.'));
      for (final t in stream.subtitles) {
        final l = t.label.toLowerCase();
        if (!wanted.contains('*') && !wanted.any((w) => l == w || l.startsWith(w))) continue;
        try {
          final vtt = await Net.i.getText(t.url, opts);
          final path = '$base.${safeName(t.label)}.vtt';
          await File(path).writeAsString(vtt);
          firstSub ??= path;
        } catch (e) {
          _log.warn('subtitle ${t.label} failed: $e');
        }
      }
    }

    await _deleteParts(job.id);
    final size = File(out).lengthSync();
    _finishedThisRun++;
    _set(job.id, (j) => j.copyWith(
          state: DownloadState.done,
          stage: 'Done',
          progress: 1,
          bytes: size,
          outputFile: out,
          subtitleFile: firstSub,
          finishedAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }

  // ── Chapters ──────────────────────────────────────────────────────────────

  Future<void> _chapter(DownloadJob job, CancelToken token) async {
    final c = job.chapter!;
    _set(job.id, (j) => j.copyWith(state: DownloadState.resolving, stage: 'Loading pages'));
    final pages = await MangaProviders.i.pages(MChapter(
      id: c.id,
      provider: c.provider,
      number: c.number,
      title: c.title,
      volume: c.volume,
      group: c.group,
    ));
    if (pages.isEmpty) throw StateError('This chapter has no pages on the source.');
    _set(job.id, (j) => j.copyWith(state: DownloadState.downloading, stage: 'Downloading', partsTotal: pages.length));

    final archive = Archive();
    var bytes = 0;
    final width = pages.length.toString().length.clamp(3, 6);
    final data = List<Uint8List?>.filled(pages.length, null);
    var cursor = 0;
    var done = 0;
    Future<void> worker() async {
      while (!token.isCancelled) {
        final n = cursor++;
        if (n >= pages.length) return;
        final p = pages[n];
        data[n] = await _retry(
          () async => p.ext != null
              // Extension pages come through the extension (headers, cookies, de-scrambling).
              ? await File(await Extensions.i.image(p)).readAsBytes()
              : await Net.i.getBytes(p.url, NetOptions(referer: p.referer, noCookies: true, cancelToken: token, timeout: const Duration(seconds: 30))),
          token,
        );
        done++;
        bytes += data[n]!.length;
        _set(job.id, (j) => j.copyWith(partsDone: done, progress: done / pages.length, bytes: bytes));
      }
    }

    await Future.wait([for (var w = 0; w < 4; w++) worker()]);
    if (token.isCancelled) return;
    for (var n = 0; n < pages.length; n++) {
      final b = data[n]!;
      archive.addFile(ArchiveFile.noCompress('${(n + 1).toString().padLeft(width, '0')}.${imageExt(b, pages[n].url)}', b.length, b));
    }

    _set(job.id, (j) => j.copyWith(state: DownloadState.muxing, stage: 'Saving the file'));
    final title = safeName(job.media.title.isEmpty ? 'Manga ${job.media.id}' : job.media.title);
    final dir = '${await mangaFolder()}${Platform.pathSeparator}$title';
    await PlatformPaths.ensure(dir);
    final out = await uniquePath('$dir${Platform.pathSeparator}${safeName(job.label)}.cbz');
    await File(out).writeAsBytes(ZipEncoder().encode(archive));
    _finishedThisRun++;
    _set(job.id, (j) => j.copyWith(
          state: DownloadState.done,
          stage: 'Done',
          progress: 1,
          bytes: File(out).lengthSync(),
          outputFile: out,
          finishedAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }

  /// Pages of a downloaded chapter, unpacked once into the app cache.
  Future<List<MPage>?> offlinePages(String chapterId) async {
    final job = chapterFile(chapterId);
    if (job == null || !File(job.outputFile!).existsSync()) return null;
    final dir = await _offlineCacheDir(job.id);
    final d = Directory(dir);
    if (!d.existsSync() || d.listSync().isEmpty) {
      await PlatformPaths.ensure(dir);
      final zip = ZipDecoder().decodeBytes(await File(job.outputFile!).readAsBytes());
      for (final f in zip.files) {
        if (!f.isFile) continue;
        await File('$dir${Platform.pathSeparator}${f.name.split('/').last}').writeAsBytes(f.content as List<int>);
      }
    }
    final files = d.listSync().whereType<File>().map((f) => f.path).toList()..sort();
    return [for (final f in files) MPage('file://$f')];
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<T> _retry<T>(Future<T> Function() fn, CancelToken token) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await fn();
      } catch (e) {
        if (token.isCancelled || attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }
  }

  Future<String> _partDir(String id) async {
    final dir = '${await PlatformPaths.root()}${Platform.pathSeparator}partials${Platform.pathSeparator}$id';
    await PlatformPaths.ensure(dir);
    return dir;
  }

  Future<void> _deleteParts(String id) async {
    try {
      final d = Directory('${await PlatformPaths.root()}${Platform.pathSeparator}partials${Platform.pathSeparator}$id');
      if (d.existsSync()) await d.delete(recursive: true);
    } catch (_) {}
  }

  Future<String> _offlineCacheDir(String id) async {
    final tmp = await getTemporaryDirectory();
    return '${tmp.path}${Platform.pathSeparator}offline${Platform.pathSeparator}$id';
  }

  Future<void> _deleteOfflineCache(String id) async {
    try {
      final d = Directory(await _offlineCacheDir(id));
      if (d.existsSync()) await d.delete(recursive: true);
    } catch (_) {}
  }

  void _set(String id, DownloadJob Function(DownloadJob) change) {
    final i = _jobs.indexWhere((j) => j.id == id);
    if (i < 0) return;
    final before = _jobs[i].state;
    _jobs[i] = change(_jobs[i]);
    _changed(stateChanged: before != _jobs[i].state);
  }

  void _changed({bool stateChanged = true}) {
    notifyListeners();
    if (stateChanged) {
      // State changes are saved at once so a kill never loses a queued job.
      _persist?.cancel();
      _persist = null;
      Store.i.saveDownloadRecords(_jobs);
    } else {
      _persist ??= Timer(const Duration(seconds: 2), () {
        _persist = null;
        Store.i.saveDownloadRecords(_jobs);
      });
    }
    _notifyTimer ??= Timer(const Duration(milliseconds: 900), () {
      _notifyTimer = null;
      _notify();
    });
  }

  /// The ongoing notification (and the foreground service that keeps
  /// downloads alive with the screen off), then a "done" note at the end.
  void _notify() {
    final active = _jobs.where((j) => !j.state.isFinished && j.state != DownloadState.paused).toList();
    if (active.isEmpty) {
      if (_hadActive) {
        _hadActive = false;
        final n = _finishedThisRun;
        _finishedThisRun = 0;
        Native.downloadDone(
          title: n > 0 && Store.i.settings.notifyDownloads ? 'Downloads finished' : null,
          text: n == 1 ? '1 item saved' : '$n items saved',
        );
      }
      return;
    }
    _hadActive = true;
    final cur = active.where((j) => j.state.isRunning).firstOrNull ?? active.first;
    final pct = (cur.progress * 100).round();
    final speed = cur.speed > 0 ? ' · ${(cur.speed / 1048576).toStringAsFixed(1)} MB/s' : '';
    Native.downloadProgress(
      title: active.length == 1 ? cur.media.title : 'Downloading ${active.length} items',
      text: '${active.length == 1 ? cur.label : '${cur.media.title} ${cur.label}'} · ${cur.stage ?? cur.state.label} · $pct%$speed',
      percent: cur.state == DownloadState.downloading ? pct : -1,
      active: active.length,
    );
  }

  static String _short(Object e) {
    final s = e is DioException ? (e.message ?? e.type.name) : '$e';
    return s.replaceFirst(RegExp(r'^(Bad state|Exception): '), '').split('\n').first;
  }
}

// ── Pure helpers (unit tested) ──────────────────────────────────────────────

class HlsKey {
  const HlsKey(this.method, this.uri, this.iv);
  final String method;
  final String? uri;
  final Uint8List? iv;
}

class HlsSegment {
  const HlsSegment(this.url, this.key, this.seq);
  final String url;
  final HlsKey? key;
  final int seq;
}

class MediaPlaylist {
  const MediaPlaylist(this.segments, this.initSegment);
  final List<HlsSegment> segments;
  final String? initSegment;
}

MediaPlaylist parseMediaPlaylist(String text, String base) {
  final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty);
  final baseUri = Uri.parse(base);
  final token = RegExp(r'[?&]token=([^&]+)').firstMatch(base)?.group(1);
  String withToken(String u) => token != null && !u.contains('?') ? '$u?token=$token' : u;
  String? attr(String line, String name) {
    final m = RegExp('(?:^|[:,])$name=(?:"([^"]*)"|([^,]*))').firstMatch(line);
    return m == null ? null : (m.group(1) ?? m.group(2));
  }

  var seq = 0;
  HlsKey? key;
  String? init;
  final segs = <HlsSegment>[];
  for (final line in lines) {
    if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
      seq = int.tryParse(line.split(':')[1]) ?? 0;
    } else if (line.startsWith('#EXT-X-KEY:')) {
      final method = attr(line, 'METHOD') ?? 'NONE';
      final uri = attr(line, 'URI');
      final ivHex = attr(line, 'IV');
      key = method == 'NONE'
          ? null
          : HlsKey(method, uri == null ? null : baseUri.resolve(uri).toString(), ivHex == null ? null : _hex(ivHex));
    } else if (line.startsWith('#EXT-X-MAP:')) {
      final uri = attr(line, 'URI');
      if (uri != null) init = withToken(baseUri.resolve(uri).toString());
    } else if (!line.startsWith('#')) {
      segs.add(HlsSegment(withToken(baseUri.resolve(line).toString()), key, seq));
      seq++;
    }
  }
  return MediaPlaylist(segs, init);
}

Uint8List _hex(String s) {
  final h = s.replaceFirst(RegExp('^0x', caseSensitive: false), '').padLeft(32, '0');
  return Uint8List.fromList([for (var i = 0; i < 32; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
}

/// HLS default IV: the media sequence number as a 128-bit big-endian integer.
Uint8List _seqIv(int seq) {
  final iv = Uint8List(16);
  for (var i = 0; i < 8; i++) {
    iv[15 - i] = (seq >> (8 * i)) & 0xff;
  }
  return iv;
}

Uint8List decryptAes128(Uint8List data, Uint8List key, Uint8List iv) {
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
    ..init(false, PaddedBlockCipherParameters<CipherParameters, CipherParameters>(ParametersWithIV(KeyParameter(key), iv), null));
  return cipher.process(data);
}

/// Some CDNs prefix MPEG-TS segments with junk (often a fake image header). Skip to the first sync-byte run.
Uint8List alignTs(Uint8List buf) {
  if (buf.length < 564 || (buf[0] == 0x47 && buf[188] == 0x47)) return buf;
  final limit = (buf.length - 376).clamp(0, 512 * 1024);
  for (var i = buf.indexOf(0x47); i != -1 && i < limit; i = buf.indexOf(0x47, i + 1)) {
    if (buf[i + 188] == 0x47 && buf[i + 376] == 0x47) return Uint8List.sublistView(buf, i);
  }
  return buf;
}

String imageExt(Uint8List b, String url) {
  String ascii(int s, int e) => b.length >= e ? String.fromCharCodes(b.sublist(s, e)) : '';
  if (b.length > 2 && b[0] == 0xff && b[1] == 0xd8) return 'jpg';
  if (b.length > 2 && b[0] == 0x89 && b[1] == 0x50) return 'png';
  if (ascii(8, 12) == 'WEBP') return 'webp';
  if (ascii(0, 3) == 'GIF') return 'gif';
  if (ascii(4, 8) == 'ftyp' && RegExp(r'^avi[fs]$').hasMatch(ascii(8, 12))) return 'avif';
  final m = RegExp(r'\.(jpe?g|png|webp|gif|avif)(?:\?|$)', caseSensitive: false).firstMatch(url)?.group(1)?.toLowerCase();
  return m == 'jpeg' ? 'jpg' : (m ?? 'jpg');
}

String safeName(String s) {
  final out = s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final cut = out.length > 120 ? out.substring(0, 120).trim() : out;
  return cut.replaceAll(RegExp(r'[. ]+$'), '');
}

Future<String> uniquePath(String p) async {
  if (!File(p).existsSync()) return p;
  final dot = p.lastIndexOf('.');
  final name = p.substring(0, dot);
  final ext = p.substring(dot);
  for (var i = 2; i < 100; i++) {
    final c = '$name ($i)$ext';
    if (!File(c).existsSync()) return c;
  }
  return '$name ${DateTime.now().millisecondsSinceEpoch}$ext';
}
