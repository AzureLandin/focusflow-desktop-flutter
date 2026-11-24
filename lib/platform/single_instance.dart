/// 单实例：数据目录下的锁文件 + dart:io 独占文件锁（进程存活期持有）。
///
/// 三层保护：同进程静态标记、文件存在时间（陈旧锁可接管）、OS 独占锁。
/// 按路径各持一个句柄（不同数据目录的应用实例互不干扰）。
/// 任一文件系统能力不可用时降级为“允许启动”，不让应用崩溃。
library;

import 'dart:async';
import 'dart:io';

const Duration kLockStaleAfter = Duration(minutes: 10);

class SingleInstanceLock {
  SingleInstanceLock._();

  /// path -> 持有中的独占句柄（多路径并存，释放时全部关闭）。
  static final Map<String, RandomAccessFile> _handles = <String, RandomAccessFile>{};
  static final Map<String, File> _files = <String, File>{};
  static Timer? _heartbeat;

  /// 成功持有锁返回 true；已有实例返回 false。
  static bool acquire(File file) {
    final key = file.absolute.path;
    if (_handles.containsKey(key)) return false;

    RandomAccessFile? handle;
    try {
      final parent = file.parent;
      if (!parent.existsSync()) parent.createSync(recursive: true);

      if (file.existsSync()) {
        final age = DateTime.now().difference(file.statSync().modified);
        if (age < kLockStaleAfter) return false;
        file.deleteSync();
      }

      handle = file.openSync(mode: FileMode.write);
      handle.lockSync(FileLock.exclusive);
      _handles[key] = handle;
      _files[key] = file;
      _touch(key);
      _heartbeat ??= Timer.periodic(
        const Duration(minutes: 1),
        (_) {
          for (final path in _handles.keys.toList()) {
            _touch(path);
          }
        },
      );
      return true;
    } on Object {
      // 降级：锁文件不可用时允许启动（不让平台差异阻断应用）。
      // 未登记的半开句柄必须关闭，否则 Windows 上会一直占用文件。
      try {
        if (!_handles.containsKey(key)) handle?.closeSync();
      } on Object {
        // ignore
      }
      return true;
    }
  }

  /// 续期锁文件的修改时间，避免长会话被当作陈旧锁接管。
  static void _touch(String key) {
    try {
      final handle = _handles[key];
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
    for (final key in _handles.keys.toList()) {
      final handle = _handles[key];
      final file = _files[key];
      try {
        handle?.unlockSync();
      } on Object {
        // ignore
      }
      try {
        handle?.closeSync();
      } on Object {
        // ignore
      }
      try {
        file?.deleteSync();
      } on Object {
        // ignore
      }
    }
    _handles.clear();
    _files.clear();
  }

  /// 供测试读取：当前是否持有某个路径的锁。
  static bool holds(File file) => _handles.containsKey(file.absolute.path);
}
