import { useState } from 'react'
import { Gavel, Unlock, CheckCircle2, Pencil, MoveRight, Siren, ShieldAlert, LogIn, LogOut, ShieldCheck, Activity, CircleDot } from 'lucide-react'
import { ago, call, usePoll, useT } from '../lib'
import { Empty } from './core'

const ICONS = {
  jail: Gavel, released: Unlock, completed: CheckCircle2, modify: Pencil, transfer: MoveRight,
  escape: Siren, suspicious: ShieldAlert, reconnect: LogIn, disconnect: LogOut,
  staff_add: ShieldCheck, staff_update: ShieldCheck, staff_remove: ShieldCheck,
}

const LABELS = {
  jail: 'Jailed', released: 'Released', completed: 'Served', modify: 'Changed', transfer: 'Moved',
  escape: 'Escape attempt', suspicious: 'Suspicious', reconnect: 'Reconnected', disconnect: 'Disconnected',
  staff_add: 'Staff added', staff_update: 'Staff changed', staff_remove: 'Staff removed',
}

export function EventRow({ e, now }) {
  const t = useT()
  const Icon = ICONS[e.kind] || CircleDot
  return (
    <div className="ev">
      <div className={`ic ${e.kind}`}><Icon size={14} /></div>
      <div>
        <div className="t">
          <b>{t(`ui.ev.${e.kind}`, LABELS[e.kind] || e.kind)}</b>
          {e.sentence_id && <span className="dim num"> · #{e.sentence_id}</span>}
          {e.actor_name && <span className="muted"> · {e.actor_name}</span>}
        </div>
        {e.detail && <div className="d">{e.detail}</div>}
      </div>
      <div className="w">{ago(e.created_at, now)}</div>
    </div>
  )
}

export default function ActivityView() {
  const t = useT()
  const [events, setEvents] = useState(null)
  const [now, setNow] = useState(Date.now() / 1000)

  usePoll(async () => {
    const res = await call('activity')
    if (res && res.ok) { setEvents(res.events); setNow(Date.now() / 1000) }
  }, 5000)

  if (events && events.length === 0) return <Empty icon={Activity} text={t('ui.act.none', 'Nothing has happened yet.')} />
  return (
    <div className="feed">
      {(events || []).map((e) => <EventRow key={e.id} e={e} now={now} />)}
    </div>
  )
}
