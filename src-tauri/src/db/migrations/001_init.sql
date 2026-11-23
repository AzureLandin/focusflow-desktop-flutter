CREATE TABLE tasks (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL CHECK(length(title) BETWEEN 1 AND 200),
  description TEXT NOT NULL DEFAULT '',
  scheduled_date TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('todo','in_progress','completed','unfinished')),
  pomodoro_enabled INTEGER NOT NULL CHECK(pomodoro_enabled IN (0,1)),
  planned_pomodoros INTEGER NOT NULL CHECK(planned_pomodoros BETWEEN 1 AND 12),
  completed_pomodoros INTEGER NOT NULL DEFAULT 0 CHECK(completed_pomodoros >= 0),
  sort_order INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  completed_at INTEGER,
  deleted_at INTEGER
) STRICT;
CREATE INDEX tasks_by_date ON tasks(scheduled_date, sort_order) WHERE deleted_at IS NULL;

CREATE TABLE daily_records (
  date TEXT PRIMARY KEY NOT NULL,
  finalized_at INTEGER,
  total_tasks INTEGER NOT NULL,
  completed_tasks INTEGER NOT NULL,
  unfinished_tasks INTEGER NOT NULL,
  total_completed_pomodoros INTEGER NOT NULL,
  total_focus_seconds INTEGER NOT NULL
) STRICT;

CREATE TABLE pomodoro_sessions (
  id TEXT PRIMARY KEY NOT NULL,
  task_id TEXT REFERENCES tasks(id),
  task_title_snapshot TEXT NOT NULL,
  planned_pomodoros INTEGER NOT NULL CHECK(planned_pomodoros BETWEEN 1 AND 12),
  completed_pomodoros INTEGER NOT NULL DEFAULT 0 CHECK(completed_pomodoros BETWEEN 0 AND planned_pomodoros),
  current_cycle INTEGER NOT NULL CHECK(current_cycle BETWEEN 1 AND planned_pomodoros),
  current_phase TEXT NOT NULL CHECK(current_phase IN ('focus','short_break','long_break')),
  status TEXT NOT NULL CHECK(status IN ('focus_running','focus_elapsed','short_break_running','long_break_running','break_elapsed','session_completed','interrupted','completed')),
  phase_started_at INTEGER NOT NULL,
  phase_ends_at INTEGER NOT NULL CHECK(phase_ends_at >= phase_started_at),
  started_at INTEGER NOT NULL,
  finished_at INTEGER,
  rules TEXT NOT NULL,
  ending_break INTEGER NOT NULL DEFAULT 0 CHECK(ending_break IN (0,1))
) STRICT;
CREATE UNIQUE INDEX one_active_session ON pomodoro_sessions((1)) WHERE status NOT IN ('interrupted','completed');

CREATE TABLE pomodoro_cycles (
  id TEXT PRIMARY KEY NOT NULL,
  session_id TEXT NOT NULL REFERENCES pomodoro_sessions(id),
  cycle_index INTEGER NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('completed','interrupted')),
  started_at INTEGER NOT NULL,
  ended_at INTEGER NOT NULL CHECK(ended_at >= started_at),
  local_date TEXT NOT NULL,
  focus_seconds INTEGER NOT NULL CHECK(focus_seconds >= 0),
  UNIQUE(session_id, cycle_index),
  UNIQUE(id, session_id)
) STRICT;
CREATE INDEX cycles_by_date ON pomodoro_cycles(local_date, status);

CREATE TABLE pomodoro_interruptions (
  id TEXT PRIMARY KEY NOT NULL,
  session_id TEXT NOT NULL REFERENCES pomodoro_sessions(id),
  cycle_id TEXT NOT NULL UNIQUE,
  reason TEXT NOT NULL CHECK(length(trim(reason)) BETWEEN 1 AND 500),
  occurred_at INTEGER NOT NULL,
  FOREIGN KEY (cycle_id, session_id) REFERENCES pomodoro_cycles(id, session_id)
) STRICT;

CREATE TABLE thought_notes (
  id TEXT PRIMARY KEY NOT NULL,
  local_date TEXT NOT NULL,
  session_id TEXT REFERENCES pomodoro_sessions(id),
  content TEXT NOT NULL CHECK(length(trim(content)) BETWEEN 1 AND 2000),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
) STRICT;
CREATE INDEX thoughts_by_date ON thought_notes(local_date, created_at);
CREATE INDEX thoughts_by_session ON thought_notes(session_id);

CREATE TABLE app_settings (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
) STRICT;
