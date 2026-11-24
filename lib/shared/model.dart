/// 与 src/shared/model.ts / src-tauri/src/model.rs 对齐的 DTO、Settings 与命令模型。
/// 校验范围与错误文案逐项照搬原实现。
library;

import 'package:uuid/uuid.dart';

import 'dates.dart';
import 'errors.dart';

void checkId(String value) {
  if (value.length != 36 || !Uuid.isValidUUID(fromString: value)) {
    throw FocusFlowException(badInput);
  }
}

void checkPlan(int value) {
  if (value < 1 || value > 12) throw FocusFlowException(badInput);
}

extension DbRowX on Map<String, dynamic> {
  String s(String key) => this[key] as String;
  int i(String key) => this[key] as int;
  int? ni(String key) => this[key] as int?;
  String? ns(String key) => this[key] as String?;
}

/// src-tauri/src/model.rs:71-118（与 model.ts:20-30 一致）。
enum AppTheme { light, dark, system }

extension AppThemeKey on AppTheme {
  String get key => switch (this) {
        AppTheme.light => 'light',
        AppTheme.dark => 'dark',
        AppTheme.system => 'system',
      };

  static AppTheme fromKey(String key) => switch (key) {
        'light' => AppTheme.light,
        'dark' => AppTheme.dark,
        'system' => AppTheme.system,
        _ => throw FocusFlowException(badInput),
      };
}

class Settings {
  const Settings({
    required this.focusMinutes,
    required this.shortMinutes,
    required this.longMinutes,
    required this.longEvery,
    required this.sound,
    required this.notifications,
    required this.finalLongBreak,
    required this.theme,
  });

  static const Settings defaults = Settings(
    focusMinutes: 25,
    shortMinutes: 5,
    longMinutes: 15,
    longEvery: 4,
    sound: true,
    notifications: true,
    finalLongBreak: false,
    theme: AppTheme.system,
  );

