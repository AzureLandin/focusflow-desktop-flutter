/// 校验离线生成的 chime.wav 符合 WebAudio 参数（44.1kHz / 单声道 / 16bit / 0.62s）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

void main() {
  test('assets/chime.wav 是合法的 PCM WAV', () {
    final file = File('assets/chime.wav');
    expect(file.existsSync(), isTrue, reason: '提示音资产必须提交入库');
    final bytes = file.readAsBytesSync();
    expect(bytes.length, greaterThan(44));

    final view = ByteData.sublistView(bytes);
    String ascii(int offset, int length) => String.fromCharCodes(
          bytes.getRange(offset, offset + length),
        );
    expect(ascii(0, 4), 'RIFF');
    expect(ascii(8, 4), 'WAVE');
    expect(ascii(12, 4), 'fmt ');
    expect(view.getUint16(20, Endian.little), 1); // PCM
    expect(view.getUint16(22, Endian.little), 1); // mono
    expect(view.getUint32(24, Endian.little), 44100);
    expect(view.getUint16(34, Endian.little), 16); // 16-bit
    expect(ascii(36, 4), 'data');

    final samples = view.getUint32(40, Endian.little) ~/ 2;
    expect(samples, (0.62 * 44100).round());
  });
}
