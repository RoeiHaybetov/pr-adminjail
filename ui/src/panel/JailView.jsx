import { useMemo, useState } from 'react'
import { Search, User, Wifi, WifiOff, Fingerprint, Gavel, Crown, ShieldCheck, Lock } from 'lucide-react'
import { ago, call, usePoll, useT, useAction } from '../lib'
import { usePanel, ErrorLine, Empty } from './core'
import { PlacementFields } from './fields'

export default function JailView() {
  const t = useT()
  const { boot, can, toast, errText, setView } = usePanel()
  const cfg = boot.config
  const max = boot.me.maxTasks

  const [tab, setTab] = useState('online')
  const [players, setPlayers] = useState([])
  const [recent, setRecent] = useState([])
  const [now, setNow] = useState(Date.now() / 1000)
  const [query, setQuery] = useState('')
  const [target, setTarget] = useState(null)
  const [identifier, setIdentifier] = useState('')
  const [label, setLabel] = useState('')

  const [tasks, setTasks] = useState(Math.min(cfg.presets[2] || 50, max))
  const [yard, setYard] = useState(cfg.defaultYard)
  const [mode, setMode] = useState(cfg.defaultMode)
  const [bucket, setBucket] = useState('')
  const [reason, setReason] = useState('')
  const [error, setError] = useState(null)
  const [busy, run] = useAction()

  usePoll(async () => {
    const res = await call('players')
    if (res && res.ok) { setPlayers(res.players); setRecent(res.recent || []); setNow(res.now) }
  }, 5000)

  const list = useMemo(() => {
    const q = query.trim().toLowerCase()
    const src = tab === 'online' ? players : recent
    if (!q) return src
    return src.filter((p) =>
      String(p.source).includes(q) || (p.name || '').toLowerCase().includes(q) ||
      (p.char || '').toLowerCase().includes(q) || (p.discord || '').includes(q))
  }, [tab, players, recent, query])

  const pick = (p) => {
    if (p.jailed) return
    setTarget(tab === 'online' ? { kind: 'online', source: p.source, name: p.name, char: p.char, isOwner: p.isOwner }
      : { kind: 'recent', token: p.token, name: p.name, char: p.char })
    setError(null)
  }

  const resolvedTarget = tab === 'id'
    ? (identifier.trim() ? { kind: 'id', identifier: identifier.trim(), name: label.trim() || identifier.trim() } : null)
    : target

  const submit = () => run(async () => {
    setError(null)
    const payload = { tasks: Number(tasks), yard, mode, bucket: mode === 'custom' ? Number(bucket) : undefined, reason }
    if (resolvedTarget.kind === 'online') payload.source = resolvedTarget.source
    if (resolvedTarget.kind === 'recent') payload.recent = resolvedTarget.token
    if (resolvedTarget.kind === 'id') { payload.identifier = resolvedTarget.identifier; payload.label = label }
    const res = await call('jail', payload)
    if (!res || !res.ok) { setError(errText(res)); return }
    toast(res.online
      ? t('ui.jail.done_online', '%s is now serving %s tasks.', resolvedTarget.name, tasks)
      : t('ui.jail.done_offline', 'Sentence #%s saved — it starts the moment they join.', res.id))
    setTarget(null); setReason(''); setIdentifier(''); setLabel('')
    setView('inmates')
  })

  const taskNum = Number(tasks)
  const valid = resolvedTarget && Number.isInteger(taskNum) && taskNum >= cfg.minTasks && taskNum <= max &&
    (!cfg.reasonRequired || reason.trim()) && (mode !== 'custom' || bucket !== '')
  const yardLabel = boot.yards.find((y) => y.key === yard)?.label

  return (
    <div className="jail-grid">
      <div className="col">
        <div className="tabs">
          <button className={tab === 'online' ? 'on' : ''} onClick={() => { setTab('online'); setTarget(null) }}>
            <Wifi size={14} /> {t('ui.jail.online', 'Online')} <span className="dim num">{players.length}</span>
          </button>
          {can('offline') && (
            <>
              <button className={tab === 'recent' ? 'on' : ''} onClick={() => { setTab('recent'); setTarget(null) }}>
                <WifiOff size={14} /> {t('ui.jail.recent', 'Recently left')} <span className="dim num">{recent.length}</span>
              </button>
              <button className={tab === 'id' ? 'on' : ''} onClick={() => { setTab('id'); setTarget(null) }}>
                <Fingerprint size={14} /> {t('ui.jail.by_id', 'By identifier')}
              </button>
            </>
          )}
        </div>

        {tab !== 'id' ? (
          <>
            <div className="search">
              <Search size={15} />
              <input className="input" placeholder={t('ui.jail.search', 'Search by ID, name or Discord…')} value={query} onChange={(e) => setQuery(e.target.value)} />
            </div>
            <div className="plist scroll">
              {list.length === 0 && <Empty icon={User} text={t('ui.jail.nobody', 'Nobody here.')} />}
              {list.map((p) => {
                const on = target && (tab === 'online' ? target.source === p.source : target.token === p.token)
                return (
                  <div key={p.token || p.source} className={`prow ${on ? 'on' : ''} ${p.jailed ? 'off' : ''}`} onClick={() => pick(p)}>
                    <div className="sid num">{p.source}</div>
                    <div className="grow">
                      <div className="nm">{p.name}{p.char && <span className="dim"> · {p.char}</span>}</div>
                      <div className="sb">
                        {tab === 'recent'
                          ? t('ui.jail.left_ago', 'left %s ago · %s', ago(p.droppedAt, now), p.reason || '')
                          : (p.discord ? `discord:${p.discord}` : t('ui.jail.no_discord', 'no Discord linked'))}
                      </div>
                    </div>
                    {p.isOwner && <span className="badge accent"><Crown size={11} />{t('ui.role.owner', 'Owner')}</span>}
                    {p.isStaff && <span className="badge info"><ShieldCheck size={11} />{t('ui.role.staff', 'Staff')}</span>}
                    {p.jailed && <span className="badge danger"><Lock size={11} />{t('ui.jail.serving', 'Serving')}</span>}
                  </div>
                )
              })}
            </div>
          </>
        ) : (
          <div className="card" style={{ padding: 16 }}>
            <div className="field">
              <div className="label">{t('ui.jail.identifier', 'Identifier')}</div>
              <input className="input mono" placeholder="discord:123… · license:… · steam:… · fivem:…" value={identifier} onChange={(e) => setIdentifier(e.target.value)} />
            </div>
            <div className="field" style={{ marginBottom: 8 }}>
              <div className="label">{t('ui.jail.label', 'Name for the logs')}<span className="hint">{t('ui.optional', 'optional')}</span></div>
              <input className="input" maxLength={48} value={label} onChange={(e) => setLabel(e.target.value)} />
            </div>
            <p className="small dim" style={{ margin: '10px 0 0', lineHeight: 1.6 }}>
              {t('ui.jail.id_help', 'The sentence waits for them. The moment someone with this identifier loads in, they go straight to the yard — any matching Discord, licence, Steam or FiveM id counts.')}
            </p>
          </div>
        )}
      </div>

      <div className="card form scroll">
        <div className={`target-card ${resolvedTarget ? 'set' : ''}`}>
          <div className="av"><User size={20} /></div>
          <div className="grow">
            {resolvedTarget ? (
              <>
                <div style={{ fontWeight: 600 }}>{resolvedTarget.name}</div>
                <div className="small dim">
                  {resolvedTarget.kind === 'online' && t('ui.jail.t_online', 'Online · ID %s', resolvedTarget.source)}
                  {resolvedTarget.kind === 'recent' && t('ui.jail.t_recent', 'Offline · served on next join')}
                  {resolvedTarget.kind === 'id' && t('ui.jail.t_id', 'By identifier · served on next join')}
                </div>
              </>
            ) : (
              <div className="dim">{t('ui.jail.pick', 'Pick a player on the left')}</div>
            )}
          </div>
        </div>

        <div className="field">
          <div className="label">{t('ui.jail.tasks', 'Community service tasks')}<span className="hint">{t('ui.jail.max', 'your max: %s', max)}</span></div>
          <div className="chips">
            {cfg.presets.map((n) => (
              <button key={n} className={`chip ${Number(tasks) === n ? 'on' : ''}`} disabled={n > max} onClick={() => setTasks(n)}>{n}</button>
            ))}
          </div>
          <div className="task-input">
            <input className="input num" type="number" min={cfg.minTasks} max={max} value={tasks} onChange={(e) => setTasks(e.target.value)} />
            <input className="range" type="range" min={cfg.minTasks} max={Math.min(max, 500)} value={Math.min(Number(tasks) || 0, 500)} onChange={(e) => setTasks(e.target.value)} />
          </div>
        </div>

        <PlacementFields yard={yard} setYard={setYard} mode={mode} setMode={setMode} bucket={bucket} setBucket={setBucket} />

        <div className="field">
          <div className="label">{t('ui.jail.reason', 'Reason')}{!cfg.reasonRequired && <span className="hint">{t('ui.optional', 'optional')}</span>}</div>
          <textarea className="textarea" maxLength={cfg.reasonMaxLength} value={reason} onChange={(e) => setReason(e.target.value)}
            placeholder={t('ui.jail.reason_ph', 'What did they do?')} />
        </div>

        <div className="summary">
          <ErrorLine text={error} />
          <p>
            {t('ui.jail.summary', 'They will do %s jobs at %s. They walk out only after the last one. Each escape attempt adds +%s.',
              Number(tasks) || 0, yardLabel, cfg.penaltyTasks)}
          </p>
          <button className="btn danger lg block" disabled={!valid || busy} onClick={submit}>
            <Gavel size={17} /> {t('ui.jail.submit', 'Sentence to %s tasks', Number(tasks) || 0)}
          </button>
        </div>
      </div>
    </div>
  )
}
