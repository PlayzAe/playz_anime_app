// Live smoke test (network). Not part of the unit suite:
//   flutter test tool/live/sources_live_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playzanime/models/media.dart';
import 'package:playzanime/services/anilist.dart';
import 'package:playzanime/sources/ani/episodes.dart';
import 'package:playzanime/sources/manga/providers.dart';
import 'package:playzanime/views/search_view.dart' show expandAlias;

void main() {
  test('anime', () async {
    for (final q in ['rezero', 'Frieren', 'jjk']) {
      final page = await AniList.i.browse(BrowseFilters(type: MediaType.anime, search: expandAlias(q).query));
      final m = page.items.first;
      final eps = await listEpisodes(m.id);
      print('ANIME "$q" -> ${m.title.romaji}: ${eps.episodes.length} eps fallback=${eps.fallback} dub=${eps.hasDub} e1=${eps.episodes.first.subUrl}');
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    print('SCHEDULE ${(await AniList.i.schedule(now, now + 7 * 86400)).length} items');
    final sol = await AniList.i.browse(const BrowseFilters(type: MediaType.anime, genres: ['Slice of Life'], sort: SortKey.popularityDesc));
    print('SLICE OF LIFE ${sol.items.length}: ${sol.items.take(3).map((m) => m.title.romaji).toList()}');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('manga', () async {
    for (final q in ['Solo Leveling', 'Chainsaw Man']) {
      final page = await AniList.i.browse(BrowseFilters(type: MediaType.manga, search: q));
      final m = page.items.first;
      final list = await MangaProviders.i.chapterList(m.id);
      print('MANGA "$q" picked=${list.provider} ch=${list.chapters.length}');
      for (final p in list.providers) {
        print('  ${p.provider}: ${p.chapterCount} latest=${p.latest} err=${p.error == null ? '-' : p.error!.substring(0, p.error!.length.clamp(0, 80))}');
      }
      if (list.chapters.isNotEmpty) {
        final pages = await MangaProviders.i.pages(list.chapters.firstWhere((c) => c.externalUrl == null));
        print('  pages=${pages.length} ${pages.isEmpty ? '' : pages.first.url}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
