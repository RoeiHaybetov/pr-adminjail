import { Building2, Globe2, Lock, Hash } from 'lucide-react'
import { useT } from '../lib'
import { usePanel } from './core'

const MODE_ICONS = { yard: Building2, solitary: Lock, public: Globe2, custom: Hash }

/** Yard + bucket mode + custom bucket — used by the jail form and the move dialog. */
export function PlacementFields({ yard, setYard, mode, setMode, bucket, setBucket }) {
  const t = useT()
  const { boot } = usePanel()
  const cfg = boot.config
  const selected = boot.yards.find((y) => y.key === yard)

  const MODE_TEXT = {
    yard: [t('ui.mode.yard', 'Yard'), selected ? t('ui.mode.yard_sub', 'bucket %s', selected.bucket) : ''],
    solitary: [t('ui.mode.solitary', 'Solitary'), t('ui.mode.solitary_sub', 'own bucket')],
    public: [t('ui.mode.public', 'Public'), t('ui.mode.public_sub', 'main world')],
    custom: [t('ui.mode.custom', 'Custom'), t('ui.mode.custom_sub', 'any bucket')],
  }

  return (
    <>
      <div className="field">
        <div className="label">{t('ui.jail.yard', 'Yard')}</div>
        <select className="select" value={yard} onChange={(e) => setYard(e.target.value)}>
          {boot.yards.map((y) => (
            <option key={y.key} value={y.key}>{y.label} · {t('ui.jail.spots', '%s spots', y.spots)}</option>
          ))}
        </select>
      </div>

      <div className="field">
        <div className="label">{t('ui.jail.bucket', 'Bucket')}<span className="hint">{t('ui.jail.bucket_hint', 'where they serve')}</span></div>
        <div className="seg">
          {cfg.bucketModes.map((m) => {
            const Icon = MODE_ICONS[m]
            return (
              <button key={m} className={mode === m ? 'on' : ''} onClick={() => setMode(m)}>
                <Icon size={16} />
                {MODE_TEXT[m][0]}
                <small>{MODE_TEXT[m][1]}</small>
              </button>
            )
          })}
        </div>
        {mode === 'custom' && (
          <input
            className="input num" style={{ marginTop: 8 }} type="number"
            min={cfg.customMin} max={cfg.customMax} value={bucket}
            placeholder={t('ui.jail.bucket_number', 'Bucket number (%s – %s)', cfg.customMin, cfg.customMax)}
            onChange={(e) => setBucket(e.target.value)}
          />
        )}
        {mode === 'public' && (
          <div className="small dim" style={{ marginTop: 8 }}>
            {t('ui.mode.public_note', 'Everyone can see them working. The leash still holds.')}
          </div>
        )}
      </div>
    </>
  )
}
