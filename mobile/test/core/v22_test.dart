import 'package:flutter_test/flutter_test.dart';
import 'package:playzanime/models/local.dart';
import 'package:playzanime/models/media.dart';
import 'package:playzanime/services/settings_file.dart';
import 'package:playzanime/sources/ani/episodes.dart';
import 'package:playzanime/sources/manga/extensions.dart';
import 'package:playzanime/views/download_sheet.dart' show estimateBytes, sizeLabel;
import 'package:playzanime/views/reader_view.dart' show ReadMode;

void main() {
  group('extension repo', () {
    test('reads a v2 index with apk url, version code and content warning', () {
      final list = parseRepo({
        'extensionList': {
          'extensions': [
            {
              'name': 'Tachiyomi: Asura Scans',
              'packageName': 'eu.kanade.tachiyomi.extension.en.asurascans',
              'resources': {'apkUrl': 'https://x/asura.apk', 'iconUrl': 'https://x/i.png'},
              'versionCode': '106069',
              'versionName': '1.6.69',
              'contentWarning': 'CONTENT_WARNING_SAFE',
              'sources': [
                {'id': '123', 'name': 'Asura Scans', 'language': 'en', 'homeUrl': 'https://asuracomic.net'},
              ],
            },
            {
              'name': 'Spicy',
              'packageName': 'eu.kanade.tachiyomi.extension.all.spicy',
              'resources': {'apkUrl': 'https://x/s.apk'},
              'versionCode': '1',
              'contentWarning': 'CONTENT_WARNING_NSFW',
              'sources': [],
            },
            {
              'name': 'No apk',
              'packageName': 'x.y',
              'sources': [],
            },
          ],
        },
      }, 'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json');
      expect(list.length, 2);
      expect(list.first.name, 'Asura Scans');
      expect(list.first.apkUrl, 'https://x/asura.apk');
      expect(list.first.versionCode, 106069);
      expect(list.first.lang, 'en');
      expect(list.first.nsfw, isFalse);
      expect(list.last.nsfw, isTrue);
      expect(list.last.lang, 'all');
    });

    test('builds apk urls for legacy index.min.json entries', () {
      final list = parseRepo([
        {'name': 'Old', 'pkg': 'eu.kanade.tachiyomi.extension.en.old', 'apk': 'old-v1.4.1.apk', 'code': 7, 'version': '1.4.1', 'nsfw': 0, 'sources': []},
      ], 'https://example.com/repo/index.min.json');
      expect(list.single.apkUrl, 'https://example.com/repo/apk/old-v1.4.1.apk');
      expect(list.single.icon, 'https://example.com/repo/icon/eu.kanade.tachiyomi.extension.en.old.png');
      expect(list.single.versionCode, 7);
    });

    test('chapter numbers come from Mihon, else from the name', () {
      expect(chapterNumber(12, 'whatever'), '12');
      expect(chapterNumber(12.5, 'whatever'), '12.5');
      expect(chapterNumber(-1, 'Chapter 45 - The Gate'), '45');
      expect(chapterNumber(-1, 'Vol.2 Ch.10.5'), '10.5');
      expect(chapterNumber(null, 'Oneshot'), isNull);
    });
  });

  group('settings.ini', () {
    test('round-trips and never writes private values', () {
      const s = Settings(accent: 'ai', readMode: 'pagedRtl', subSize: 1.3, cloudflareCookie: 'secret', downloadDir: '/sdcard/x');
      final text = SettingsFile.encode(s);
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('/sdcard/x')));
      final back = SettingsFile.merge(const Settings(downloadDir: '/keep'), SettingsFile.decode(text));
      expect(back.accent, 'ai');
      expect(back.readMode, 'pagedRtl');
      expect(back.subSize, closeTo(1.3, 0.001));
      expect(back.downloadDir, '/keep');
    });

    test('old reader settings migrate to the new reading modes', () {
      expect(Settings.fromJson({'readerMode': 'paged', 'readerDirection': 'ltr'}).readMode, 'pagedLtr');
      expect(Settings.fromJson({'readerMode': 'paged'}).readMode, 'pagedRtl');
      expect(Settings.fromJson({}).readMode, 'strip');
      expect(ReadMode.parse('nonsense'), ReadMode.strip);
      expect(ReadMode.parse('stripGaps').isStrip, isTrue);
    });

    test('new fields default sensibly', () {
      final s = Settings.fromJson({});
      expect(s.seekSeconds, 5);
      expect(s.downloadQuality, QualityPref.q720);
      expect(s.autoRotate, isTrue);
      expect(Settings.fromJson(s.toJson()).downloadQuality, QualityPref.q720);
    });
  });

  group('anime', () {
    test('spots MegaPlay error pages', () {
      expect(isMegaplayError('<html><head><title>Error - MegaPlay</title>'), isTrue);
      expect(isMegaplayError('<title>Frieren E1 - MegaPlay</title>'), isFalse);
    });

    test('download sizes shrink with quality', () {
      final sizes = [QualityPref.q1080, QualityPref.q720, QualityPref.q480, QualityPref.q360].map((q) => estimateBytes(q)).toList();
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], lessThan(sizes[i - 1]));
      }
      expect(sizeLabel(estimateBytes(QualityPref.q1080)), endsWith('MB'));
      expect(sizeLabel(3 << 30), '3.0 GB');
    });
  });

  test('reading titles know if they are manga, manhwa or manhua', () {
    expect(MediaSnapshot(id: 1, title: 'a', type: MediaType.manga, country: 'KR').kind, 'Manhwa');
    expect(MediaSnapshot(id: 1, title: 'a', type: MediaType.manga, country: 'CN').kind, 'Manhua');
    expect(MediaSnapshot(id: 1, title: 'a', type: MediaType.manga, country: 'JP').kind, 'Manga');
    expect(MediaSnapshot(id: 1, title: 'a').kind, 'Anime');
    expect(MediaSnapshot.fromJson(MediaSnapshot(id: 2, title: 'b', type: MediaType.manga, country: 'KR').toJson()).kind, 'Manhwa');
  });
}
