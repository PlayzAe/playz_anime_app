import '../models/media.dart';

/// Pure formatting helpers, ported from `src/renderer/lib/format.ts`.
///
/// Everything here is deterministic and side-effect free, which makes it the
/// first thing the unit-test council covers.
abstract final class Fmt {
  // ── Titles ────────────────────────────────────────────────────────────────

  static String titleOf(Media m, {String lang = 'english'}) {
    final t = m.title;
    final primary = lang == 'english' ? (t.english ?? t.romaji) : (t.romaji ?? t.english);
    return primary ?? t.userPreferred ?? t.native ?? 'Untitled';
  }

  /// The other-language title, shown small under the main one when it differs.
  static String? altTitleOf(Media m, {String lang = 'english'}) {
    final main = titleOf(m, lang: lang);
    final other = lang == 'english' ? m.title.romaji : m.title.english;
    if (other == null) return null;
    return other.toLowerCase() == main.toLowerCase() ? null : other;
  }

  static String coverOf(Media m) =>
      m.coverImage?.extraLarge ?? m.coverImage?.large ?? m.coverImage?.medium ?? '';

  /// Grid-sized cover: the 230px `large` file is plenty for a 160px card when
  /// saving data.
  static String posterOf(Media m, bool dataSaver) =>
      (dataSaver ? (m.coverImage?.large ?? coverOf(m)) : coverOf(m));

  // ── Snapshots ─────────────────────────────────────────────────────────────

  static MediaSnapshot snapshot(Media m, {String lang = 'english'}) => MediaSnapshot(
    id: m.id,
    type: m.type ?? ((m.chapters != null || m.format == 'MANGA' || m.format == 'ONE_SHOT') ? MediaType.manga : MediaType.anime),
    chapters: m.chapters,
    title: titleOf(m, lang: lang),
    romaji: m.title.romaji,
    native: m.title.native,
    cover: coverOf(m),
    banner: m.bannerImage,
    color: m.coverImage?.color,
    format: m.format,
    episodes: m.episodes,
    year: m.seasonYear ?? m.startDate?.year,
    status: m.status,
    country: m.countryOfOrigin,
  );

  static MediaSnapshot snapshotOfDetail(MediaDetail m, {String lang = 'english'}) => snapshot(m, lang: lang);

  // ── Labels ────────────────────────────────────────────────────────────────

  static const Map<String, String> _formats = {
    'TV': 'TV',
    'TV_SHORT': 'TV short',
    'MOVIE': 'Movie',
    'SPECIAL': 'Special',
    'OVA': 'OVA',
    'ONA': 'ONA',
    'MUSIC': 'Music',
    'MANGA': 'Manga',
    'NOVEL': 'Novel',
    'ONE_SHOT': 'One-shot',
  };

  static String? formatLabel(String? f) => f == null ? null : (_formats[f] ?? f);

  /// Manga from Korea and China read as manhwa and manhua.
  static String? mangaKind(Media m) {
    if (m.format == 'ONE_SHOT') return 'One-shot';
    if (m.countryOfOrigin == 'KR') return 'Manhwa';
    if (m.countryOfOrigin == 'CN' || m.countryOfOrigin == 'TW') return 'Manhua';
    return m.format == 'MANGA' ? 'Manga' : formatLabel(m.format);
  }

  static bool isManga(Media m) =>
      m.type == MediaType.manga || m.format == 'MANGA' || m.format == 'ONE_SHOT' || m.format == 'NOVEL';

  static String mediaPath(Media m) => isManga(m) ? '/manga/${m.id}' : '/anime/${m.id}';

  static String? statusLabel(MediaStatus? s) => switch (s) {
    null => null,
    MediaStatus.finished => 'Finished',
    MediaStatus.releasing => 'Airing',
    MediaStatus.notYetReleased => 'Upcoming',
    MediaStatus.cancelled => 'Cancelled',
    MediaStatus.hiatus => 'On hiatus',
  };

