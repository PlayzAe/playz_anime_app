import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playzanime/services/cache.dart';
import 'package:playzanime/services/hls.dart';
import 'package:playzanime/services/stream_resolver.dart';
import 'package:playzanime/sources/manga/providers.dart';
import 'package:playzanime/views/search_view.dart' show expandAlias;

void main() {
  group('TtlCache', () {
    test('wrap completes (regression: whenComplete awaited its own future)', () async {
      final c = TtlCache<int>(4);
      final v = await c.wrap('a', 1000, () async => 7).timeout(const Duration(seconds: 2));
      expect(v, 7);
    });

    test('concurrent callers share one build, later calls hit the cache', () async {
      final c = TtlCache<int>(4);
      var builds = 0;
      Future<int> build() async {
        builds++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 1;
      }

      final r = await Future.wait([c.wrap('k', 1000, build), c.wrap('k', 1000, build)]);
      expect(r, [1, 1]);
      expect(await c.wrap('k', 1000, build), 1);
      expect(builds, 1);
    });

    test('a failed build is not cached', () async {
      final c = TtlCache<int>(4);
      await expectLater(c.wrap('x', 1000, () async => throw StateError('boom')), throwsStateError);
      expect(await c.wrap('x', 1000, () async => 2), 2);
    });
  });

  group('search aliases', () {
    test('expands shorthand people type', () {
      expect(expandAlias('rezero').query, 'Re:Zero');
      expect(expandAlias(' JJK ').query, 'Jujutsu Kaisen');
      expect(expandAlias('frieren').expanded, isTrue);
    });

    test('leaves real queries alone', () {
      final r = expandAlias('Solo Leveling');
      expect(r.query, 'Solo Leveling');
      expect(r.expanded, isFalse);
    });
  });

  group('HLS', () {
    test('parses variants, best first', () {
      const master = '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=854x480\nlow/index.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080\nhigh/index.m3u8\n';
      final v = Hls.parseMaster(master, 'https://cdn.example/x/master.m3u8');
      expect(v.first.label, '1080p');
      expect(v.first.url, 'https://cdn.example/x/high/index.m3u8');
      expect(v.last.label, '480p');
    });
  });

  group('stream labels', () {
    test('subtitle language from file name', () {
      expect(StreamResolver.labelFromUrl('https://h/subtitles/spa-5.vtt'), 'Spanish');
      expect(StreamResolver.labelFromUrl('https://h/subtitles/xyz.vtt'), 'English');
    });

    test('tidies megaplay labels and keeps them unique', () {
      expect(StreamResolver.tidyLabel('Portuguese (- Portuguese(Brazil))'), 'Portuguese (Brazil)');
      final seen = <String>{};
      expect(StreamResolver.uniqueLabel(seen, 'English'), 'English');
      expect(StreamResolver.uniqueLabel(seen, 'English'), 'English 2');
    });
  });

  group('manga helpers', () {
    test('chapter labels', () {
      expect(const MChapter(id: 'a:1', provider: 'a', number: '12').label, 'Chapter 12');
      expect(const MChapter(id: 'a:1', provider: 'a', number: '3', title: 'The Gate').label, 'Chapter 3 · The Gate');
      expect(const MChapter(id: 'a:1', provider: 'a').label, 'Oneshot');
    });

    test('site-search friendly queries', () {
      expect(plainQuery('I’m the Max‑Level Newbie'), "I'm the Max-Level Newbie");
      expect(decodeEntities('Journey&#39;s End &amp; more'), "Journey's End & more");
      expect(norm('Re:ZERO -Starting Life-'), 'rezerostartinglife');
    });

    test('provider names fall back to the id', () {
      expect(providerName('mangadex'), 'MangaDex');
      expect(providerName('unknown'), 'unknown');
    });
  });
}
