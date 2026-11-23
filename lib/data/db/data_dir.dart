import 'dart:io';

import 'package:path/path.dart' as p;

const String kDatabaseFileName = 'focusflow.sqlite3';
const String kDataDirEnv = 'FOCUSFLOW_DATA_DIR';

/// 对齐 src-tauri/src/lib.rs:30-53：
/// Windows 用 %APPDATA%\FocusFlow，macOS 用 ~/Library/Application Support/FocusFlow，
/// 支持 FOCUSFLOW_DATA_DIR / --user-data-dir= 覆盖（必须为绝对路径）。
Directory resolveDataDir({List<String>? args}) {
  final override = Platform.environment[kDataDirEnv];
  final cli = (args ?? const <String>[]).where(
    (arg) => arg.startsWith('--user-data-dir='),
  );
  final raw = override ??
      (cli.isEmpty ? null : cli.first.substring('--user-data-dir='.length));
  if (raw != null && raw.isNotEmpty) {
    final dir = Directory(raw);
    if (!dir.isAbsolute) {
      throw ArgumentError('自定义数据目录必须为绝对路径。');
    }
    return dir;
  }

  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) {
      throw StateError('无法定位系统数据目录。');
    }
    return Directory(p.join(appData, 'FocusFlow'));
  }
  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('无法定位系统数据目录。');
    }
    return Directory(p.join(home, 'Library', 'Application Support', 'FocusFlow'));
  }
  throw UnsupportedError('FocusFlow 仅支持 macOS 与 Windows。');
}

File resolveDatabaseFile({List<String>? args}) =>
    File(p.join(resolveDataDir(args: args).path, kDatabaseFileName));
