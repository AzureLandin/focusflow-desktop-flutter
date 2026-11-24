/// 单实例：数据目录下的锁文件 + dart:io 独占文件锁（进程存活期持有）。
///
/// 判定链：同进程静态标记 → 锁内 pid 存活检测 → 文件年龄（陈旧接管）→ OS 独占锁。
/// pid 已死则立即接管（正常退出未清锁/崩溃后可马上重启）；检测手段不可用时
/// 回退到 10 分钟陈旧窗口。按路径各持一个句柄，任一文件系统能力不可用时
/// 降级为“允许启动”，不让应用崩溃。
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
        final info = _readLockInfo(file);
        if (info != null) {
          // pid 还活着：真有另一个实例（pid 被复用时宁可拒绝，行为不变）。
          if (_pidAlive(info.$1)) return false;
          // pid 已死：立即接管，不受 10 分钟窗口限制。
          file.deleteSync();
        } else {
          // 锁不可解析：回退到陈旧时间规则。
          final age = DateTime.now().difference(file.statSync().modified);
          if (age < kLockStaleAfter) return false;
          file.deleteSync();
        }
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

  /// 解析锁文件内容 `<pid> <毫秒时间戳>`；不可解析返回 null。
  static (int, int)? _readLockInfo(File file) {
    try {
      final parts = file.readAsStringSync().trim().split(RegExp(r'\s+'));
      if (parts.length != 2) return null;
      final pid = int.tryParse(parts[0]);
      final stamp = int.tryParse(parts[1]);
      if (pid == null || stamp == null || pid <= 0) return null;
      return (pid, stamp);
    } on Object {
      return null;
    }
  }

  /// pid 是否仍存活。POSIX 用 `kill -0`，Windows 用 `tasklist` 过滤；
  /// 检测手段不可用时保守视为存活（回退到陈旧时间规则）。
  static bool _pidAlive(int pid) {
    try {
      if (Platform.isWindows) {
        final result = Process.runSync(
          'tasklist',
          ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH'],
        );
        final out = result.stdout.toString();
        return !out.contains('No tasks') && out.contains('"$pid"');
      }
      return Process.runSync('kill', ['-0', '$pid']).exitCode == 0;
    } on Object {
      return true;
    }
  }
}
