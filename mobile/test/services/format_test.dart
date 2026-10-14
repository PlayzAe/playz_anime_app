import 'package:flutter_test/flutter_test.dart';
import 'package:playzanime/services/format.dart';

void main() {
  group('Format Utilities Unit Tests', () {
    test('Format.clock formats seconds into clock notation accurately', () {
      expect(Format.clock(0), '0:00');
      expect(Format.clock(45), '0:45');
      expect(Format.clock(65), '1:05');
      expect(Format.clock(245), '4:05');
      expect(Format.clock(1420), '23:40');
      expect(Format.clock(3665), '1:01:05');
      expect(Format.clock(7325), '2:02:05');

      // Edge cases: negative, infinite, NaN
      expect(Format.clock(-10), '0:00');
      expect(Format.clock(double.nan), '0:00');
      expect(Format.clock(double.infinity), '0:00');
    });

    test('Format.bytes formats byte counts into human-readable strings', () {
      expect(Format.bytes(0), '0 MB');
      expect(Format.bytes(1024), '1.0 KB');
      expect(Format.bytes(1048576), '1.0 MB');
      expect(Format.bytes(1073741824), '1.0 GB');
    });

    test('Format.relativeTime calculates human readable elapsed time', () {
      final now = 1700000000000;
      expect(Format.relativeTime(now - 30000, now), 'just now');
      expect(Format.relativeTime(now - 120000, now), '2 min ago');
      expect(Format.relativeTime(now - 7200000, now), '2 h ago');
      expect(Format.relativeTime(now - 90000000, now), 'yesterday');
    });
  });
}
