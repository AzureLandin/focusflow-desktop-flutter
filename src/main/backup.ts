import { dateKey, settingsSchema } from '../shared/model';
import { Database, UserError } from './database';

const tables = ['tasks', 'daily_records', 'pomodoro_sessions', 'pomodoro_cycles', 'pomodoro_interruptions', 'thought_notes', 'app_settings'] as const;
type Table = typeof tables[number];
type Cell = string | number | null;
type Row = Record<string, Cell>;

export function exportBackup(db: Database) {
  return JSON.stringify({ format: 'focusflow-backup', version: 1,
    data: Object.fromEntries(tables.map((table) => [table, db.all(`SELECT * FROM ${table}`)])),
  }, null, 2);
}

function invalid(): never { throw new UserError('无法恢复此备份。请选择本应用导出的完整 JSON 文件。'); }

function validateRow(table: Table, row: Row, columns: string[]) {
  if (!row || typeof row !== 'object' || Array.isArray(row) || Object.keys(row).length !== columns.length) invalid();
  for (const column of columns) {
    const value = row[column];
    if (value !== null && typeof value !== 'string' && !Number.isSafeInteger(value)) invalid();
    if (['date', 'scheduled_date', 'local_date'].includes(column) && !dateKey.safeParse(value).success) invalid();
  }
  if (table === 'app_settings' && row.key === 'archive_origin' && !dateKey.safeParse(row.value).success) invalid();
  const preferences = table === 'app_settings' && row.key === 'preferences' ? row.value : undefined;
  const rules = table === 'pomodoro_sessions' ? row.rules : preferences;
  if (rules !== undefined && (typeof rules !== 'string' || !settingsSchema.safeParse(JSON.parse(rules)).success)) invalid();
}

export function restoreBackup(db: Database, raw: string) {
  try {
    const backup = JSON.parse(raw);
    if (backup?.format !== 'focusflow-backup' || backup.version !== 1 || !backup.data) invalid();
    const entries = tables.map((table) => {
      const columns = db.all<{ name: string }>(`PRAGMA table_info(${table})`).map(({ name }) => name);
      const rows: Row[] = backup.data[table];
      if (!Array.isArray(rows)) invalid();
      for (const row of rows) validateRow(table, row, columns);
      return { table, columns, rows };
    });
    db.transaction(() => {
      for (const table of [...tables].reverse()) db.run(`DELETE FROM ${table}`);
      for (const { table, columns, rows } of entries) {
        const placeholders = columns.map(() => '?').join(',');
        for (const row of rows) db.run(`INSERT INTO ${table} (${columns.join(',')}) VALUES (${placeholders})`, ...columns.map((column) => row[column]));
      }
      const inconsistent = db.get(`SELECT 1 FROM pomodoro_sessions s WHERE
        s.completed_pomodoros <> (SELECT COUNT(*) FROM pomodoro_cycles c WHERE c.session_id=s.id AND c.status='completed')
        OR (s.status='focus_running' AND EXISTS (SELECT 1 FROM pomodoro_cycles c WHERE c.session_id=s.id AND c.cycle_index=s.current_cycle))`);
      if (inconsistent) invalid();
    });
  } catch { invalid(); }
}
