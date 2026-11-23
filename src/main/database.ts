import { DatabaseSync, type SQLInputValue } from 'node:sqlite';
import migration001 from './migration-001.sql';

const migrations = [migration001];

export class Database {
  private connection: DatabaseSync;

  constructor(path: string) {
    this.connection = new DatabaseSync(path);
    try {
      this.connection.exec('PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=3000;');
      this.transaction(() => {
        const version = this.get<{ user_version: number }>('PRAGMA user_version')!.user_version;
        if (version > migrations.length) throw new Error('数据库来自较新的 FocusFlow 版本。请使用新版打开。');
        for (let index = version; index < migrations.length; index++) {
          this.connection.exec(migrations[index]);
          this.connection.exec(`PRAGMA user_version=${index + 1}`);
        }
      });
    } catch (error) {
      this.connection.close();
      throw error;
    }
  }

  get<T>(sql: string, ...values: SQLInputValue[]) {
    return this.connection.prepare(sql).get(...values) as T | undefined;
  }
  all<T>(sql: string, ...values: SQLInputValue[]) {
    return this.connection.prepare(sql).all(...values) as T[];
  }
  run(sql: string, ...values: SQLInputValue[]) {
    return this.connection.prepare(sql).run(...values);
  }
  transaction<T>(action: () => T): T {
    this.connection.exec('BEGIN IMMEDIATE');
    try {
      const result = action();
      this.connection.exec('COMMIT');
      return result;
    } catch (error) {
      this.connection.exec('ROLLBACK');
      throw error;
    }
  }
  close() { this.connection.close(); }
}

export class UserError extends Error {}
