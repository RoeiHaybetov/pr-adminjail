import {
  Brush, Droplets, Trash2, Wind, Sprout, SprayCan, Hammer, Hand, Wrench,
} from 'lucide-react'

const JOB_ICONS = {
  broom: Brush,
  mop: Droplets,
  trash: Trash2,
  wind: Wind,
  sprout: Sprout,
  spray: SprayCan,
  hammer: Hammer,
  hand: Hand,
}

export function JobIcon({ name, size = 18 }) {
  const Icon = JOB_ICONS[name] || Wrench
  return <Icon size={size} />
}
