/// 备份文件对话框：接通 file_picker 13.x 与 backup.dart 的 v1 导出/导入。
/// 用户取消返回 false（不报错、不提示）；插件失败由上层 UI 转为 notice。
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../data/backup.dart';
import '../data/repository.dart';
import '../shared/dates.dart';

Future<bool> exportBackupWithDialog(Repository repository) async {
  final bytes = utf8.encode(await exportBackup(repository.db));
  final uri = await FilePicker.saveFile(
    dialogTitle: '导出 JSON 备份',
    fileName: 'focusflow-backup-${localDay()}.json',
    mimeType: 'application/json',
    bytes: bytes,
  );
  // 用户取消保存对话框：静默返回。
  return uri != null;
}

Future<bool> importBackupWithDialog(Repository repository) async {
  final files = await FilePicker.pickFiles(
    dialogTitle: '恢复 JSON 备份',
    type: FileType.custom,
    allowedExtensions: const <String>['json'],
  );
  if (files.isEmpty) return false;
  final path = files.first.path;
  if (path == null) return false;
  final data = await readFile(File(path));
  await restore(repository, data, nowMillis());
  return true;
}
