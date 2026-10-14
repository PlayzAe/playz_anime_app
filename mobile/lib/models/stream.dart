import 'json.dart';

enum Audio {
  sub('sub'),
  dub('dub');

  const Audio(this.wire);
  final String wire;

  static Audio parse(String? v) => v == 'dub' ? Audio.dub : Audio.sub;
}

class Episode {
  const Episode({
    required this.number,
    required this.title,
    this.subUrl,
    this.dubUrl,
    this.thumbnail,
  });

  final int number;
  final String title;
  final String? subUrl;
  final String? dubUrl;
  final String? thumbnail;

  String? urlFor(Audio audio) => audio == Audio.dub ? (dubUrl ?? subUrl) : (subUrl ?? dubUrl);
}

class EpisodeList {
  const EpisodeList({
    required this.mediaId,
    required this.fallback,
    required this.hasDub,
    required this.episodes,
    this.sourceId,
    this.available = true,
  });

  final int mediaId;
  final int? sourceId;

  /// False when the streaming source has no copy of this title at all (the
  /// fallback embed answers with its error page), so the app can say so
  /// instead of spinning on every episode.
  final bool available;

  /// True when the provider lookup failed and the list was built from AniList's
  /// episode count instead.
  final bool fallback;
  final bool hasDub;
  final List<Episode> episodes;
}

class StreamVariant {
  const StreamVariant({
    required this.label,
    required this.height,
    required this.bandwidth,
    required this.url,
  });

  final String label;
  final int height;
  final int bandwidth;
  final String url;

  factory StreamVariant.fromJson(Map<String, dynamic> j) => StreamVariant(
    label: j.str('label') ?? '',
    height: j.integer('height') ?? 0,
    bandwidth: j.integer('bandwidth') ?? 0,
    url: j.str('url') ?? '',
  );
}

class SubtitleTrack {
  const SubtitleTrack({required this.label, required this.url, this.isDefault = false});

  final String label;
  final String url;
  final bool isDefault;
}

class TimeRange {
  const TimeRange({required this.start, required this.end});

  final double start;
  final double end;

  bool contains(double t) => t >= start && t <= end;
}

/// An embed page resolved down to a playable HLS master playlist.
class ResolvedStream {
  const ResolvedStream({
    required this.embedUrl,
    required this.master,
    this.referer = 'https://megaplay.buzz/',
    required this.host,
    required this.variants,
    required this.subtitles,
    required this.resolvedAt,
    this.intro,
    this.outro,
  });

  final String embedUrl;
  final String master;

  /// Origin the embed lives on; every stream request must send it as Referer.
  final String referer;
  final String host;
  final List<StreamVariant> variants;
  final List<SubtitleTrack> subtitles;
  final TimeRange? intro;
  final TimeRange? outro;
  final int resolvedAt;

  /// Best variant at or below [maxHeight]; falls back to the highest available.
  StreamVariant? pick(int maxHeight) {
    if (variants.isEmpty) return null;
    final sorted = [...variants]..sort((a, b) => b.height.compareTo(a.height));
    for (final v in sorted) {
      if (v.height <= maxHeight) return v;
    }
    return sorted.last;
  }
}