  final int focusMinutes;
  final int shortMinutes;
  final int longMinutes;
  final int longEvery;
  final bool sound;
  final bool notifications;
  final bool finalLongBreak;
  final AppTheme theme;

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
        focusMinutes: (json['focusMinutes'] as num?)?.toInt() ??
            defaults.focusMinutes,
        shortMinutes: (json['shortMinutes'] as num?)?.toInt() ??
            defaults.shortMinutes,
        longMinutes:
            (json['longMinutes'] as num?)?.toInt() ?? defaults.longMinutes,
        longEvery: (json['longEvery'] as num?)?.toInt() ?? defaults.longEvery,
        sound: (json['sound'] as bool?) ?? defaults.sound,
        notifications:
            (json['notifications'] as bool?) ?? defaults.notifications,
        finalLongBreak:
            (json['finalLongBreak'] as bool?) ?? defaults.finalLongBreak,
        theme: AppThemeKey.fromKey((json['theme'] as String?) ?? 'system'),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'focusMinutes': focusMinutes,
        'shortMinutes': shortMinutes,
        'longMinutes': longMinutes,
        'longEvery': longEvery,
        'sound': sound,
        'notifications': notifications,
        'finalLongBreak': finalLongBreak,
        'theme': theme.key,
      };

  Settings copyWith({
    int? focusMinutes,
    int? shortMinutes,
    int? longMinutes,
    int? longEvery,
    bool? sound,
    bool? notifications,
    bool? finalLongBreak,
    AppTheme? theme,
  }) =>
      Settings(
        focusMinutes: focusMinutes ?? this.focusMinutes,
        shortMinutes: shortMinutes ?? this.shortMinutes,
        longMinutes: longMinutes ?? this.longMinutes,
        longEvery: longEvery ?? this.longEvery,
        sound: sound ?? this.sound,
        notifications: notifications ?? this.notifications,
        finalLongBreak: finalLongBreak ?? this.finalLongBreak,
        theme: theme ?? this.theme,
      );

  void validate() {
    if (!(focusMinutes >= 1 && focusMinutes <= 120) ||
        !(shortMinutes >= 1 && shortMinutes <= 60) ||
        !(longMinutes >= 15 && longMinutes <= 30) ||
        !(longEvery >= 1 && longEvery <= 12)) {
      throw FocusFlowException(badInput);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.focusMinutes == focusMinutes &&
      other.shortMinutes == shortMinutes &&
      other.longMinutes == longMinutes &&
      other.longEvery == longEvery &&
      other.sound == sound &&
      other.notifications == notifications &&
      other.finalLongBreak == finalLongBreak &&
      other.theme == theme;

  @override
  int get hashCode => Object.hash(focusMinutes, shortMinutes, longMinutes,
      longEvery, sound, notifications, finalLongBreak, theme);

  @override
  String toString() => 'Settings($toJson)';
}

class TaskInput {
  const TaskInput({
    required this.title,
    required this.description,
    required this.scheduledDate,
    required this.pomodoroEnabled,
    required this.plannedPomodoros,
  });

  final String title;
  final String description;
  final String scheduledDate;
  final bool pomodoroEnabled;
  final int plannedPomodoros;

  /// 对齐 Command::SaveTask 的校验：清理文本、校验日期与计划数。
  TaskInput validated() {
    final result = TaskInput(
      title: cleanText(title, 1, 200),
      description: cleanText(description, 0, 2000),
      scheduledDate: parseDate(scheduledDate),
      pomodoroEnabled: pomodoroEnabled,
      plannedPomodoros: plannedPomodoros,
    );
    checkPlan(result.plannedPomodoros);
    return result;
  }
}

class Task {
  const Task({
    required this.id,
    required this.title,
    required this.description,
    required this.scheduledDate,
    required this.status,
    required this.pomodoroEnabled,
    required this.plannedPomodoros,
    required this.completedPomodoros,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.deletedAt,
  });

  factory Task.fromRow(Map<String, dynamic> r) => Task(
        id: r.s('id'),
        title: r.s('title'),
        description: r.s('description'),
        scheduledDate: r.s('scheduled_date'),
        status: r.s('status'),
        pomodoroEnabled: r.i('pomodoro_enabled'),
        plannedPomodoros: r.i('planned_pomodoros'),
        completedPomodoros: r.i('completed_pomodoros'),
        sortOrder: r.i('sort_order'),
        createdAt: r.i('created_at'),
        updatedAt: r.i('updated_at'),
        completedAt: r.ni('completed_at'),
        deletedAt: r.ni('deleted_at'),
      );

  final String id;
  final String title;
  final String description;
  final String scheduledDate;
  final String status;
  final int pomodoroEnabled;
  final int plannedPomodoros;
  final int completedPomodoros;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;
  final int? completedAt;
  final int? deletedAt;
}

class Thought {
  const Thought({
    required this.id,
    required this.localDate,
    required this.sessionId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Thought.fromRow(Map<String, dynamic> r) => Thought(
        id: r.s('id'),
        localDate: r.s('local_date'),
        sessionId: r.ns('session_id'),
        content: r.s('content'),
        createdAt: r.i('created_at'),
        updatedAt: r.i('updated_at'),
      );

  final String id;
  final String localDate;
  final String? sessionId;
  final String content;
  final int createdAt;
  final int updatedAt;
}

class Activity {
  const Activity({
    required this.id,
    required this.title,
    required this.cycleIndex,
    required this.reason,
    required this.endedAt,
    required this.focusSeconds,
  });

  factory Activity.fromRow(Map<String, dynamic> r) => Activity(
        id: r.s('id'),
        title: r.s('title'),
        cycleIndex: r.i('cycle_index'),
        reason: r.ns('reason'),
        endedAt: r.i('ended_at'),
        focusSeconds: r.i('focus_seconds'),
      );

  final String id;
  final String title;
  final int cycleIndex;
  final String? reason;
  final int endedAt;
  final int focusSeconds;
}

class DayRecord {
  const DayRecord({
    required this.date,
    required this.finalizedAt,
    required this.totalTasks,
    required this.completedTasks,
    required this.unfinishedTasks,
    required this.totalCompletedPomodoros,
    required this.totalFocusSeconds,
  });

  factory DayRecord.fromRow(Map<String, dynamic> r) => DayRecord(
        date: r.s('date'),
        finalizedAt: r.ni('finalized_at'),
        totalTasks: r.i('total_tasks'),
        completedTasks: r.i('completed_tasks'),
        unfinishedTasks: r.i('unfinished_tasks'),
        totalCompletedPomodoros: r.i('total_completed_pomodoros'),
        totalFocusSeconds: r.i('total_focus_seconds'),
      );

  final String date;
  final int? finalizedAt;
  final int totalTasks;
  final int completedTasks;
  final int unfinishedTasks;
  final int totalCompletedPomodoros;
  final int totalFocusSeconds;
}

class Session {
  const Session({
    required this.id,
    required this.taskId,
    required this.taskTitleSnapshot,
    required this.plannedPomodoros,
    required this.completedPomodoros,
    required this.currentCycle,
    required this.currentPhase,
    required this.status,
    required this.phaseStartedAt,
    required this.phaseEndsAt,
    required this.startedAt,
    required this.finishedAt,
    required this.rules,
    required this.endingBreak,
  });

  factory Session.fromRow(Map<String, dynamic> r) => Session(
        id: r.s('id'),
        taskId: r.ns('task_id'),
        taskTitleSnapshot: r.s('task_title_snapshot'),
        plannedPomodoros: r.i('planned_pomodoros'),
        completedPomodoros: r.i('completed_pomodoros'),
        currentCycle: r.i('current_cycle'),
        currentPhase: r.s('current_phase'),
        status: r.s('status'),
        phaseStartedAt: r.i('phase_started_at'),
        phaseEndsAt: r.i('phase_ends_at'),
        startedAt: r.i('started_at'),
        finishedAt: r.ni('finished_at'),
        rules: r.s('rules'),
        endingBreak: r.i('ending_break'),
      );

  final String id;
  final String? taskId;
  final String taskTitleSnapshot;
  final int plannedPomodoros;
  final int completedPomodoros;
  final int currentCycle;
  final String currentPhase;
  final String status;
  final int phaseStartedAt;
  final int phaseEndsAt;
  final int startedAt;
  final int? finishedAt;
  final String rules;
  final int endingBreak;
}

class ActiveSession {
  const ActiveSession({
    required this.session,
    required this.nextBreak,
    required this.focusSeconds,
    required this.thoughtCount,
    required this.canConfirm,
  });

  final Session session;
  final String? nextBreak;
  final int focusSeconds;
  final int thoughtCount;
  final bool canConfirm;

  String get id => session.id;
  String? get taskId => session.taskId;
  String get status => session.status;
  String get currentPhase => session.currentPhase;
  int get completedPomodoros => session.completedPomodoros;
  int get currentCycle => session.currentCycle;
  int get plannedPomodoros => session.plannedPomodoros;
  int get phaseStartedAt => session.phaseStartedAt;
  int get phaseEndsAt => session.phaseEndsAt;
  int get endingBreak => session.endingBreak;
}

class DayData {
  const DayData({
    required this.tasks,
    required this.thoughts,
    required this.record,
    required this.activity,
  });

  final List<Task> tasks;
  final List<Thought> thoughts;
  final DayRecord record;
  final List<Activity> activity;
}

class Pulse {
  const Pulse({
    required this.now,
    required this.today,
    required this.session,
  });

  final int now;
  final String today;
  final ActiveSession? session;

  Pulse copyWith({
    int? now,
    String? today,
    ActiveSession? session,
    bool clearSession = false,
  }) =>
      Pulse(
        now: now ?? this.now,
        today: today ?? this.today,
        session: clearSession ? null : (session ?? this.session),
      );
}

class Workspace {
  const Workspace({
    required this.pulse,
    required this.todayData,
    required this.selectedData,
    required this.calendar,
    required this.settings,
    required this.dataPath,
  });

  final Pulse pulse;
  final DayData todayData;
  final DayData selectedData;
  final List<DayRecord> calendar;
  final Settings settings;
  final String dataPath;

  Workspace copyWith({
    Pulse? pulse,
    DayData? todayData,
    DayData? selectedData,
    List<DayRecord>? calendar,
    Settings? settings,
    String? dataPath,
  }) =>
      Workspace(
        pulse: pulse ?? this.pulse,
        todayData: todayData ?? this.todayData,
        selectedData: selectedData ?? this.selectedData,
        calendar: calendar ?? this.calendar,
        settings: settings ?? this.settings,
        dataPath: dataPath ?? this.dataPath,
      );
}

class Query {
  const Query({this.day, this.month});

  final String? day;
  final String? month;
}

class TimerEvent {
  const TimerEvent({
    required this.message,
    required this.sound,
    required this.notify,
  });

  final String message;
  final bool sound;
  final bool notify;
}

/// src-tauri/src/model.rs:141-261 的 13 种命令。
sealed class Command {
  const Command();

  bool get requiresIdle => switch (this) {
        SaveTask() ||
        ToggleTask() ||
        DeleteTask() ||
        MoveTask() ||
        Start() ||
        SaveInterruptedQuick() ||
        SettingsCommand() =>
          true,
        _ => false,
      };

  /// 返回清理/校验后的新实例；失败抛 [FocusFlowException]。
  Command validate();
}

class SaveTask extends Command {
  const SaveTask({this.id, required this.task});

  final String? id;
  final TaskInput task;

  @override
  Command validate() {
    if (id != null) checkId(id!);
    return SaveTask(id: id, task: task.validated());
  }
}

class ToggleTask extends Command {
  const ToggleTask({required this.id});
  final String id;
  @override
  Command validate() {
    checkId(id);
    return this;
  }
}

class DeleteTask extends Command {
  const DeleteTask({required this.id});
  final String id;
  @override
  Command validate() {
    checkId(id);
    return this;
  }
}

class MoveTask extends Command {
  const MoveTask({required this.id, required this.direction});
  final String id;
  final int direction;
  @override
  Command validate() {
    checkId(id);
    if (direction != -1 && direction != 1) {
      throw FocusFlowException(badInput);
    }
    return this;
  }
}

class SaveThought extends Command {
  const SaveThought({this.id, required this.content});
  final String? id;
  final String content;
  @override
  Command validate() {
    if (id != null) checkId(id!);
    return SaveThought(id: id, content: cleanText(content, 1, 2000));
  }
}

class DeleteThought extends Command {
  const DeleteThought({required this.id});
  final String id;
  @override
  Command validate() {
    checkId(id);
    return this;
  }
}

class Start extends Command {
  const Start({this.taskId, this.title, required this.count});
  final String? taskId;
  final String? title;
  final int count;
  @override
  Command validate() {
    if (taskId != null) checkId(taskId!);
    final cleanTitle = title == null ? null : cleanText(title!, 1, 200);
    if (count < 1 || count > 12) {
      throw FocusFlowException(badInput);
    }
    return Start(taskId: taskId, title: cleanTitle, count: count);
  }
}

class Advance extends Command {
  const Advance({required this.id});
  final String id;
  @override
  Command validate() {
    checkId(id);
    return this;
  }
}

class Interrupt extends Command {
  const Interrupt({required this.id, required this.reason});
  final String id;
  final String reason;
  @override
  Command validate() {
    checkId(id);
    return Interrupt(id: id, reason: cleanText(reason, 1, 500));
  }
}

class SaveInterruptedQuick extends Command {
  const SaveInterruptedQuick({required this.id});
  final String id;
  @override
  Command validate() {
    checkId(id);
    return this;
  }
}

class EndSession extends Command {
  const EndSession({required this.id});
  final String id;
  @override
  Command validate() {
    checkId(id);
    return this;
  }
}

class Resolve extends Command {
  const Resolve({
    required this.id,
    required this.completed,
    this.saveQuick = false,
  });
  final String id;
  final bool completed;
  final bool saveQuick;
  @override
  Command validate() {
    checkId(id);
    return this;
  }
}

class SettingsCommand extends Command {
  const SettingsCommand({required this.settings});
  final Settings settings;
  @override
  Command validate() {
    settings.validate();
    return this;
  }
}

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
