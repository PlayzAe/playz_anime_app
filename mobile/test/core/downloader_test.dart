import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:playzanime/services/downloader.dart';
import 'package:pointycastle/export.dart';

void main() {
  group('parseMediaPlaylist', () {
    test('resolves relative segments and carries the AES key', () {
      const m3u8 = '''#EXTM3U
#EXT-X-MEDIA-SEQUENCE:5
#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x000102030405060708090a0b0c0d0e0f
#EXTINF:4.0,
seg5.ts
#EXTINF:4.0,
https://cdn.example/abs/seg6.ts
#EXT-X-ENDLIST''';
      final p = parseMediaPlaylist(m3u8, 'https://host.example/hls/index.m3u8');
      expect(p.segments.length, 2);
      expect(p.segments.first.url, 'https://host.example/hls/seg5.ts');
      expect(p.segments.last.url, 'https://cdn.example/abs/seg6.ts');
      expect(p.segments.first.key?.method, 'AES-128');
      expect(p.segments.first.key?.uri, 'https://host.example/hls/key.bin');
      expect(p.segments.first.key?.iv?.length, 16);
    });
  });

  test('decryptAes128 reverses AES-128-CBC with PKCS7', () {
    final key = Uint8List.fromList(List.generate(16, (i) => i));
    final iv = Uint8List.fromList(List.generate(16, (i) => 15 - i));
    final plain = Uint8List.fromList(List.generate(400, (i) => i % 251));
    final enc = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(true, PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), iv), null));
    final cipher = enc.process(plain);
    expect(decryptAes128(cipher, key, iv), plain);
  });

  test('alignTs drops junk before the first 0x47 sync byte', () {
    final ts = Uint8List(188 * 4);
    for (var i = 0; i < ts.length; i += 188) {
      ts[i] = 0x47;
    }
    final junk = Uint8List.fromList([1, 2, 3, ...ts]);
    final out = alignTs(junk);
    expect(out.first, 0x47);
    expect(out.length, ts.length);
  });
}
