import { useEffect, useState, type CSSProperties, type FormEvent } from 'react';
import { Check, CirclePause, Coffee, Lightbulb, Play, Square, Timer } from 'lucide-react';
import type { ActiveSession, Thought } from '../shared/model';
import { Thoughts } from './thoughts';
import { Button, Logo, Modal, timeSpan, type Run } from './ui';

const phases = { focus: '专注', short_break: '短休息', long_break: '长休息' };
const reasons = ['临时有事', '接到电话或消息', '需要处理紧急任务', '身体不适或需要休息', '其他'];

function Interrupt({ session, run, onClose }: { session: ActiveSession; run: Run; onClose: () => void }) {
  const [selected, setSelected] = useState('');
  const [custom, setCustom] = useState('');
  const [busy, setBusy] = useState(false);
  const reason = selected === '其他' || !selected ? custom.trim() : [selected, custom.trim()].filter(Boolean).join(' · ');
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!reason || busy) return;
    setBusy(true);
    if (await run({ type: 'interrupt', id: session.id, reason })) onClose();
    setBusy(false);
  }
  return <Modal title="打断番茄" onClose={onClose}><form className="form" onSubmit={submit}>
    <p className="muted">第 {session.current_cycle} 轮将记为已打断。已完成的番茄和记录的想法会保留。</p>
    <fieldset className="reasons"><legend>打断原因</legend>{reasons.map((item) => <label key={item}>
      <input type="radio" name="reason" value={item} checked={selected === item} onChange={() => setSelected(item)} />{item}
    </label>)}</fieldset>
    <label>{selected && selected !== '其他' ? '补充说明（可选）' : '填写原因'}<textarea rows={3} maxLength={450} value={custom} onChange={(event) => setCustom(event.target.value)} /></label>
    <footer><Button onClick={onClose}>返回专注</Button><Button variant="danger" type="submit" disabled={!reason || busy}>确认打断</Button></footer>
  </form></Modal>;
}

