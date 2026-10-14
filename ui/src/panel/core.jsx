import { createContext, useCallback, useContext, useEffect, useState } from 'react'
import { AlertTriangle, CheckCircle2, X } from 'lucide-react'
import { useT } from '../lib'

export const PanelContext = createContext(null)
export const usePanel = () => useContext(PanelContext)

/** English fallbacks for every error key the server can return. */
export const ERRORS = {
  'error.generic': 'Something went wrong.',
  'error.slow_down': 'Slow down a little.',
  'error.no_permission': 'You do not have permission to do that.',
  'error.not_allowed': 'You are not allowed to use the Admin Jail.',
  'error.no_discord': 'Your Discord account could not be verified.',
  'error.jailed_staff': 'You are serving a sentence yourself.',
  'error.player_offline': 'That player is not online.',
  'error.already_jailed': 'That player is already serving sentence #%s.',
  'error.protected_owner': 'Owners cannot be jailed or changed by staff.',
  'error.self_action': 'You cannot touch your own sentence.',
  'error.bad_yard': 'Pick a valid yard.',
  'error.bad_bucket_mode': 'That bucket mode is disabled.',
  'error.bad_bucket': 'Enter a valid bucket number.',
  'error.no_solitary': 'Every solitary bucket is in use.',
  'error.bad_tasks': 'Tasks must be a whole number up to %s.',
  'error.reason_required': 'A reason is required.',
  'error.no_sentence': 'That sentence no longer exists.',
  'error.database': 'Database error — check the server console.',
  'error.over_limit': 'That is more than your limit of %s tasks.',
  'error.bad_request': 'Invalid request.',
  'error.recent_gone': 'That player is no longer in the recent list.',
  'error.bad_identifier': 'Not a recognised identifier. Use discord:, license:, steam: or fivem:.',
  'error.bad_discord': 'Enter a valid Discord user id.',
  'error.owner_immutable': 'Owners are set in s.secrets.lua and cannot be edited here.',
  'error.target_no_discord': 'That player has no Discord linked to FiveM.',
}

export function useErrText() {
  const t = useT()
  return useCallback((res) => {
    const key = (res && res.error) || 'error.generic'
    const arg = res && (res.max ?? res.existing)
    return t(key, ERRORS[key] || key, arg)
  }, [t])
}

export function useToast() {
  const [toast, setToast] = useState(null)
  useEffect(() => {
    if (!toast) return
    const id = setTimeout(() => setToast(null), 3200)
    return () => clearTimeout(id)
  }, [toast])
  const show = useCallback((text, kind = 'ok') => setToast({ text, kind, at: Date.now() }), [])
  const node = toast ? (
    <div key={toast.at} className={`toast ${toast.kind}`}>
      {toast.kind === 'ok' ? <CheckCircle2 size={16} /> : <AlertTriangle size={16} />}
      {toast.text}
    </div>
  ) : null
  return [show, node]
}

export function Dialog({ icon: Icon, tone, title, sub, children, footer, onClose, wide }) {
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') { e.stopPropagation(); onClose() } }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [onClose])

  return (
    <div className="dlg-wrap" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose() }}>
      <div className={`dlg ${wide ? 'wide' : ''}`}>
        <div className="dlg-head">
          {Icon && <div className={`ic ${tone || ''}`}><Icon size={17} /></div>}
          <div className="grow">
            <h3>{title}</h3>
            {sub && <p>{sub}</p>}
          </div>
          <button className="x" onClick={onClose}><X size={16} /></button>
        </div>
        <div className="dlg-body scroll">{children}</div>
        {footer && <div className="dlg-foot">{footer}</div>}
      </div>
    </div>
  )
}

export function ErrorLine({ text }) {
  if (!text) return null
  return <div className="error-line"><AlertTriangle size={15} />{text}</div>
}

export function Empty({ icon: Icon, text }) {
  return (
    <div className="empty">
      {Icon && <Icon size={42} />}
      <div>{text}</div>
    </div>
  )
}

export function Bar({ value, total, ok }) {
  const pct = total > 0 ? Math.min(100, (value / total) * 100) : 0
  return <div className={`bar ${ok ? 'ok' : ''}`}><i style={{ width: `${pct}%` }} /></div>
}
