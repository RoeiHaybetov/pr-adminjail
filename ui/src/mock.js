// Browser-only preview data. Loaded only by `npm run dev` outside FiveM; never in the build.
import { emit, setMock } from './lib'

const now = () => Math.floor(Date.now() / 1000)
const perms = [
  { key: 'jail', label: 'Jail players', desc: 'Sentence online players.' },
  { key: 'offline', label: 'Jail offline', desc: 'Sentence by identifier — served on next join.' },
  { key: 'modify', label: 'Modify sentences', desc: 'Add, remove or set tasks. Move yard or bucket.' },
  { key: 'release', label: 'Release', desc: 'Cancel a sentence early.' },
  { key: 'history', label: 'History & identities', desc: 'See past sentences, the event log and identifiers.' },
]

const inmates = [
  { id: 41, name: 'RoeiH', char: 'Tony Vercetti', source: 12, online: true, total: 300, done: 87, left: 213, penalty: 10, escapes: 2,
    yard: 'bolingbroke', yardLabel: 'Bolingbroke Penitentiary', mode: 'yard', bucket: 7000, reason: 'RDM x3 at Legion Square, then combat-logged',
    staffName: 'Abacus', createdAt: now() - 2700, task: { label: 'Mop the floor', icon: 'mop', stage: 1, stages: 1 } },
  { id: 40, name: 'xX_Sniper_Xx', source: 31, online: true, total: 50, done: 44, left: 6, penalty: 0, escapes: 0,
    yard: 'bolingbroke', yardLabel: 'Bolingbroke Penitentiary', mode: 'solitary', bucket: 7100, reason: 'Fail RP — ignored a robbery',
    staffName: 'Mod Dana', createdAt: now() - 900, task: { label: 'Collect the trash', icon: 'trash', stage: 2, stages: 2 } },
  { id: 37, name: 'offline:discord:2918…', source: null, online: false, total: 100, done: 0, left: 100, penalty: 0, escapes: 0,
    yard: 'bolingbroke', yardLabel: 'Bolingbroke Penitentiary', mode: 'public', bucket: 0, reason: 'Meta-gaming via Discord', staffName: 'Abacus', createdAt: now() - 86400 },
]

const events = [
  { id: 9, sentence_id: 41, kind: 'escape', detail: 'leash · +5 · 141m from the yard', created_at: now() - 120 },
  { id: 8, sentence_id: 40, kind: 'suspicious', detail: 'reached the task 64m away in 1.2s (minimum 5.6s) — teleport? Task re-rolled.', created_at: now() - 400 },
  { id: 7, sentence_id: 40, kind: 'jail', actor_name: 'Mod Dana', detail: '50 tasks · bolingbroke · bucket 7100 (solitary) · Fail RP', created_at: now() - 900 },
  { id: 6, sentence_id: 41, kind: 'modify', actor_name: 'Abacus', detail: 'add 100 · 113 -> 213 left · lied in ticket', created_at: now() - 1500 },
  { id: 5, kind: 'staff_add', actor_name: 'Abacus', detail: 'Mod Dana (2918…) · jail,modify · max 50', created_at: now() - 5000 },
  { id: 4, sentence_id: 36, kind: 'completed', detail: 'served 25 tasks', created_at: now() - 7200 },
]

