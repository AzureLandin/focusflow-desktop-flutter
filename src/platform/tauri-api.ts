import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import type { DesktopApi, Result } from '../shared/model';

async function call<T>(name: string, args?: Record<string, unknown>): Promise<Result<T>> {
  try {
    return { ok: true, value: await invoke<T>(name, args) };
  } catch (error) {
    const message = typeof error === 'string' && /^FF:/.test(error)
      ? error.slice(3)
      : '操作失败。请关闭其他 FocusFlow 窗口后重试。';
    return { ok: false, message };
  }
}

export const tauriApi: DesktopApi = {
  read: (query) => call('workspace_read', { query }),
  pulse: () => call('workspace_pulse'),
  command: (command) => call('workspace_command', { command }),
  backup: (action) => call(action === 'export' ? 'backup_export' : 'backup_restore'),
  onChime(play) {
    let cancelled = false;
    const subscription = listen('timer-chime', () => { if (!cancelled) play(); });
    void subscription.catch(() => console.warn('无法订阅专注提示音。'));
    return () => {
      cancelled = true;
      void subscription.then((unlisten) => unlisten()).catch(() => {});
    };
  },
};
