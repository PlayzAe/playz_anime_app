import 'package:flutter_test/flutter_test.dart';
import 'package:playzanime/models/local.dart';
import 'package:playzanime/models/media.dart';
import 'package:playzanime/models/stream.dart';

void main() {
  group('Local Storage Models Unit Tests', () {
    test('ListStatus.parse parses wire strings with planning fallback', () {
      expect(ListStatus.parse('watching'), ListStatus.watching);
      expect(ListStatus.parse('planning'), ListStatus.planning);
      expect(ListStatus.parse('completed'), ListStatus.completed);
      expect(ListStatus.parse('paused'), ListStatus.paused);
      expect(ListStatus.parse('dropped'), ListStatus.dropped);
      expect(ListStatus.parse('invalid_status'), ListStatus.planning);
      expect(ListStatus.parse(null), ListStatus.planning);
    });

    test('LibraryEntry serializes and deserializes accurately', () {
      final snapshot = MediaSnapshot(
        id: 501,
        title: const MediaTitle(english: 'Bleach'),
      );
      final entry = LibraryEntry(
        media: snapshot,
        status: ListStatus.watching,
        addedAt: 1700000000,
        updatedAt: 1700005000,
        categories: const ['Favorites', 'Action'],
      );

      final json = entry.toJson();
      final revived = LibraryEntry.fromJson(json);

      expect(revived.media.id, 501);
      expect(revived.status, ListStatus.watching);
      expect(revived.addedAt, 1700000000);
      expect(revived.updatedAt, 1700005000);
      expect(revived.categories, ['Favorites', 'Action']);
    });

    test('HistoryEntry records episode position and audio accurately', () {
      final snapshot = MediaSnapshot(
        id: 601,
        title: const MediaTitle(english: 'Naruto'),
      );
      final entry = HistoryEntry(
        media: snapshot,
        episode: 15,
        position: 1200.5,
        duration: 1420.0,
        audio: Audio.sub,
        updatedAt: 1700009000,
        episodeTitle: 'The Chunin Exam Begins',
      );

      expect(entry.media.id, 601);
      expect(entry.episode, 15);
      expect(entry.position, 1200.5);
      expect(entry.duration, 1420.0);
      expect(entry.audio, Audio.sub);
      expect(entry.episodeTitle, 'The Chunin Exam Begins');
    });
  });
}