setMock(async (endpoint, payload) => {
  await new Promise((r) => setTimeout(r, 120))
  if (endpoint === 'close') return { ok: true }
  if (endpoint !== 'panel') return { ok: true }
  const { action } = payload
  switch (action) {
    case 'bootstrap': return {
      ok: true,
      me: { name: 'Abacus', discord: '720720916354564199', isOwner: true, label: 'Owner', perms: perms.map((p) => p.key), maxTasks: 1000 },
      config: { minTasks: 1, maxTasks: 1000, presets: [10, 25, 50, 100, 150, 300], reasonRequired: true, reasonMaxLength: 200,
        defaultYard: 'bolingbroke', bucketModes: ['yard', 'solitary', 'public', 'custom'], defaultMode: 'yard', customMin: 1, customMax: 1000000, penaltyTasks: 5 },
      yards: [{ key: 'bolingbroke', label: 'Bolingbroke Penitentiary', bucket: 7000, spots: 12 }],
      permsCatalog: perms,
    }
    case 'players': return { ok: true, now: now(), players: [
      { source: 3, name: 'Abacus', discord: '720720916354564199', isOwner: true },
      { source: 7, name: 'Mod Dana', discord: '291812345678901234', isStaff: true, char: 'Dana Cruz' },
      { source: 12, name: 'RoeiH', char: 'Tony Vercetti', discord: '1029384756102938475', jailed: 41 },
      { source: 18, name: 'GhostRider', char: 'Luis Lopez', discord: '1112223334445556667' },
      { source: 24, name: 'kiki', char: 'Kira Stone' },
      { source: 31, name: 'xX_Sniper_Xx', discord: '998877665544332211', jailed: 40 },
    ], recent: [
      { token: 'a1', name: 'RageQuitter', source: 44, droppedAt: now() - 95, reason: 'Exiting', discord: '123412341234123412' },
      { token: 'a2', name: 'Lagger', source: 51, droppedAt: now() - 1300, reason: 'Timed out' },
    ] }
    case 'inmates': return { ok: true, now: now(), inmates }
    case 'activity': return { ok: true, events }
    case 'history': return { ok: true, total: 3, page: 1, pageSize: 25, rows: [
      { id: 41, name: 'RoeiH', tasks_done: 87, tasks_total: 300, reason: inmates[0].reason, staff_name: 'Abacus', status: 'active', created_at: now() - 2700 },
      { id: 39, name: 'Mike', tasks_done: 25, tasks_total: 25, reason: 'VDM', staff_name: 'Mod Dana', status: 'completed', created_at: now() - 90000 },
      { id: 38, name: 'Lior', tasks_done: 3, tasks_total: 40, reason: 'Wrong person', staff_name: 'Abacus', status: 'released', created_at: now() - 190000 },
    ] }
    case 'events': return { ok: true, events, sentence: {
      id: 41, name: 'RoeiH', char_name: 'Tony Vercetti', status: 'active', tasks_done: 87, tasks_total: 300, penalty_tasks: 10,
      yard: 'bolingbroke', bucket: 7000, bucket_mode: 'yard', staff_name: 'Abacus', created_at: now() - 2700, reason: inmates[0].reason,
      discord: '1029384756102938475', steam: '110000112345678', license: '3f9a2c1d8e7b6a5f4e3d2c1b0a9f8e7d6c5b4a39', fivem: '1234567',
    } }
    case 'staff': return { ok: true, owners: ['720720916354564199'], staff: [
      { discord: '291812345678901234', label: 'Mod Dana', perms: { jail: true, modify: true }, maxTasks: 50, createdAt: 1, updatedAt: 1 },
      { discord: '381812345678901234', label: 'Senior Admin', perms: { jail: true, offline: true, modify: true, release: true, history: true }, maxTasks: 0, createdAt: 2, updatedAt: 2 },
    ] }
    default: return { ok: true }
  }
})

const params = new URLSearchParams(location.search)
const show = params.get('show') || 'panel'
setTimeout(() => {
  if (show === 'panel') emit('panel', true)
  if (show === 'hud' || show === 'cine') {
    emit('hud', { total: 300, done: 87, left: 213, reason: 'RDM x3 at Legion Square, then combat-logged', staff: 'Abacus',
      yard: 'Bolingbroke Penitentiary', escapes: 2, penalty: 10, penaltyTasks: 5, position: 'top-right' })
    emit('task', { label: 'Collect the trash', stageLabel: 'Throw it in the dumpster', icon: 'trash', stage: 2, stages: 2 })
    emit('taskDistance', 23)
    emit('edge', true)
  }
  if (show === 'cine') emit('cinematic', { kind: 'sentenced', duration: 60000, data: { tasks: 300, reason: 'RDM x3 at Legion Square', staff: 'Abacus' } })
}, 50)
