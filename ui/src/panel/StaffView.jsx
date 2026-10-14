import { useEffect, useState } from 'react'
import { Crown, UserPlus, Trash2, Save, Check, Send, ShieldCheck } from 'lucide-react'
import { call, useT, useAction } from '../lib'
import { usePanel, ErrorLine, Empty } from './core'

function Perms({ catalog, value, onChange }) {
  const t = useT()
  const toggle = (key) => onChange(value.includes(key) ? value.filter((k) => k !== key) : [...value, key])
  return (
    <div className="perms">
      {catalog.map((p) => (
        <button key={p.key} title={t(`ui.perm.${p.key}_desc`, p.desc)} className={`perm ${value.includes(p.key) ? 'on' : ''}`} onClick={() => toggle(p.key)}>
          {value.includes(p.key) && <Check size={12} />}
          {t(`ui.perm.${p.key}`, p.label)}
        </button>
      ))}
    </div>
  )
}

function StaffCard({ s, catalog, onSaved }) {
  const t = useT()
  const { boot, toast, errText } = usePanel()
  const initial = { label: s.label, perms: Object.keys(s.perms || {}), maxTasks: s.maxTasks || 0 }
  const [form, setForm] = useState(initial)
  const [error, setError] = useState(null)
  const [busy, run] = useAction()
  const [confirm, setConfirm] = useState(false)

  const dirty = JSON.stringify(form) !== JSON.stringify(initial)

  const save = () => run(async () => {
    const res = await call('saveStaff', { discord: s.discord, label: form.label, perms: form.perms, maxTasks: Number(form.maxTasks) || 0 })
    if (!res || !res.ok) return setError(errText(res))
    toast(t('ui.staff.saved', '%s saved.', form.label))
    onSaved()
  })

  const remove = () => run(async () => {
    const res = await call('removeStaff', { discord: s.discord })
    if (!res || !res.ok) return setError(errText(res))
    toast(t('ui.staff.removed', '%s can no longer use the jail.', s.label))
    onSaved()
  })

  return (
    <div className="card srow">
      <ErrorLine text={error} />
      <div className="top">
        <ShieldCheck size={18} color="var(--info)" />
        <input className="input" style={{ maxWidth: 220, height: 32 }} value={form.label} maxLength={64} onChange={(e) => setForm({ ...form, label: e.target.value })} />
        <span className="mono dim small">{s.discord}</span>
        <div className="grow" />
        <span className="small dim">{t('ui.staff.max', 'max tasks')}</span>
        <input className="input num" type="number" style={{ width: 86, height: 32 }} min={0} max={boot.config.maxTasks}
          value={form.maxTasks} onChange={(e) => setForm({ ...form, maxTasks: e.target.value })} />
      </div>
      <Perms catalog={catalog} value={form.perms} onChange={(perms) => setForm({ ...form, perms })} />
      <div className="row">
        <span className="small dim grow">{Number(form.maxTasks) > 0 ? t('ui.staff.cap', 'Can hand out up to %s tasks at once.', form.maxTasks) : t('ui.staff.nocap', 'No personal cap (server max %s).', boot.config.maxTasks)}</span>
        {confirm ? (
          <>
            <button className="btn sm ghost" onClick={() => setConfirm(false)}>{t('ui.cancel', 'Cancel')}</button>
            <button className="btn sm danger" disabled={busy} onClick={remove}><Trash2 size={13} />{t('ui.staff.confirm_remove', 'Remove access')}</button>
          </>
        ) : (
          <button className="btn sm ghost" onClick={() => setConfirm(true)}><Trash2 size={13} /></button>
        )}
        <button className="btn sm primary" disabled={!dirty || busy} onClick={save}><Save size={13} />{t('ui.save', 'Save')}</button>
      </div>
    </div>
  )
}

