/// src-tauri/src/error.rs 的 Dart 对应：面向用户的错误带固定文案，
/// 对外统一以 `FF:<message>` 呈现（对应 Error::ipc）。
/// 继承 [ArgumentError]：校验类失败同时满足 Flutter 侧既有的 throwsArgumentError 断言。
class FocusFlowException extends ArgumentError implements Exception {
  FocusFlowException(String message) : _userMessage = message, super(null);

  final String _userMessage;

  @override
  String get message => _userMessage;

  String get userMessage => _userMessage;

  @override
  String toString() => 'FF:$_userMessage';
}

const String badInput = '输入格式或数值超出允许范围，请检查后重试。';
const String invalidBackup = '无法恢复此备份。请选择本应用导出的完整 JSON 文件。';
