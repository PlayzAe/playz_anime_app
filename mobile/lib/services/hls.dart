import '../models/stream.dart';

/// M3U8 parsing, ported from `parseMaster`, `segmentHosts` and `qualityLabel`
/// in `src/main/extractor.ts`.
///
/// Pure string work, no I/O — which makes it the first thing the unit-test
/// council can pin down without touching the network.
abstract final class Hls {
  static bool isMaster(String playlist) => playlist.contains('#EXT-X-STREAM-INF');

  /// Parses a master playlist into quality variants.
  ///
  /// A URL that turns out to be a media playlist yields a single `Auto` variant,
  /// which is what the desktop build did — the player can still use it.
  static List<StreamVariant> parseMaster(String text, String masterUrl) {
    if (!isMaster(text)) {
      return [StreamVariant(label: 'Auto', height: 0, bandwidth: 0, url: masterUrl)];
    }

    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final variants = <StreamVariant>[];
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
      if (i + 1 >= lines.length) continue;
      final uri = lines[i + 1];
      if (uri.isEmpty || uri.startsWith('#')) continue;

      final res = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(lines[i]);
      final bw = int.tryParse(RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i])?.group(1) ?? '') ?? 0;
      final q = qualityLabel(res == null ? 0 : int.tryParse(res.group(2)!) ?? 0, bw);
      variants.add(
        StreamVariant(
          label: q.label,
          height: q.height,
          bandwidth: bw,
          url: withToken(_resolve(uri, masterUrl), masterUrl),
        ),
      );
    }

    variants.sort((a, b) => b.height != a.height ? b.height.compareTo(a.height) : b.bandwidth.compareTo(a.bandwidth));
    // Drop duplicate tiers: same label, lower bitrate.
    final out = <StreamVariant>[];
    for (final v in variants) {
      if (out.isEmpty || out.last.label != v.label) out.add(v);
    }
    return out;
  }

  /// Some players hand back a bare media playlist whose segments need the
  /// master's `token` query parameter. Carrying it across is the difference
  /// between a stream that plays and a stream that 403s.
  static String withToken(String url, String master) {
    final m = RegExp(r'[?&]token=([^&]+)').firstMatch(master);
    final token = m?.group(1);
    if (token == null || url.contains('?')) return url;
    return '$url?token=$token';
  }

  static String _resolve(String uri, String base) {
    if (uri.startsWith('http://') || uri.startsWith('https://')) return uri;
    return Uri.parse(base).resolve(uri).toString();
  }

  /// `1080p` from a RESOLUTION height, falling back to the advertised bitrate
  /// when the playlist does not state one.
  static ({String label, int height}) qualityLabel(int height, int bandwidth) {
    var h = height;
    if (h == 0) {
      final kbps = bandwidth / 1000;
      h = kbps >= 3500
          ? 1080
          : kbps >= 1500
          ? 720
          : kbps >= 800
          ? 480
          : 360;
    }
    const tiers = [2160, 1440, 1080, 720, 480, 360, 240];
    for (final t in tiers) {
      if (h >= t * 0.9) return (label: '${t}p', height: t);
    }
    return (label: '${h}p', height: h);
  }

  /// The first handful of segment and key URLs in a media playlist.
  ///
  /// Used to work out which hosts a stream will touch, so the header rules can
  /// cover every request the player makes.
  static List<String> segmentUrls(String text, String playlistUrl, {int limit = 12}) {
    final urls = <String>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final key = RegExp(r'URI="([^"]+)"').firstMatch(line)?.group(1);
      if (key != null) {
        urls.add(_resolve(key, playlistUrl));
      } else if (!line.startsWith('#')) {
        urls.add(_resolve(line, playlistUrl));
      }
      if (urls.length > limit) break;
    }
    return urls;
  }

  /// Every segment of a media playlist, in order.
  static List<String> allSegments(String text, String playlistUrl) {
    final urls = <String>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      urls.add(_resolve(line, playlistUrl));
    }
    return urls;
  }

  /// `#EXT-X-MAP:URI="init.mp4"` — present on fragmented-MP4 playlists, and the
  /// difference between a playable file and a useless blob on disk.
  static String? initSegment(String text, String playlistUrl) {
    final m = RegExp(r'#EXT-X-MAP:URI="([^"]+)"').firstMatch(text);
    return m == null ? null : _resolve(m.group(1)!, playlistUrl);
  }

  /// True when the segments are MPEG-TS (concatenating them makes a valid file)
  /// rather than fragmented MP4 (which needs the init segment kept at the front).
  static bool isTransportStream(String text) =>
      !text.contains('#EXT-X-MAP') && !text.contains('.m4s');

  /// Total duration from `#EXTINF` values, in seconds. 0 when unknown.
  static double duration(String text) {
    var total = 0.0;
    for (final m in RegExp(r'#EXTINF:\s*([\d.]+)').allMatches(text)) {
      total += double.tryParse(m.group(1)!) ?? 0;
    }
    return total;
  }
}