export function Focus({ session, serverNow, notes, busy, run, recovered }: {
  session: ActiveSession; serverNow: number; notes: Thought[]; busy: boolean; run: Run; recovered: boolean;
}) {
  const [now, setNow] = useState(serverNow);
  const [interruptingCycle, setInterruptingCycle] = useState<number>();
  const [showNotes, setShowNotes] = useState(false);
  const [saveQuick, setSaveQuick] = useState(false);
  const focusRunning = session.status === 'focus_running';
  const focusElapsed = session.status === 'focus_elapsed';
  const breakElapsed = session.status === 'break_elapsed';
  const summary = session.status === 'session_completed';

  useEffect(() => {
    const anchor = performance.now();
    setNow(serverNow);
    const id = window.setInterval(() => setNow(serverNow + performance.now() - anchor), 250);
    return () => window.clearInterval(id);
  }, [serverNow]);

  const seconds = Math.max(0, Math.ceil((session.phase_ends_at - now) / 1000));
  const countdown = `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
  const percent = Math.min(100, Math.max(0, 100 * (now - session.phase_started_at) / (session.phase_ends_at - session.phase_started_at)));
  const advance = () => void run({ type: 'advance', id: session.id });
  const finish = (completed: boolean) => void run({ type: 'resolve', id: session.id, completed, saveQuick });
  const next = session.nextBreak ? `接下来是${phases[session.nextBreak]}` : '可以查看本次专注总结';

  return <div className="focus-window"><header className="focus-top"><Logo /><Button variant="ghost" icon={Lightbulb}
    className="notes-toggle" aria-expanded={showNotes} onClick={() => setShowNotes(!showNotes)}>番茄想法（{notes.length}）</Button></header>
    <div className="focus-layout"><main className="focus-main">
      {recovered && <p className="recovered" role="status">已恢复上次的专注会话</p>}
      <div className="stage-label">{summary ? <Check size={16} /> : session.current_phase === 'focus' ? <Timer size={16} /> : <Coffee size={16} />}
        {summary ? '专注总结' : phases[session.current_phase]}</div>
      <h1>{session.task_title_snapshot}</h1>
      {summary ? <div className="summary" aria-label="本次专注总结">
        <div className="summary-metrics"><div><strong>{session.completed_pomodoros} / {session.planned_pomodoros}</strong><span>完成番茄</span></div>
          <div><strong>{timeSpan(session.focusSeconds)}</strong><span>有效专注</span></div><div><strong>{session.thoughtCount}</strong><span>番茄想法</span></div></div>
        {!session.task_id && <label className="check-label quick-save"><input type="checkbox" checked={saveQuick} onChange={(event) => setSaveQuick(event.target.checked)} />加入今日待办</label>}
        <p>{session.task_id ? session.canConfirm ? '这项任务完成了吗？' : '任务还未达到计划番茄数，可以稍后继续。' : saveQuick ? '这项任务完成了吗？' : '本次专注记录已保存在日历里。'}</p>
        <div className="focus-buttons">
          {(session.task_id && session.canConfirm || !session.task_id && saveQuick) ? <>
            <Button onClick={() => finish(false)} disabled={busy}>还需要继续</Button><Button variant="primary" icon={Check} onClick={() => finish(true)} disabled={busy}>任务已完成</Button>
          </> : <Button variant="primary" onClick={() => finish(false)} disabled={busy}>返回今日待办</Button>}
        </div>
      </div> : <>
        <p className="focus-cycle">第 {session.current_cycle} / {session.planned_pomodoros} 个番茄</p>
        <div className="countdown-ring" style={{ '--progress': `${percent}%` } as CSSProperties}>
          <div><time aria-label="剩余时间" role="timer">{countdown}</time>
            <span>{focusElapsed ? '专注已完成' : breakElapsed ? '休息已结束' : session.current_phase === 'focus' ? '专注计时中' : '休息计时中'}</span></div>
        </div>
        <div className="cycle-dots" aria-label={`已完成 ${session.completed_pomodoros} 个番茄`}>{Array.from({ length: session.planned_pomodoros }, (_, index) =>
          <span key={index} className={index < session.completed_pomodoros ? 'filled' : ''} />)}</div>
        <p className="focus-next" role="status">{focusElapsed ? next : breakElapsed ? session.ending_break ? '可以查看本次专注总结' : '准备好后开始下一个番茄' :
          focusRunning ? session.nextBreak ? `下一阶段：${phases[session.nextBreak]}` : '本轮结束后查看专注总结' : '休息结束后，由你继续'}</p>
        <div className="focus-buttons">
          {focusRunning ? <Button icon={CirclePause} variant="ghost" onClick={() => setInterruptingCycle(session.current_cycle)}>打断番茄</Button> : <>
            {!((focusElapsed && !session.nextBreak) || (breakElapsed && session.ending_break)) && <Button icon={Square} variant="ghost" onClick={() => void run({ type: 'endSession', id: session.id })} disabled={busy}>{session.ending_break || session.completed_pomodoros === session.planned_pomodoros ? '跳过休息' : '结束本次专注'}</Button>}
            {(focusElapsed || breakElapsed) && <Button variant="primary" icon={focusElapsed && session.nextBreak ? Coffee : Play} onClick={advance} disabled={busy}>
              {focusElapsed ? session.nextBreak ? `开始${phases[session.nextBreak]}` : '查看专注总结' : session.ending_break ? '查看专注总结' : '开始下一个番茄'}
            </Button>}
          </>}
        </div>
      </>}
    </main><aside className={`focus-notes${showNotes ? ' open' : ''}`} aria-label="番茄想法面板">
      <h2><Lightbulb size={19} />番茄想法</h2><Thoughts notes={notes} editable run={run} />
    </aside></div>
    {interruptingCycle === session.current_cycle && focusRunning && <Interrupt session={session} run={run} onClose={() => setInterruptingCycle(undefined)} />}
  </div>;
}
