import { useState, type FormEvent } from 'react';
import { Download, HardDrive, Save, Upload } from 'lucide-react';
import type { Settings as Preferences } from '../shared/model';
import { Button, type Run } from './ui';

export function Settings({ settings, dataPath, run, backup, busy }: {
  settings: Preferences; dataPath: string; run: Run; backup: (action: 'import' | 'export') => Promise<void>; busy: boolean;
}) {
  const [draft, setDraft] = useState(settings);
  const changed = JSON.stringify(draft) !== JSON.stringify(settings);
  const update = <T extends keyof Preferences>(key: T, value: Preferences[T]) => setDraft((previous) => ({ ...previous, [key]: value }));
  const save = (event: FormEvent) => { event.preventDefault(); void run({ type: 'settings', settings: draft }); };
  const timings = [
    ['focusMinutes', '专注时长', 1, 120, '分钟'], ['shortMinutes', '短休息', 1, 60, '分钟'],
    ['longMinutes', '长休息', 15, 30, '分钟'], ['longEvery', '长休息间隔', 1, 12, '个番茄'],
  ] as const;
  const switches = [
    ['finalLongBreak', '会话结束后仍提示长休息', '当最后一个番茄刚好达到长休息间隔时显示提示。'],
    ['sound', '提示音', '每个专注或休息阶段结束时播放。'],
    ['notifications', '系统通知', '阶段结束时发送系统通知。'],
  ] as const;
  return <main className="page settings-page"><header className="page-header"><h1>设置</h1></header>
    <form className="settings-form" onSubmit={save}>
      <section><h2>番茄时钟</h2><div className="settings-fields">{timings.map(([key, title, min, max, unit]) => <label key={key}>
        <span>{title}</span><span className="inline-label"><input type="number" value={Number.isNaN(draft[key]) ? '' : draft[key]} min={min} max={max} required
          onChange={(event) => update(key, event.target.valueAsNumber)} />{unit}</span></label>)}</div>
        {switches.map(([key, title, detail]) => <label className="setting-toggle" key={key}>
          <span><strong>{title}</strong><small>{detail}</small></span><input className="switch" type="checkbox" checked={draft[key]} onChange={(event) => update(key, event.target.checked)} />
        </label>)}
      </section>
      <section><h2>外观</h2><label className="setting-toggle">主题<select value={draft.theme} onChange={(event) => update('theme', event.target.value as Preferences['theme'])}>
        <option value="system">跟随系统</option><option value="light">浅色</option><option value="dark">深色</option>
      </select></label></section>
      <Button icon={Save} type="submit" variant="primary" disabled={!changed || busy}>保存设置</Button>
    </form>
    <section className="data-settings"><h2>本地数据</h2><p><HardDrive size={16} /> SQLite 数据库</p><code>{dataPath}</code>
      <div><Button icon={Download} disabled={busy} onClick={() => void backup('export')}>导出 JSON 备份</Button>
        <Button icon={Upload} disabled={busy} onClick={() => void backup('import')}>恢复 JSON 备份</Button></div>
    </section>
  </main>;
}
