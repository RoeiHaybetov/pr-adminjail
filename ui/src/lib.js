import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from 'react'

export const isBrowser = typeof window.GetParentResourceName !== 'function'

export function resourceName() {
  return isBrowser ? 'pr-adminjail' : window.GetParentResourceName()
}

let mock = null
export function setMock(fn) { mock = fn }

export async function nui(endpoint, payload) {
  if (isBrowser) return mock ? mock(endpoint, payload) : { ok: false, error: 'error.generic' }
  try {
    const res = await fetch(`https://${resourceName()}/${endpoint}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(payload || {}),
    })
    return await res.json()
  } catch {
    return { ok: false, error: 'error.generic' }
  }
}

/** One call through the panel's single door. */
export function call(action, payload) {
  return nui('panel', { action, payload: payload || {} })
}

// ---------------------------------------------------------------------------
// Messages from Lua

const handlers = new Set()

window.addEventListener('message', (e) => {
  const msg = e.data
  if (!msg || typeof msg !== 'object' || !msg.action) return
  if (msg.locales) setLocales(msg.locales)
  handlers.forEach((fn) => fn(msg))
})

export function useNuiEvent(action, fn) {
  const ref = useRef(fn)
  ref.current = fn
  useEffect(() => {
    const h = (msg) => { if (msg.action === action) ref.current(msg.data) }
    handlers.add(h)
    return () => handlers.delete(h)
  }, [action])
}

export function emit(action, data, extra) {
  window.postMessage({ action, data, ...(extra || {}) }, '*')
}

// ---------------------------------------------------------------------------
// Locales — sent by Lua from locales/*.json. Every call carries an English fallback, so a
// missing key never shows up as a raw key.

let bundle = {}
const listeners = new Set()

export function setLocales(next) {
  if (!next || typeof next !== 'object') return
  bundle = next
  listeners.forEach((fn) => fn())
}

const subscribe = (fn) => { listeners.add(fn); return () => listeners.delete(fn) }
const snapshot = () => bundle

function format(text, args) {
  if (!args || !args.length) return text
  let i = 0
  return text.replace(/%[sd]/g, () => (i < args.length ? String(args[i++]) : ''))
}

export function useT() {
  const active = useSyncExternalStore(subscribe, snapshot, snapshot)
  return useCallback((key, fallback, ...args) => {
    const value = active[key]
    const text = typeof value === 'string' && value !== key ? value : (fallback !== undefined ? fallback : key)
    return format(text, args)
  }, [active])
}

// ---------------------------------------------------------------------------
// Helpers

export function usePoll(fn, ms, deps) {
  const ref = useRef(fn)
  ref.current = fn
  useEffect(() => {
    let alive = true
    let timer
    const tick = async () => {
      await ref.current()
      if (alive) timer = setTimeout(tick, ms)
    }
    tick()
    return () => { alive = false; clearTimeout(timer) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps || [])
}

export function useAction() {
  const [busy, setBusy] = useState(false)
  const run = useCallback(async (fn) => {
    setBusy(true)
    try { return await fn() } finally { setBusy(false) }
  }, [])
  return [busy, run]
}

export function ago(seconds, now) {
  const diff = Math.max(0, (now || Date.now() / 1000) - seconds)
  if (diff < 60) return `${Math.floor(diff)}s`
  if (diff < 3600) return `${Math.floor(diff / 60)}m`
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`
  return `${Math.floor(diff / 86400)}d`
}

export function stamp(seconds) {
  if (!seconds) return '—'
  const d = new Date(seconds * 1000)
  return d.toLocaleString(undefined, { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
}

export function steam64(hex) {
  if (!hex || !/^[0-9a-f]+$/i.test(hex)) return null
  try { return BigInt('0x' + hex).toString() } catch { return null }
}