  static String seasonName(MediaSeason s) =>
      s.name[0].toUpperCase() + s.name.substring(1).toLowerCase();

  static String? seasonLabel(Media m) {
    if (m.season != null && m.seasonYear != null) return '${seasonName(m.season!)} ${m.seasonYear}';
    final y = m.seasonYear ?? m.startDate?.year;
    return y == null ? null : '$y';
  }

  static String? scoreLabel(int? avg) => avg == null || avg == 0 ? null : (avg / 10).toStringAsFixed(1);

  static String? episodesLabel(Media m) {
    if (isManga(m)) return m.chapters == null ? null : '${m.chapters} ch';
    if (m.format == 'MOVIE') return null;
    if (m.episodes != null) return '${m.episodes} ep${m.episodes == 1 ? '' : 's'}';
    if (m.nextAiringEpisode != null) return '${m.nextAiringEpisode!.episode - 1} eps so far';
    return null;
  }

  /// The short meta line under a poster: `TV · 24 eps · 2024`.
  static String posterMeta(Media m) {
    final parts = <String>[
      if (isManga(m)) ?mangaKind(m) else ?formatLabel(m.format),
      ?episodesLabel(m),
      if (m.seasonYear != null) '${m.seasonYear}',
    ];
    return parts.where((p) => p.isNotEmpty).join(' · ');
  }

  // ── Time ──────────────────────────────────────────────────────────────────

  /// `2d 4h`, `5h 12m`, `12m`
  static String countdown(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final d = s ~/ 86400;
    final h = (s % 86400) ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (d > 0) return h > 0 ? '${d}d ${h}h' : '${d}d';
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    return '${m < 1 ? 1 : m}m';
  }

  /// `3 min ago`, `5 h ago`, `yesterday`, `12 Sep`
  static String relativeTime(int ms, [int? now]) {
    final n = now ?? DateTime.now().millisecondsSinceEpoch;
    final diff = (n - ms) / 1000;
    if (diff < 0) return 'in ${countdown(diff.abs().round())}';
    if (diff < 60) return 'just now';
    if (diff < 3600) return '${(diff / 60).floor()} min ago';
    if (diff < 86400) return '${(diff / 3600).floor()} h ago';
    if (diff < 172800) return 'yesterday';
    if (diff < 7 * 86400) return '${(diff / 86400).floor()} days ago';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day} ${_months[d.month - 1]}';
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Player clock: `4:05`, `23:40`, `1:02:13`
  static String clock(num seconds) {
    var s = seconds.isFinite && seconds > 0 ? seconds.toInt() : 0;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }

  static String bytes(num n) {
    if (n <= 0) return '0 MB';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    var v = n.toDouble();
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    final text = (v >= 100 || i == 0) ? v.round().toString() : v.toStringAsFixed(1);
    return '$text ${units[i]}';
  }

