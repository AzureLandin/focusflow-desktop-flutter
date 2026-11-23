import { useState, type FormEvent } from 'react';
import { Lightbulb, Pencil, Plus, Trash2 } from 'lucide-react';
import type { Thought } from '../shared/model';
import { Button, IconButton, timeLabel, type Run } from './ui';

export function Thoughts({ notes, editable, run }: { notes: Thought[]; editable: boolean; run: Run }) {
  const [content, setContent] = useState('');
  const [editing, setEditing] = useState<string>();
  const [removing, setRemoving] = useState<string>();
  const [busy, setBusy] = useState(false);
  async function save(event: FormEvent) {
    event.preventDefault();
    if (!content.trim() || busy) return;
    setBusy(true);
    if (await run({ type: 'saveThought', id: editing, content })) { setContent(''); setEditing(undefined); }
    setBusy(false);
  }
  return <div className="thoughts">
    {editable && <form className="thought-form" onSubmit={save}>
      <textarea aria-label="番茄想法内容" maxLength={2000} rows={3} placeholder="把冒出来的想法先记在这里…" value={content}
        onChange={(event) => setContent(event.target.value)} onKeyDown={(event) => {
          if (event.key === 'Enter' && (event.ctrlKey || event.metaKey) && !event.nativeEvent.isComposing) event.currentTarget.form?.requestSubmit();
        }} />
      <div><small>Ctrl + Enter 保存</small>{editing && <Button variant="ghost" onClick={() => { setEditing(undefined); setContent(''); }}>取消</Button>}
        <Button type="submit" variant="primary" icon={editing ? undefined : Plus} disabled={!content.trim() || busy}>{editing ? '保存修改' : '记录'}</Button></div>
    </form>}
    {notes.length === 0 ? <p className="notes-empty"><Lightbulb size={16} /> 当天还没有番茄想法。</p> : <ul className="note-list">{notes.map((note) => <li key={note.id}>
      <p>{note.content}</p><div><time dateTime={new Date(note.created_at).toISOString()}>{timeLabel(note.created_at)}</time>
        {editable && (removing === note.id ? <><Button variant="ghost" onClick={() => setRemoving(undefined)}>取消</Button>
          <Button variant="danger" onClick={async () => { if (await run({ type: 'deleteThought', id: note.id })) {
            setRemoving(undefined); if (editing === note.id) { setEditing(undefined); setContent(''); }
          } }}>删除这条想法</Button></> : <>
          <IconButton icon={Pencil} label="编辑想法" onClick={() => { setEditing(note.id); setContent(note.content); setRemoving(undefined); }} />
          <IconButton icon={Trash2} label="删除想法" onClick={() => setRemoving(note.id)} />
        </>)}</div>
    </li>)}</ul>}
  </div>;
}
