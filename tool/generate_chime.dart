/// 离线合成提示音，对齐 src/renderer/index.tsx:27-42 的 playChime：
///   660Hz @ t=0.00s、880Hz @ t=0.16s，各持续 0.46s；
///   指数增益包络 0.001 → 0.12（0.04s）→ 0.001（0.45s）。
/// 运行：dart run tool/generate_chime.dart
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 44100;
const double attackSeconds = 0.04;
const double releaseEndSeconds = 0.45;
const double toneSeconds = 0.46;
const double peak = 0.12;
const double floorGain = 0.001;

const List<({double frequency, double delay})> tones = [
  (frequency: 660, delay: 0.0),
  (frequency: 880, delay: 0.16),
];

/// WebAudio exponentialRampToValueAtTime 的指数插值。
double _ramp(double from, double to, double progress) =>
    from * math.pow(to / from, progress.clamp(0.0, 1.0)).toDouble();

double _envelope(double local) {
  if (local < 0 || local > toneSeconds) return 0;
  if (local <= attackSeconds) {
    return _ramp(floorGain, peak, local / attackSeconds);
  }
  if (local <= releaseEndSeconds) {
    return _ramp(
      peak,
      floorGain,
      (local - attackSeconds) / (releaseEndSeconds - attackSeconds),
    );
  }
  return floorGain;
}

Uint8List _pcm16(List<double> samples) {
  final bytes = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    view.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
  }
  return bytes;
}

Uint8List _wav(Uint8List pcm) {
  final header = ByteData(44);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      header.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // PCM chunk size
  header.setUint16(20, 1, Endian.little); // PCM format
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);

  return Uint8List.fromList([...header.buffer.asUint8List(), ...pcm]);
}

void main() {
  const totalSeconds = 0.16 + toneSeconds;
  final length = (sampleRate * totalSeconds).round();
  final samples = List<double>.filled(length, 0);
  for (var i = 0; i < length; i++) {
    final t = i / sampleRate;
    var value = 0.0;
    for (final tone in tones) {
      final local = t - tone.delay;
      if (local < 0 || local > toneSeconds) continue;
      value += math.sin(2 * math.pi * tone.frequency * local) * _envelope(local);
    }
    samples[i] = value;
  }

  final output = File('assets/chime.wav');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(_wav(_pcm16(samples)));
  // ignore: avoid_print
  print('Wrote ${output.path} ($length samples, ${totalSeconds}s, 44.1kHz mono)');
}
