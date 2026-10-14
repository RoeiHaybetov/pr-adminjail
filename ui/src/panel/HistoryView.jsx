import { useEffect, useState } from 'react'
import { Search, ChevronLeft, ChevronRight, Info, Copy, ExternalLink, FileText } from 'lucide-react'
import { call, nui, stamp, steam64, useT } from '../lib'
import { usePanel, Dialog, Empty, Bar } from './core'
import { EventRow } from './ActivityView'

const STATUS_TONE = { active: 'danger', completed: 'ok', released: 'info' }

export function StatusBadge({ status }) {
  const t = useT()
  return <span className={`badge ${STATUS_TONE[status] || ''}`}>{t(`ui.status.${status}`, status)}</span>
}

function IdRow({ kind, value, link }) {
  if (!value) return null
  const full = `${kind}:${value}`
  return (
    <div className="idrow">
      <span>{kind}</span>
      <span className="v mono">{full}</span>
      <span className="row" style={{ gap: 4 }}>
        {link && <a className="btn sm ghost" href={link} target="_blank" rel="noreferrer"><ExternalLink size={13} /></a>}
        <button className="btn sm ghost" onClick={() => nui('copy', { text: full })}><Copy size={13} /></button>
      </span>
    </div>
  )
}

export function SentenceDetails({ id, onClose }) {
  const t = useT()
  const [data, setData] = useState(null)

  useEffect(() => {
    call('events', { id }).then((res) => setData(res && res.ok ? res : false))
  }, [id])

  const s = data && data.sentence
  const s64 = s && steam64(s.steam)

  return (
    <Dialog wide icon={FileText} title={t('ui.det.title', 'Sentence #%s', id)} sub={s ? `${s.name}${s.char_name ? ' · ' + s.char_name : ''}` : ''} onClose={onClose}>
      {data === null && <Empty text={t('ui.loading', 'Loading…')} />}
      {data === false && <Empty text={t('error.generic', 'Something went wrong.')} />}
      {s && (
        <div className="stack">
          <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
            <StatusBadge status={s.status} />
            <span className="badge num">{s.tasks_done} / {s.tasks_total}</span>
            {s.penalty_tasks > 0 && <span className="badge danger num">+{s.penalty_tasks} {t('ui.det.penalty', 'penalty')}</span>}
            <span className="badge">{s.yard} · {s.bucket} · {s.bucket_mode}</span>
            <span className="badge">{t('ui.det.by', 'by %s', s.staff_name || '—')}</span>
            <span className="badge">{stamp(s.created_at)}</span>
          </div>
          <Bar value={s.tasks_done} total={s.tasks_total} ok={s.status !== 'active'} />
          <div className="card" style={{ padding: 12, fontSize: 13 }}>
            <div className="small dim" style={{ marginBottom: 4 }}>{t('ui.jail.reason', 'Reason')}</div>
            {s.reason}
            {s.end_reason && <>
              <div className="small dim" style={{ margin: '10px 0 4px' }}>{t('ui.det.end', 'Ended by %s', s.ended_by_name || 'system')}</div>
              {s.end_reason}
            </>}
          </div>
          <div>
            <div className="label">{t('ui.det.ids', 'Identifiers')}</div>
            <div className="ids">
              <IdRow kind="discord" value={s.discord} />
              <IdRow kind="steam" value={s.steam} link={s64 && `https://steamcommunity.com/profiles/${s64}`} />
              <IdRow kind="license" value={s.license} />
              <IdRow kind="fivem" value={s.fivem} />
            </div>
          </div>
          <div>
            <div className="label">{t('ui.det.log', 'Event log')}</div>
            <div className="feed">
              {data.events.map((e) => <EventRow key={e.id} e={e} />)}
            </div>
          </div>
        </div>
      )}
    </Dialog>
  )
}

export default function HistoryView() {
  const t = useT()
  const [status, setStatus] = useState('all')
  const [search, setSearch] = useState('')
  const [debounced, setDebounced] = useState('')
  const [page, setPage] = useState(1)
  const [data, setData] = useState(null)
  const [open, setOpen] = useState(null)

  useEffect(() => {
    const id = setTimeout(() => { setDebounced(search); setPage(1) }, 300)
    return () => clearTimeout(id)
  }, [search])

  useEffect(() => {
    call('history', { status, search: debounced, page }).then((res) => setData(res && res.ok ? res : null))
  }, [status, debounced, page])

  const pages = data ? Math.max(1, Math.ceil(data.total / data.pageSize)) : 1

  return (
    <>
      <div className="toolbar">
        <div className="search">
          <Search size={15} />
          <input className="input" placeholder={t('ui.hist.search', 'Name, reason, staff, #id, or an exact identifier…')} value={search} onChange={(e) => setSearch(e.target.value)} />
        </div>
        <select className="select" style={{ width: 160 }} value={status} onChange={(e) => { setStatus(e.target.value); setPage(1) }}>
          {['all', 'active', 'completed', 'released'].map((s) => <option key={s} value={s}>{t(`ui.status.${s}`, s)}</option>)}
        </select>
      </div>

      {data && data.rows.length === 0 && <Empty icon={FileText} text={t('ui.hist.none', 'No sentences match.')} />}

      {data && data.rows.length > 0 && (
        <table className="table">
          <thead>
            <tr>
              <th>#</th><th>{t('ui.hist.player', 'Player')}</th><th>{t('ui.hist.tasks', 'Tasks')}</th>
              <th>{t('ui.jail.reason', 'Reason')}</th><th>{t('ui.hist.staff', 'Staff')}</th>
              <th>{t('ui.hist.status', 'Status')}</th><th>{t('ui.hist.when', 'When')}</th><th />
            </tr>
          </thead>
          <tbody>
            {data.rows.map((r) => (
              <tr key={r.id} className="click" onClick={() => setOpen(r.id)}>
                <td className="num dim">{r.id}</td>
                <td className="ell" style={{ fontWeight: 500 }}>{r.name}</td>
                <td className="num">{r.tasks_done}/{r.tasks_total}</td>
                <td className="ell muted">{r.reason}</td>
                <td className="ell">{r.staff_name}</td>
                <td><StatusBadge status={r.status} /></td>
                <td className="dim small">{stamp(r.created_at)}</td>
                <td><Info size={14} className="dim" /></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {data && (
        <div className="pager">
          <span className="num">{t('ui.hist.count', '%s sentences', data.total)}</span>
          <div className="row">
            <button className="btn sm" disabled={page <= 1} onClick={() => setPage(page - 1)}><ChevronLeft size={14} /></button>
            <span className="num">{page} / {pages}</span>
            <button className="btn sm" disabled={page >= pages} onClick={() => setPage(page + 1)}><ChevronRight size={14} /></button>
          </div>
        </div>
      )}

      {open && <SentenceDetails id={open} onClose={() => setOpen(null)} />}
    </>
  )
}
