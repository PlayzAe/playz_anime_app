import 'package:flutter_test/flutter_test.dart';
import 'package:playzanime/services/net.dart';
import 'package:playzanime/services/anilist.dart';
import 'package:playzanime/models/media.dart';

void main() {
  test('probe', () async {
    final sw = Stopwatch()..start();
    try {
      final r = await Net.i.postJson('https://graphql.anilist.co', {'query': '{ Media(id: 1) { id } }'}).timeout(const Duration(seconds: 20));
      print('RAW ok ${sw.elapsedMilliseconds}ms $r');
    } catch (e) {
      print('RAW fail ${sw.elapsedMilliseconds}ms $e');
    }
    sw.reset();
    try {
      final m = await AniList.i.media(154587).timeout(const Duration(seconds: 40));
      print('MEDIA ok ${sw.elapsedMilliseconds}ms ${m.title.romaji}');
    } catch (e) {
      print('MEDIA fail ${sw.elapsedMilliseconds}ms $e');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
