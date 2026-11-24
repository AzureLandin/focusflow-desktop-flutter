/// 单实例锁：纯 dart:io 测试占用分支、释放、陈旧锁接管。
library;

import 'dart:io';

import 'package:focusflow/platform/single_instance.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late File lock;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('focusflow-lock-test-');
    lock = File(p.join(dir.path, 'focusflow.lock'));
  });

  tearDown(() {
    SingleInstanceLock.release();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('首次获取锁成功，同进程再次获取被拒绝', () {
    expect(SingleInstanceLock.acquire(lock), isTrue);
    expect(SingleInstanceLock.holds(lock), isTrue);
    expect(SingleInstanceLock.acquire(lock), isFalse);
  });

  test('释放后可重新获取', () {
    expect(SingleInstanceLock.acquire(lock), isTrue);
    SingleInstanceLock.release();
    expect(SingleInstanceLock.holds(lock), isFalse);
    expect(lock.existsSync(), isFalse);
    expect(SingleInstanceLock.acquire(lock), isTrue);
  });

  test('陈旧锁文件可被接管', () {
    lock.writeAsStringSync('12345 0\n');
    final old = DateTime.now().subtract(kLockStaleAfter + const Duration(minutes: 1));
    lock.setLastModifiedSync(old);

    expect(SingleInstanceLock.acquire(lock), isTrue);
    expect(SingleInstanceLock.holds(lock), isTrue);
  });

  test('不同路径的锁互不干扰', () {
    final other = File(p.join(dir.path, 'other.lock'));
    expect(SingleInstanceLock.acquire(lock), isTrue);
    expect(SingleInstanceLock.acquire(other), isTrue);
    SingleInstanceLock.release();
    expect(SingleInstanceLock.holds(lock), isFalse);
    expect(SingleInstanceLock.holds(other), isFalse);
  });

  test('锁内 pid 已死时立即接管（不受 10 分钟窗口限制）', () {
    // 不可能存活的超大 pid；文件 mtime 是新鲜的。
    lock.writeAsStringSync('999999999 ${DateTime.now().millisecondsSinceEpoch}\n');
    expect(SingleInstanceLock.acquire(lock), isTrue);
    expect(SingleInstanceLock.holds(lock), isTrue);
  });

  test('锁内 pid 仍存活时拒绝启动', () {
    // 测试进程自身的 pid 一定存活。
    lock.writeAsStringSync('$pid ${DateTime.now().millisecondsSinceEpoch}\n');
    expect(SingleInstanceLock.acquire(lock), isFalse);
    expect(SingleInstanceLock.holds(lock), isFalse);
  });
}
