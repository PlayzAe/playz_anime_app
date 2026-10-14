import 'package:flutter_test/flutter_test.dart';
import 'package:playzanime/models/media.dart';

void main() {
  group('Media Models Unit Tests', () {
    test('Media.fromJson parses null safe attributes correctly', () {
      final json = <String, dynamic>{
        'id': 1001,
        'type': 'ANIME',
        'format': 'TV',
        'status': 'FINISHED',
        'title': {
          'romaji': 'Sousou no Frieren',
          'english': 'Frieren: Beyond Journey\'s End',
        },
        'episodes': 28,
        'averageScore': 95,
        'isAdult': false,
      };

      final media = Media.fromJson(json);
      expect(media.id, 1001);
      expect(media.title.english, 'Frieren: Beyond Journey\'s End');
      expect(media.title.romaji, 'Sousou no Frieren');
      expect(media.format, 'TV');
      expect(media.episodes, 28);
      expect(media.averageScore, 95);
      expect(media.isAdult, isFalse);
    });

    test('Media.toSnapshot converts Media to lightweight snapshot for library/history', () {
      final media = Media(
        id: 2002,
        title: const MediaTitle(english: 'One Piece', romaji: 'One Piece'),
        coverImage: const CoverImage(large: 'https://cdn.example.com/op.jpg'),
        status: MediaStatus.releasing,
        format: 'TV',
        episodes: null,
      );

      final snapshot = media.toSnapshot();
      expect(snapshot.id, 2002);
      expect(snapshot.title.english, 'One Piece');
      expect(snapshot.coverImage.large, 'https://cdn.example.com/op.jpg');

      final json = snapshot.toJson();
      final revived = MediaSnapshot.fromJson(json);
      expect(revived.id, 2002);
      expect(revived.title.english, 'One Piece');
    });

    test('MediaDetail parses nextAiringEpisode and relations correctly', () {
      final json = <String, dynamic>{
        'id': 3003,
        'status': 'RELEASING',
        'title': {'english': 'Chainsaw Man'},
        'nextAiringEpisode': {
          'episode': 13,
          'airingAt': 1750000000,
          'timeUntilAiring': 86400,
        },
      };

      final detail = MediaDetail.fromJson(json);
      expect(detail.id, 3003);
      expect(detail.nextAiringEpisode?.episode, 13);
      expect(detail.nextAiringEpisode?.timeUntilAiring, 86400);
    });
  });
}
