/// 平台能力入口：提示音与系统通知。
/// 所有插件调用都吞掉异常——能力缺失时静默降级，绝不让应用崩溃。
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:local_notifier/local_notifier.dart';

class ChimePlayer {
  ChimePlayer._();

  static AudioPlayer? _player;
  static bool _ready = false;

  static Future<void> prime() async {
    if (_ready) return;
    try {
      _player ??= AudioPlayer();
      await _player!.setSource(AssetSource('chime.wav'));
      await _player!.setVolume(1);
      _ready = true;
    } on Object {
      // 插件/资产不可用：关闭能力，后续调用直接返回。
      _player = null;
      _ready = false;
    }
  }

  /// 对齐 WebAudio：每次阶段结束都从头播放提示音。
  static void play() {
    unawaited(() async {
      try {
        await prime();
        final player = _player;
        if (player == null) return;
        await player.stop();
        await player.play(AssetSource('chime.wav'));
      } on Object {
        // 静默降级。
      }
    }());
  }
}

class SystemNotifier {
  SystemNotifier._();

  static bool _ready = false;

  static Future<void> prime() async {
    if (_ready) return;
    try {
      await localNotifier.setup(appName: 'FocusFlow');
      _ready = true;
    } on Object {
      _ready = false;
    }
  }

  /// 系统通知不依赖窗口是否聚焦，与 tauri-plugin-notification 行为一致。
  static void show(String message) {
    unawaited(() async {
      try {
        await prime();
        if (!_ready) return;
        await LocalNotification(title: 'FocusFlow', body: message).show();
      } on Object {
        // 静默降级。
      }
    }());
  }
}
