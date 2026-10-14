import { useState } from 'react'
import { Search, Plus, Minus, Equal, MoveRight, Unlock, Info, Users, Pencil, Wifi } from 'lucide-react'
import { ago, call, usePoll, useT, useAction } from '../lib'
import { usePanel, Dialog, ErrorLine, Empty, Bar } from './core'
import { PlacementFields } from './fields'
import { SentenceDetails } from './HistoryView'
import { JobIcon } from '../icons'

function ModifyDialog({ inmate, onClose, onDone }) {
  const t = useT()
  const { boot, can, errText, toast } = usePanel()
  const [op, setOp] = useState('add')
  const [amount, setAmount] = useState(10)
  const [reason, setReason] = useState('')
  const [error, setError] = useState(null)
  const [busy, run] = useAction()

  const n = Number(amount) || 0
  const after = op === 'add' ? inmate.left + n : op === 'remove' ? Math.max(0, inmate.left - n) : n
  const releasing = after === 0

  const submit = () => run(async () => {
    const res = await call('modify', { id: inmate.id, op, amount: n, reason })
    if (!res || !res.ok) return setError(errText(res))
    toast(releasing ? t('ui.mod.released', '%s served — released.', inmate.name) : t('ui.mod.done', '%s now has %s tasks left.', inmate.name, after))
    onDone()
  })

  const OPS = [['add', Plus, t('ui.mod.add', 'Add')], ['remove', Minus, t('ui.mod.remove', 'Remove')], ['set', Equal, t('ui.mod.set', 'Set left')]]

  return (
    <Dialog icon={Pencil} title={t('ui.mod.title', 'Change sentence')} sub={`${inmate.name} · #${inmate.id}`} onClose={onClose}
      footer={<>
        <button className="btn ghost" onClick={onClose}>{t('ui.cancel', 'Cancel')}</button>
        <button className={`btn ${releasing ? 'danger' : 'primary'}`} disabled={busy || (boot.config.reasonRequired && !reason.trim()) || (op !== 'set' && n < 1) || (releasing && !can('release'))} onClick={submit}>
          {releasing ? t('ui.mod.submit_release', 'Release') : t('ui.mod.submit', 'Apply')}
        </button>
      </>}>
      <ErrorLine text={error} />
      <div className="field">
        <div className="seg">
          {OPS.map(([key, Icon, text]) => (
            <button key={key} className={op === key ? 'on' : ''} onClick={() => setOp(key)}><Icon size={15} />{text}</button>
          ))}
        </div>
      </div>
      <div className="field">
        <div className="label">{t('ui.mod.amount', 'Tasks')}<span className="hint num">{t('ui.mod.preview', '%s left → %s left', inmate.left, after)}</span></div>
        <input className="input num" type="number" min={op === 'set' ? 0 : 1} value={amount} onChange={(e) => setAmount(e.target.value)} />
      </div>
      <div className="field" style={{ marginBottom: 0 }}>
        <div className="label">{t('ui.jail.reason', 'Reason')}</div>
        <textarea className="textarea" maxLength={boot.config.reasonMaxLength} value={reason} onChange={(e) => setReason(e.target.value)} />
      </div>
    </Dialog>
  )
}

function MoveDialog({ inmate, onClose, onDone }) {
  const t = useT()
  const { boot, errText, toast } = usePanel()
  const [yard, setYard] = useState(inmate.yard)
  const [mode, setMode] = useState(inmate.mode)
  const [bucket, setBucket] = useState(inmate.mode === 'custom' ? inmate.bucket : '')
  const [reason, setReason] = useState('')
  const [error, setError] = useState(null)
  const [busy, run] = useAction()

  const submit = () => run(async () => {
    const res = await call('transfer', { id: inmate.id, yard, mode, bucket: mode === 'custom' ? Number(bucket) : undefined, reason })
    if (!res || !res.ok) return setError(errText(res))
    toast(t('ui.move.done', '%s moved.', inmate.name))
    onDone()
  })

  return (
    <Dialog icon={MoveRight} title={t('ui.move.title', 'Move yard / bucket')} sub={`${inmate.name} · ${inmate.yardLabel} · bucket ${inmate.bucket}`} onClose={onClose}
      footer={<>
        <button className="btn ghost" onClick={onClose}>{t('ui.cancel', 'Cancel')}</button>
        <button className="btn primary" disabled={busy || (boot.config.reasonRequired && !reason.trim()) || (mode === 'custom' && bucket === '')} onClick={submit}>{t('ui.move.submit', 'Move')}</button>
      </>}>
      <ErrorLine text={error} />
      <PlacementFields yard={yard} setYard={setYard} mode={mode} setMode={setMode} bucket={bucket} setBucket={setBucket} />
      <div className="field" style={{ marginBottom: 0 }}>
        <div className="label">{t('ui.jail.reason', 'Reason')}</div>
        <textarea className="textarea" value={reason} onChange={(e) => setReason(e.target.value)} />
      </div>
    </Dialog>
  )
}

