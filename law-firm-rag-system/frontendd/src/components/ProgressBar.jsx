import useSessionPolling from '../hooks/useSessionPolling'

/**
 * Live pipeline progress.
 *
 * The polling logic moved into `useSessionPolling`, which fixes overlapping
 * requests, silent network failures and unmount leaks. What remains here is
 * presentation — plus the accessibility the previous version lacked entirely:
 * the bar is a real `progressbar` and stage changes are announced politely.
 */

const STAGES = [
  { key: 'extracting', label: 'Extract', step: '1' },
  { key: 'indexing',   label: 'Index',   step: '2' },
  { key: 'analysing',  label: 'Analyse', step: '3' },
  { key: 'generating', label: 'Generate', step: '4' },
  { key: 'complete',   label: 'Done',    step: '✓' },
]

export default function ProgressBar({ sessionId, onComplete, onFailure, onCancel }) {
  const { status, progress, label, error } = useSessionPolling(sessionId, {
    onComplete,
    onError: onFailure,
  })

  const currentIndex = STAGES.findIndex((stage) => stage.key === status)
  const failed = status === 'failed' || Boolean(error)

  return (
    <section className="panel progress-panel" aria-labelledby="progress-heading">
      <h2 id="progress-heading">Reviewing your documents</h2>
      <p className="panel-subtitle">
        The bundle is being read, indexed and interrogated against Pakistani
        statutes. You can leave this page open — the review continues on the server.
      </p>

      <ol className="stage-steps" aria-label="Pipeline stages">
        {STAGES.map((stage, index) => {
          const done = currentIndex > index || status === 'complete'
          const active = currentIndex === index && status !== 'complete'
          return (
            <li
              key={stage.key}
              className={`stage-step${done ? ' done' : ''}`}
              aria-current={active ? 'step' : undefined}
            >
              <span
                className={`stage-dot${done ? ' done' : active ? ' active' : ''}`}
                aria-hidden="true"
              >
                {done ? '✓' : stage.step}
              </span>
              <span
                className={`stage-label-text${done ? ' done' : active ? ' active' : ''}`}
              >
                {stage.label}
              </span>
              <span className="sr-only">
                {done ? 'completed' : active ? 'in progress' : 'pending'}
              </span>
            </li>
          )
        })}
      </ol>

      <p className="stage-label" aria-live="polite" aria-atomic="true">
        {failed
          ? error || 'The review could not be completed.'
          : label || 'Preparing the review…'}
      </p>

      <div
        className="progress-track"
        role="progressbar"
        aria-valuenow={progress}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label="Review progress"
      >
        <div className="progress-fill" style={{ width: `${Math.max(progress, 2)}%` }} />
      </div>
      <p className="progress-pct">{progress}% complete</p>

      {failed && (
        <div className="alert alert-error mt-4" role="alert">
          <span aria-hidden="true">⚠</span>
          <div className="alert-body">
            <div className="alert-title">The review stopped</div>
            <div className="alert-detail">
              {error || 'An unexpected error ended the pipeline.'}
            </div>
          </div>
        </div>
      )}

      <p className="hint">
        Typically two to five minutes, depending on bundle size and how many pages
        need OCR. Rate limits are handled automatically with backoff.
      </p>

      {onCancel && (
        <div className="btn-row" style={{ justifyContent: 'center', marginTop: 'var(--s-4)' }}>
          <button type="button" className="btn btn-ghost" onClick={onCancel}>
            {failed ? 'Start a new review' : 'Cancel and start over'}
          </button>
        </div>
      )}
    </section>
  )
}
