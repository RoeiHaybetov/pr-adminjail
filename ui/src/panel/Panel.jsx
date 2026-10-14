import { useCallback, useEffect, useState } from 'react'
import { Gavel, Users, History, Activity, ShieldCheck, X, Lock } from 'lucide-react'
import { call, nui, useNuiEvent, useT } from '../lib'
import { PanelContext, useErrText, useToast, Empty } from './core'
import JailView from './JailView'
import InmatesView from './InmatesView'
import HistoryView from './HistoryView'
import ActivityView from './ActivityView'
import StaffView from './StaffView'

const VIEWS = [
  { key: 'jail', icon: Gavel, perm: 'jail', title: ['ui.nav.jail', 'Sentence'], sub: ['ui.nav.jail_sub', 'Send someone to do community service'] },
  { key: 'inmates', icon: Users, perm: null, title: ['ui.nav.inmates', 'Inmates'], sub: ['ui.nav.inmates_sub', 'Everyone currently serving — live'] },
  { key: 'history', icon: History, perm: 'history', title: ['ui.nav.history', 'History'], sub: ['ui.nav.history_sub', 'Every sentence ever handed out'] },
  { key: 'activity', icon: Activity, perm: 'history', title: ['ui.nav.activity', 'Activity'], sub: ['ui.nav.activity_sub', 'The latest events across all sentences'] },
  { key: 'staff', icon: ShieldCheck, perm: 'owner', title: ['ui.nav.staff', 'Staff'], sub: ['ui.nav.staff_sub', 'Choose who can use the Admin Jail, and what they can do'] },
]

export default function Panel() {
  const t = useT()
  const errText = useErrText()
  const [open, setOpen] = useState(false)
  const [boot, setBoot] = useState(null)
  const [error, setError] = useState(null)
  const [view, setView] = useState('inmates')
  const [inmateCount, setInmateCount] = useState(0)
  const [toast, toastNode] = useToast()

  useNuiEvent('panel', (v) => setOpen(!!v))

  useEffect(() => {
    if (!open) { setBoot(null); setError(null); return }
    call('bootstrap').then((res) => {
      if (!res || !res.ok) { setError(errText(res)); return }
      setBoot(res)
      const perms = new Set(res.me.perms)
      setView((v) => {
        const def = VIEWS.find((x) => x.key === v)
        const allowed = (d) => !d.perm || (d.perm === 'owner' ? res.me.isOwner : perms.has(d.perm))
        if (def && allowed(def)) return v
        return perms.has('jail') ? 'jail' : 'inmates'
      })
    })
  }, [open, errText])

  const close = useCallback(() => {
    setOpen(false)
    nui('close')
  }, [])

  useEffect(() => {
    if (!open) return
    const onKey = (e) => { if (e.key === 'Escape') close() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, close])

  if (!open) return null

  const can = (perm) => !!boot && (boot.me.isOwner || boot.me.perms.includes(perm))
  const allowed = (d) => !d.perm || (d.perm === 'owner' ? boot?.me.isOwner : can(d.perm))
  const current = VIEWS.find((v) => v.key === view) || VIEWS[1]
  const ctx = { boot, can, toast, errText, setView, setInmateCount }

  return (
    <div className="panel-wrap">
      <div className="panel">
        <aside className="side">
          <div className="brand">
            <div className="logo"><Lock size={19} strokeWidth={2.4} /></div>
            <div>
              <h2>{t('ui.brand', 'Admin Jail')}</h2>
              <p>{t('ui.brand_sub', 'served in work, not minutes')}</p>
            </div>
          </div>
          <nav className="nav">
            {boot && VIEWS.filter(allowed).map((v) => (
              <button key={v.key} className={view === v.key ? 'on' : ''} onClick={() => setView(v.key)}>
                <v.icon size={17} />
                {t(...v.title)}
                {v.key === 'inmates' && inmateCount > 0 && <span className="count num">{inmateCount}</span>}
              </button>
            ))}
          </nav>
          {boot && (
            <div className="me">
              <div className="av">{(boot.me.name || '?').slice(0, 1).toUpperCase()}</div>
              <div style={{ minWidth: 0 }}>
                <div className="nm">{boot.me.name}</div>
                <span className={`badge ${boot.me.isOwner ? 'accent' : 'info'}`}>
                  {boot.me.isOwner ? t('ui.role.owner', 'Owner') : (boot.me.label || t('ui.role.staff', 'Staff'))}
                </span>
              </div>
            </div>
          )}
        </aside>

        <section className="main">
          <header className="head">
            <current.icon size={22} color="var(--accent)" />
            <div>
              <h1>{t(...current.title)}</h1>
              <p>{t(...current.sub)}</p>
            </div>
            <div className="spacer" />
            <button className="x" onClick={close}><X size={17} /></button>
          </header>

          <div className="body scroll">
            {error && <Empty icon={Lock} text={error} />}
            {!error && !boot && <Empty text={t('ui.loading', 'Loading…')} />}
            {boot && (
              <PanelContext.Provider value={ctx}>
                {view === 'jail' && <JailView />}
                {view === 'inmates' && <InmatesView />}
                {view === 'history' && <HistoryView />}
                {view === 'activity' && <ActivityView />}
                {view === 'staff' && <StaffView />}
              </PanelContext.Provider>
            )}
          </div>
        </section>
      </div>
      {toastNode}
    </div>
  )
}