  static String speed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '';
    return '${bytes(bytesPerSecond)}/s';
  }

  // ── Descriptions ──────────────────────────────────────────────────────────

  /// AniList descriptions carry `<br>`, `<i>` and entities even with
  /// `asHtml: false`.
  static String plainText(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    return raw
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'&#0?39;|&apos;'), "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&mdash;', '—')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'\(Source:[^)]*\)\s*$', caseSensitive: false), '')
        .trim();
  }

  static int? mediaYear(Media m) => m.seasonYear ?? m.startDate?.year;

  // ── Progress ──────────────────────────────────────────────────────────────

  /// `E07 · The Journey's End`
  static String episodeLabel(int number, String? title) {
    final n = number.toString().padLeft(2, '0');
    final t = (title ?? '').trim();
    final generic = RegExp(r'^(episode\s*\d+|ep\.?\s*\d+|full|\d+)$', caseSensitive: false).hasMatch(t);
    return generic || t.isEmpty ? 'E$n' : 'E$n · $t';
  }

  /// `Ch. 147 · The Night Before`
  static String chapterLabel(String? number, String? name, String? title) {
    final raw = (number ?? '').trim();
    final fromName = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(name ?? '')?.group(1);
    final n = raw.isNotEmpty ? raw : fromName;
    final t = (title ?? '').trim();
    if (n == null) return t.isEmpty ? (name ?? 'Chapter') : t;
    return t.isEmpty ? 'Ch. $n' : 'Ch. $n · $t';
  }

  /// `Season 2` — from a show title, else null.
  static String? seasonOf(String title) {
    final m = RegExp(r'\b(?:season|s)\s*(\d{1,2})\b', caseSensitive: false).firstMatch(title);
    if (m != null) return 'Season ${m.group(1)}';
    final ord = RegExp(r'\b(2nd|3rd|4th|5th)\s+season\b', caseSensitive: false).firstMatch(title);
    if (ord != null) {
      const map = {'2nd': '2', '3rd': '3', '4th': '4', '5th': '5'};
      return 'Season ${map[ord.group(1)!.toLowerCase()]}';
    }
    final roman = RegExp(r'\b(II|III|IV|V)\b').firstMatch(title);
    if (roman != null) {
      const map = {'II': '2', 'III': '3', 'IV': '4', 'V': '5'};
      return 'Season ${map[roman.group(1)!]}';
    }
    return null;
  }

  /// A safe folder name: strips the characters Windows and Android both reject.
  static String safeFileName(String raw, {int max = 80}) {
    var s = raw
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    s = s.replaceAll(RegExp(r'[.\s]+$'), '');
    if (s.length > max) s = s.substring(0, max).trim();
    return s.isEmpty ? 'Untitled' : s;
  }
}

abstract final class Format {
  static String titleOf(Media m, {String lang = 'english'}) => Fmt.titleOf(m, lang: lang);
  static String? altTitleOf(Media m, {String lang = 'english'}) => Fmt.altTitleOf(m, lang: lang);
  static String coverOf(Media m) => Fmt.coverOf(m);
  static String posterOf(Media m, bool dataSaver) => Fmt.posterOf(m, dataSaver);
  static MediaSnapshot snapshot(Media m, {String lang = 'english'}) => Fmt.snapshot(m, lang: lang);
  static MediaSnapshot snapshotOfDetail(MediaDetail m, {String lang = 'english'}) => Fmt.snapshotOfDetail(m, lang: lang);
  static String? formatLabel(String? f) => Fmt.formatLabel(f);
  static String? mangaKind(Media m) => Fmt.mangaKind(m);
  static bool isManga(Media m) => Fmt.isManga(m);
  static String mediaPath(Media m) => Fmt.mediaPath(m);
  static String? statusLabel(MediaStatus? s) => Fmt.statusLabel(s);
  static String seasonName(MediaSeason s) => Fmt.seasonName(s);
  static String? seasonLabel(Media m) => Fmt.seasonLabel(m);
  static String? scoreLabel(int? avg) => Fmt.scoreLabel(avg);
  static String? episodesLabel(Media m) => Fmt.episodesLabel(m);
  static String posterMeta(Media m) => Fmt.posterMeta(m);
  static String countdown(int seconds) => Fmt.countdown(seconds);
  static String relativeTime(int ms, [int? now]) => Fmt.relativeTime(ms, now);
  static String clock(num seconds) => Fmt.clock(seconds);
  static String bytes(num n) => Fmt.bytes(n);
  static String speed(double bytesPerSecond) => Fmt.speed(bytesPerSecond);
  static String plainText(String? raw) => Fmt.plainText(raw);
  static int? mediaYear(Media m) => Fmt.mediaYear(m);
  static String episodeLabel(int number, String? title) => Fmt.episodeLabel(number, title);
  static String chapterLabel(String? number, String? name, String? title) => Fmt.chapterLabel(number, name, title);
  static String? seasonOf(String title) => Fmt.seasonOf(title);
  static String safeFileName(String raw, {int max = 80}) => Fmt.safeFileName(raw, max: max);
}