export default function StaffView() {
  const t = useT()
  const { boot, toast, errText } = usePanel()
  const catalog = boot.permsCatalog
  const [data, setData] = useState(null)
  const [players, setPlayers] = useState([])
  const [mode, setMode] = useState('online')
  const [source, setSource] = useState('')
  const [discord, setDiscord] = useState('')
  const [label, setLabel] = useState('')
  const [perms, setPerms] = useState(['jail', 'modify'])
  const [maxTasks, setMaxTasks] = useState(0)
  const [error, setError] = useState(null)
  const [busy, run] = useAction()

  const load = () => call('staff').then((res) => setData(res && res.ok ? res : null))
  useEffect(() => {
    load()
    call('players').then((res) => res && res.ok && setPlayers(res.players.filter((p) => p.discord && !p.isOwner && !p.isStaff)))
  }, [])

  const add = () => run(async () => {
    setError(null)
    const payload = { label, perms, maxTasks: Number(maxTasks) || 0 }
    if (mode === 'online') payload.source = Number(source)
    else payload.discord = discord.trim()
    const res = await call('saveStaff', payload)
    if (!res || !res.ok) return setError(errText(res))
    toast(t('ui.staff.added', 'Staff member added.'))
    setSource(''); setDiscord(''); setLabel('')
    load()
    call('players').then((r) => r && r.ok && setPlayers(r.players.filter((p) => p.discord && !p.isOwner && !p.isStaff)))
  })

  const test = async () => {
    const res = await call('testLog')
    toast(res && res.ok ? t('ui.staff.test_sent', 'Test sent to the staff webhook.') : errText(res), res && res.ok ? 'ok' : 'err')
  }

  const canAdd = (mode === 'online' ? source !== '' : /^\d{15,22}$/.test(discord.trim()))

  return (
    <div className="staff-grid">
      <div className="col scroll" style={{ gap: 10 }}>
        {data && data.staff.length === 0 && <Empty icon={ShieldCheck} text={t('ui.staff.none', 'No staff yet. Only owners can use the jail.')} />}
        {data && data.staff.map((s) => <StaffCard key={`${s.discord}:${s.updatedAt}`} s={s} catalog={catalog} onSaved={load} />)}
      </div>

      <div className="col scroll" style={{ gap: 14 }}>
        <div className="card" style={{ padding: 16 }}>
          <div className="label"><UserPlus size={14} />{t('ui.staff.add', 'Give access')}</div>
          <ErrorLine text={error} />
          <div className="tabs">
            <button className={mode === 'online' ? 'on' : ''} onClick={() => setMode('online')}>{t('ui.staff.from_online', 'Online player')}</button>
            <button className={mode === 'id' ? 'on' : ''} onClick={() => setMode('id')}>{t('ui.staff.from_id', 'Discord ID')}</button>
          </div>
          <div className="field">
            {mode === 'online' ? (
              <select className="select" value={source} onChange={(e) => setSource(e.target.value)}>
                <option value="">{t('ui.staff.pick', 'Pick a player with Discord linked…')}</option>
                {players.map((p) => <option key={p.source} value={p.source}>{p.source} · {p.name}</option>)}
              </select>
            ) : (
              <input className="input mono" placeholder="720720916354564199" value={discord} onChange={(e) => setDiscord(e.target.value)} />
            )}
          </div>
          <div className="field">
            <div className="label">{t('ui.staff.label', 'Label')}<span className="hint">{t('ui.staff.label_hint', 'e.g. Senior Admin')}</span></div>
            <input className="input" maxLength={64} value={label} onChange={(e) => setLabel(e.target.value)} />
          </div>
          <div className="field">
            <div className="label">{t('ui.staff.perms', 'Permissions')}</div>
            <Perms catalog={catalog} value={perms} onChange={setPerms} />
          </div>
          <div className="field">
            <div className="label">{t('ui.staff.max_label', 'Max tasks per sentence')}<span className="hint">{t('ui.staff.max_hint', '0 = server max')}</span></div>
            <input className="input num" type="number" min={0} max={boot.config.maxTasks} value={maxTasks} onChange={(e) => setMaxTasks(e.target.value)} />
          </div>
          <button className="btn primary block" disabled={!canAdd || busy} onClick={add}><UserPlus size={15} />{t('ui.staff.add_btn', 'Add staff')}</button>
        </div>

        <div className="card" style={{ padding: 16 }}>
          <div className="label"><Crown size={14} />{t('ui.staff.owners', 'Owners')}<span className="hint">s.secrets.lua</span></div>
          {(data?.owners || []).map((id) => (
            <div key={id} className="owner-row"><Crown size={14} color="var(--accent)" /><span className="mono">{id}</span></div>
          ))}
          <p className="small dim" style={{ lineHeight: 1.6, margin: '8px 0 12px' }}>
            {t('ui.staff.owners_help', 'Owners have every permission and are the only ones who see this tab. They are set server-side and cannot be removed from here.')}
          </p>
          <button className="btn sm block" onClick={test}><Send size={13} />{t('ui.staff.test', 'Send a test log')}</button>
        </div>
      </div>
    </div>
  )
}
