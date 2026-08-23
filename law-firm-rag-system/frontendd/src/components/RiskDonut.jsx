import { useId } from 'react'

/**
 * Risk distribution as a donut.
 *
 * Drawn with plain SVG arithmetic rather than a charting dependency: the whole
 * figure is four arcs, and adding a 40 kB library to draw four arcs would be a
 * poor trade. Colour is never the only signal — every slice is also labelled
 * with its count in the adjacent legend, and the accessible name states the
 * full distribution.
 */

const SIZE = 168
const STROKE = 20
const RADIUS = (SIZE - STROKE) / 2
const CIRCUMFERENCE = 2 * Math.PI * RADIUS

export default function RiskDonut({ high = 0, medium = 0, low = 0, failed = 0 }) {
  const titleId = useId()
  const segments = [
    { key: 'high',   label: 'High risk',    value: high,   colour: 'var(--risk-high)' },
    { key: 'medium', label: 'Medium risk',  value: medium, colour: 'var(--risk-med)' },
    { key: 'low',    label: 'Low risk',     value: low,    colour: 'var(--risk-low)' },
    { key: 'failed', label: 'Not assessed', value: failed, colour: 'var(--risk-none)' },
  ].filter((segment) => segment.value > 0)

  const total = segments.reduce((sum, segment) => sum + segment.value, 0)

  let offset = 0
  const arcs = segments.map((segment) => {
    const fraction = total > 0 ? segment.value / total : 0
    const arc = {
      ...segment,
      dash: fraction * CIRCUMFERENCE,
      gap: CIRCUMFERENCE - fraction * CIRCUMFERENCE,
      offset: -offset,
    }
    offset += fraction * CIRCUMFERENCE
    return arc
  })

  const description = total
    ? segments.map((segment) => `${segment.value} ${segment.label}`).join(', ')
    : 'No findings yet'

  return (
    <div className="risk-overview">
      <div className="donut-wrap">
        <svg
          className="donut"
          width={SIZE}
          height={SIZE}
          viewBox={`0 0 ${SIZE} ${SIZE}`}
          role="img"
          aria-labelledby={titleId}
        >
          <title id={titleId}>Risk distribution: {description}</title>
          <circle
            className="donut-track"
            cx={SIZE / 2}
            cy={SIZE / 2}
            r={RADIUS}
            fill="none"
            strokeWidth={STROKE}
          />
          {arcs.map((arc) => (
            <circle
              key={arc.key}
              className="donut-segment"
              cx={SIZE / 2}
              cy={SIZE / 2}
              r={RADIUS}
              fill="none"
              stroke={arc.colour}
              strokeWidth={STROKE}
              strokeDasharray={`${arc.dash} ${arc.gap}`}
              strokeDashoffset={arc.offset}
              strokeLinecap="butt"
            />
          ))}
        </svg>
        <div className="donut-centre" aria-hidden="true">
          <span className="donut-centre-value">{total}</span>
          <span className="donut-centre-label">questions</span>
        </div>
      </div>

      <ul className="donut-legend">
        {segments.length === 0 && (
          <li className="donut-legend-item text-muted">No findings to display.</li>
        )}
        {segments.map((segment) => (
          <li className="donut-legend-item" key={segment.key}>
            <span
              className="donut-swatch"
              style={{ background: segment.colour }}
              aria-hidden="true"
            />
            <span className="donut-legend-label">{segment.label}</span>
            <span className="donut-legend-value" style={{ color: segment.colour }}>
              {segment.value}
            </span>
            <span className="text-muted" style={{ fontSize: 'var(--fs-xs)' }}>
              {total ? `${Math.round((segment.value / total) * 100)}%` : '0%'}
            </span>
          </li>
        ))}
      </ul>
    </div>
  )
}
