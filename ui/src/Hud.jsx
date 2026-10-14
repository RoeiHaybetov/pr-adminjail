import { useEffect, useRef, useState } from 'react'
import { ShieldAlert, Siren, Navigation } from 'lucide-react'
import { useNuiEvent, useT } from './lib'
import { JobIcon } from './icons'

export default function Hud() {
  const t = useT()
  const [hud, setHud] = useState(null)
  const [task, setTask] = useState(null)
  const [dist, setDist] = useState(null)
  const [edge, setEdge] = useState(false)
  const [bump, setBump] = useState(false)
  const lastLeft = useRef(null)

  useNuiEvent('hud', (data) => {
    if (!data) {
      setHud(null); setTask(null); setEdge(false); lastLeft.current = null
      return
    }
    setHud(data)
  })
  useNuiEvent('task', (data) => setTask(data || null))
  useNuiEvent('taskDistance', setDist)
  useNuiEvent('edge', (v) => setEdge(!!v))

  useEffect(() => {
    if (!hud) return
    if (lastLeft.current !== null && lastLeft.current !== hud.left) {
      setBump(true)
      const id = setTimeout(() => setBump(false), 500)
      lastLeft.current = hud.left
      return () => clearTimeout(id)
    }
    lastLeft.current = hud.left
  }, [hud])

  if (!hud) return null
  const pct = hud.total > 0 ? Math.min(100, (hud.done / hud.total) * 100) : 0

  return (
    <div className={`hud ${hud.position || 'top-right'}`}>
      <div className="hud-stripe" />
      <div className="hud-head">
        <div className="hud-badge"><ShieldAlert size={17} /></div>
        <div>
          <div className="hud-title">{t('ui.hud.title', 'Community Service')}</div>
          <div className="hud-sub">{hud.yard}</div>
        </div>
      </div>

      <div className="hud-count">
        <b className={`num ${bump ? 'bump' : ''}`}>{hud.left}</b>
        <span>{t('ui.hud.left', 'tasks left')}</span>
      </div>

      <div className="hud-progress">
        <div className="bar"><i style={{ width: `${pct}%` }} /></div>
        <div className="meta num">
          <span>{t('ui.hud.done', '%s / %s done', hud.done, hud.total)}</span>
          <span>{Math.floor(pct)}%</span>
        </div>
      </div>

      {edge && (
        <div className="hud-edge">
          <Siren size={16} />
          {t('ui.hud.edge', 'You are at the fence. Step out and it costs +%s tasks.', hud.penaltyTasks)}
        </div>
      )}

      {task && (
        <div className="hud-task">
          <span className="ic"><JobIcon name={task.icon} size={20} /></span>
          <div>
            <div className="lbl">{task.stageLabel}</div>
            <div className="st">
              {task.stages > 1
                ? t('ui.hud.stage', '%s · step %s of %s', task.label, task.stage, task.stages)
                : t('ui.hud.current', 'Current job')}
            </div>
          </div>
          {dist !== null && (
            <span className="dist num"><Navigation size={12} style={{ marginRight: 4 }} />{dist}m</span>
          )}
        </div>
      )}

      <div className="hud-foot">
        <div className="row"><span>{t('ui.hud.reason', 'Reason')}:</span><b>{hud.reason}</b></div>
        {hud.staff && <div className="row"><span>{t('ui.hud.by', 'By')}:</span><b>{hud.staff}</b></div>}
        {hud.escapes > 0 && (
          <div className="row warn">
            {t('ui.hud.escapes', 'Escape attempts: %s (+%s tasks)', hud.escapes, hud.penalty)}
          </div>
        )}
      </div>
    </div>
  )
}