function ReleaseDialog({ inmate, onClose, onDone }) {
  const t = useT()
  const { boot, errText, toast } = usePanel()
  const [reason, setReason] = useState('')
  const [error, setError] = useState(null)
  const [busy, run] = useAction()

  const submit = () => run(async () => {
    const res = await call('release', { id: inmate.id, reason })
    if (!res || !res.ok) return setError(errText(res))
    toast(t('ui.rel.done', '%s released.', inmate.name))
    onDone()
  })

  return (
    <Dialog icon={Unlock} tone="danger" title={t('ui.rel.title', 'Cancel this sentence?')} sub={t('ui.rel.sub', '%s still owes %s of %s tasks.', inmate.name, inmate.left, inmate.total)} onClose={onClose}
      footer={<>
        <button className="btn ghost" onClick={onClose}>{t('ui.cancel', 'Cancel')}</button>
        <button className="btn danger" disabled={busy || (boot.config.reasonRequired && !reason.trim())} onClick={submit}><Unlock size={15} />{t('ui.rel.submit', 'Release now')}</button>
      </>}>
      <ErrorLine text={error} />
      <div className="label">{t('ui.rel.reason', 'Why are they being released early?')}</div>
      <textarea className="textarea" value={reason} onChange={(e) => setReason(e.target.value)} />
    </Dialog>
  )
}

export default function InmatesView() {
  const t = useT()
  const { can, setInmateCount } = usePanel()
  const [inmates, setInmates] = useState(null)
  const [now, setNow] = useState(Date.now() / 1000)
  const [query, setQuery] = useState('')
  const [dialog, setDialog] = useState(null)

  const load = async () => {
    const res = await call('inmates')
    if (res && res.ok) { setInmates(res.inmates); setNow(res.now); setInmateCount(res.inmates.length) }
  }
  usePoll(load, 3000)

  const close = () => setDialog(null)
  const done = () => { setDialog(null); load() }

  const q = query.trim().toLowerCase()
  const list = (inmates || []).filter((i) => !q || i.name.toLowerCase().includes(q) || String(i.id) === q ||
    String(i.source || '') === q || (i.reason || '').toLowerCase().includes(q))

  return (
    <>
      <div className="toolbar">
        <div className="search">
          <Search size={15} />
          <input className="input" placeholder={t('ui.inm.search', 'Search inmates…')} value={query} onChange={(e) => setQuery(e.target.value)} />
        </div>
        <span className="badge"><Wifi size={11} />{t('ui.inm.live', 'live · refreshes every 3s')}</span>
      </div>

      {inmates && list.length === 0 && <Empty icon={Users} text={t('ui.inm.none', 'Nobody is serving right now. The yard is quiet.')} />}

      <div className="inmates">
        {list.map((i) => (
          <div key={i.id} className="card inmate">
            <div className="who">
              <span className={`dot ${i.online ? 'on' : ''}`} />
              <div style={{ minWidth: 0 }}>
                <div className="nm">{i.name}{i.char && <span className="dim" style={{ fontWeight: 400 }}> · {i.char}</span>}</div>
                <div className="sb">
                  <span className="num">#{i.id}</span>
                  {i.online ? <span className="badge ok num">ID {i.source}</span> : <span className="badge">{t('ui.inm.offline', 'offline — waits for them')}</span>}
                  <span className="badge">{i.yardLabel} · {i.bucket} · {t(`ui.mode.${i.mode}`, i.mode)}</span>
                </div>
              </div>
            </div>

            <div className="prog">
              <div className="top">
                <span><b className="num">{i.left}</b> <span>{t('ui.hud.left', 'tasks left')}</span></span>
                <span className="num">{i.done} / {i.total}</span>
              </div>
              <Bar value={i.done} total={i.total} />
              <div className="bot">
                {i.task && <span className="row" style={{ gap: 5, color: 'var(--accent)' }}><JobIcon name={i.task.icon} size={12} />{i.task.label}{i.task.stages > 1 && ` ${i.task.stage}/${i.task.stages}`}</span>}
                {i.escapes > 0 && <span style={{ color: '#fb923c' }}>{t('ui.inm.escapes', '%s escape attempts (+%s)', i.escapes, i.penalty)}</span>}
                <span>{t('ui.inm.by', 'by %s · %s ago', i.staffName || '—', ago(i.createdAt, now))}</span>
              </div>
            </div>

            <div className="acts">
              {can('modify') && <button className="btn sm" title={t('ui.mod.title', 'Change sentence')} onClick={() => setDialog({ kind: 'modify', inmate: i })}><Pencil size={14} /></button>}
              {can('modify') && <button className="btn sm" title={t('ui.move.title', 'Move yard / bucket')} onClick={() => setDialog({ kind: 'move', inmate: i })}><MoveRight size={14} /></button>}
              {can('history') && <button className="btn sm" title={t('ui.details', 'Details')} onClick={() => setDialog({ kind: 'details', inmate: i })}><Info size={14} /></button>}
              {can('release') && <button className="btn sm danger" onClick={() => setDialog({ kind: 'release', inmate: i })}><Unlock size={14} />{t('ui.rel.short', 'Release')}</button>}
            </div>

            <div className="reason"><span className="dim">{t('ui.jail.reason', 'Reason')}:</span><b>{i.reason}</b></div>
          </div>
        ))}
      </div>

      {dialog?.kind === 'modify' && <ModifyDialog inmate={dialog.inmate} onClose={close} onDone={done} />}
      {dialog?.kind === 'move' && <MoveDialog inmate={dialog.inmate} onClose={close} onDone={done} />}
      {dialog?.kind === 'release' && <ReleaseDialog inmate={dialog.inmate} onClose={close} onDone={done} />}
      {dialog?.kind === 'details' && <SentenceDetails id={dialog.inmate.id} onClose={close} />}
    </>
  )
}
