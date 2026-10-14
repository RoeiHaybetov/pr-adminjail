import { useEffect, useState } from 'react'
import { useNuiEvent, useT } from './lib'

export default function Cinematic() {
  const t = useT()
  const [cine, setCine] = useState(null)

  useNuiEvent('cinematic', (data) => setCine(data ? { ...data, key: Date.now() } : null))

  useEffect(() => {
    if (!cine) return
    const id = setTimeout(() => setCine(null), cine.duration || 6500)
    return () => clearTimeout(id)
  }, [cine])

  if (!cine) return null
  const d = cine.data || {}

  return (
    <div key={cine.key} className={`cine ${cine.kind}`} style={{ '--cine-ms': `${cine.duration || 6500}ms` }}>
      <div className="bars" />
      <div className="cine-card">
        {cine.kind === 'sentenced' && (
          <>
            <div className="cine-tape"><span>{t('ui.cine.tape', 'ADMIN JAIL')}</span></div>
            <h1>{t('ui.cine.sentenced', 'SENTENCED')}</h1>
            <div className="big num">
              <b>{d.tasks}</b> {t('ui.cine.tasks', 'community service tasks')}
            </div>
            <div className="meta">
              <i>{t('ui.cine.reason', 'Reason')}:</i> {d.reason}
              {d.staff && <> &nbsp;·&nbsp; <i>{t('ui.cine.by', 'by')}</i> {d.staff}</>}
            </div>
            <div className="hint">{t('ui.cine.hint', 'Work it off. Every job counts. Running costs more.')}</div>
          </>
        )}
        {cine.kind === 'served' && (
          <>
            <h1>{t('ui.cine.served', 'SERVED')}</h1>
            <div className="big num"><b>{d.tasks}</b> {t('ui.cine.tasks_done', 'tasks completed')}</div>
            <div className="hint">{t('ui.cine.free', 'You are free to go. Behave.')}</div>
          </>
        )}
        {cine.kind === 'released' && (
          <>
            <h1>{t('ui.cine.released', 'RELEASED')}</h1>
            <div className="hint">{t('ui.cine.released_hint', 'Your sentence was cancelled by staff.')}</div>
          </>
        )}
      </div>
    </div>
  )
}
