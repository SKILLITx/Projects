/** Small formatting helpers shared across components. */

export const RISK_LEVELS = ['HIGH', 'MEDIUM', 'LOW']

export const RISK_META = {
  HIGH:   { label: 'High risk',   token: 'var(--risk-high)', short: 'HIGH' },
  MEDIUM: { label: 'Medium risk', token: 'var(--risk-med)',  short: 'MED'  },
  LOW:    { label: 'Low risk',    token: 'var(--risk-low)',  short: 'LOW'  },
}

export const normaliseRisk = (value) => {
  const text = String(value ?? '').toUpperCase()
  return RISK_LEVELS.includes(text) ? text : 'LOW'
}

export function formatBytes(bytes) {
  const value = Number(bytes) || 0
  if (value < 1024) return `${value} B`
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(0)} KB`
  return `${(value / (1024 * 1024)).toFixed(1)} MB`
}

export function formatDuration(seconds) {
  const total = Math.max(0, Math.round(Number(seconds) || 0))
  if (total < 60) return `${total}s`
  const minutes = Math.floor(total / 60)
  const remainder = total % 60
  return remainder ? `${minutes}m ${remainder}s` : `${minutes}m`
}

export const titleCase = (value) =>
  String(value ?? '')
    .split(/[\s_-]+/)
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ')

export const truncate = (value, limit = 90) => {
  const text = String(value ?? '')
  return text.length > limit ? `${text.slice(0, limit - 1)}…` : text
}
