/// 与 src/shared/model.ts 对齐的共享枚举与 DTO 骨架。
/// 第 3 步会在此补齐 Task / Session / Workspace 等完整类型。
library;

enum Phase { focus, shortBreak, longBreak }

enum SessionState {
  focusRunning,
  focusElapsed,
  shortBreakRunning,
  longBreakRunning,
  breakElapsed,
  sessionCompleted,
  interrupted,
  completed,
}

enum TaskStatus { todo, inProgress, completed, unfinished }

String phaseKey(Phase phase) => switch (phase) {
      Phase.focus => 'focus',
      Phase.shortBreak => 'short_break',
      Phase.longBreak => 'long_break',
    };

String sessionStateKey(SessionState state) => switch (state) {
      SessionState.focusRunning => 'focus_running',
      SessionState.focusElapsed => 'focus_elapsed',
      SessionState.shortBreakRunning => 'short_break_running',
      SessionState.longBreakRunning => 'long_break_running',
      SessionState.breakElapsed => 'break_elapsed',
      SessionState.sessionCompleted => 'session_completed',
      SessionState.interrupted => 'interrupted',
      SessionState.completed => 'completed',
    };

String taskStatusKey(TaskStatus status) => switch (status) {
      TaskStatus.todo => 'todo',
      TaskStatus.inProgress => 'in_progress',
      TaskStatus.completed => 'completed',
      TaskStatus.unfinished => 'unfinished',
    };
