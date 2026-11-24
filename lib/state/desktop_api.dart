/// UI 与领域层之间的窄接口。真实实现包一层 Repository；
/// widget 测试用内存替身实现同一语义（见 test/ui/fake_desktop_api.dart）。
library;

import '../data/repository.dart';
import '../shared/model.dart';

abstract class DesktopApi {
  Future<Workspace> read(Query query);

  /// 心跳：先 sync（可能推进阶段），再取 pulse。
  Future<PulseResult> pulse();

  Future<void> run(Command command);

  /// 'export' / 'import'；文件对话框属于步骤 6，此处只保留 hook。
  Future<bool> backup(String action);

  Future<void> dispose();
}

class PulseResult {
  const PulseResult({required this.pulse, required this.event});

  final Pulse pulse;
  final TimerEvent? event;
}

class RepositoryDesktopApi implements DesktopApi {
  RepositoryDesktopApi(this._repository, {this.backupHandler});

  final Repository _repository;
  final Future<bool> Function(String action)? backupHandler;

  @override
  Future<Workspace> read(Query query) => _repository.read(query);

  @override
  Future<PulseResult> pulse() async {
    final event = await _repository.sync();
    final pulse = await _repository.pulse();
    return PulseResult(pulse: pulse, event: event);
  }

  @override
  Future<void> run(Command command) => _repository.run(command);

  @override
  Future<bool> backup(String action) async {
    final handler = backupHandler;
    return handler == null ? false : handler(action);
  }

  @override
  Future<void> dispose() => _repository.close();
}
