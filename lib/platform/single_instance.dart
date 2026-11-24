/// 单实例：数据目录下的锁文件 + dart:io 独占文件锁（进程存活期持有）。
///
/// 三层保护：同进程静态标记、文件存在时间（陈旧锁可接管）、OS 独占锁。
/// 任一文件系统能力不可用时降级为“允许启动”，不让应用崩溃。
library;

import 'dart:async';
import 'dart:io';

const Duration kLockStaleAfter = Duration(minutes: 10);

class SingleInstanceLock {
  SingleInstanceLock._();

  static final Set<String> _held = <String>{};
  static RandomAccessFile? _handle;
  static File? _file;
  static Timer? _heartbeat;

  /// 成功持有锁返回 true；已有实例返回 false。
  static bool acquire(File file) {
    final key = file.absolute.path;
    if (_held.contains(key)) return false;

    try {
      final parent = file.parent;
      if (!parent.existsSync()) parent.createSync(recursive: true);

      if (file.existsSync()) {
        final age = DateTime.now().difference(file.statSync().modified);
        if (age < kLockStaleAfter) return false;
        file.deleteSync();
      }

      _handle = file.openSync(mode: FileMode.write);
      _handle!.lockSync(FileLock.exclusive);
      _file = file;
      _held.add(key);
      _touch();
      _heartbeat = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _touch(),
      );
      return true;
    } on Object {
      // 降级：锁文件不可用时允许启动（不让平台差异阻断应用）。
      _handle = null;
      _file = null;
      return true;
    }
  }

  /// 续期锁文件的修改时间，避免长会话被当作陈旧锁接管。
  static void _touch() {
    try {
      final handle = _handle;
      if (handle == null) return;
      handle.setPositionSync(0);
      handle.writeStringSync('$pid ${DateTime.now().millisecondsSinceEpoch}\n');
      handle.truncateSync(handle.positionSync());
    } on Object {
      // 续写失败不影响已持有的锁。
    }
  }

  static void release() {
    _heartbeat?.cancel();
    _heartbeat = null;
    try {
      _handle?.unlockSync();
    } on Object {
      // ignore
    }
    try {
      _handle?.closeSync();
    } on Object {
      // ignore
    }
    try {
      _file?.deleteSync();
    } on Object {
      // ignore
    }
    _handle = null;
    _file = null;
    _held.clear();
  }

  /// 供测试读取：当前是否持有某个路径的锁。
  static bool holds(File file) => _held.contains(file.absolute.path);
}
