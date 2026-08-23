import { useRef, useState } from 'react'

import { askQuestion } from '../lib/api'
import { normaliseRisk } from '../lib/format'

/**
 * Free-form counsel Q&A.
 *
 * The previous version discarded the previous answer the moment a new question
 * was asked, so comparing two related questions meant re-asking the first one
 * and paying for the tokens twice. Answers now accumulate into a session
 * history, newest first, and an in-flight request can be cancelled.
 */

const EXAMPLES = [
  'Does this agreement comply with Section 54 of the Transfer of Property Act 1882?',
  'Is the vendor’s title constitutionally protected under Article 23?',
  'What Anti-Money Laundering obligations arise on this transaction?',
  'What stamp duty is payable under the Stamp Act 1899 for this instrument?',
  'Is the mutation validly recorded under the Land Revenue Act 1967?',
]

const MAX_LENGTH = 500

function AnswerCard({ entry }) {
  const risk = normaliseRisk(entry.risk_level)
  return (
    <article className="qa-answer">
      <header className="qa-answer-header">
        <span className={`risk-badge ${risk}`}>{risk}</span>
        <span className="qa-answer-question" title={entry.question}>{entry.question}</span>
      </header>
      <div className="qa-answer-body">
        <div className="finding-row">
          <span className="finding-row-label">Finding</span>
          <span className="finding-row-value">{entry.finding || '—'}</span>
        </div>
        {entry.reasoning && (
          <div className="finding-row">
            <span className="finding-row-label">Reasoning</span>
            <span className="finding-row-value">{entry.reasoning}</span>
          </div>
        )}
        <div className="finding-row">
          <span className="finding-row-label">Citations</span>
          <span className="finding-row-value">
            {entry.document_citation && (
              <span className="citation-chip">
                <span aria-hidden="true">📄</span> {entry.document_citation}
              </span>
            )}
            {entry.statutory_citation && (
              <span className="citation-chip statute">
                <span aria-hidden="true">⚖</span> {entry.statutory_citation}
              </span>
            )}
            {entry.constitutional_basis && (
              <span className="citation-chip constitution">
                <span aria-hidden="true">🏛</span> {entry.constitutional_basis}
              </span>
            )}
          </span>
        </div>
        <div className="finding-row">
          <span className="finding-row-label">Recommendation</span>
          <span className="finding-row-value">{entry.recommendation || '—'}</span>
        </div>
      </div>
    </article>
  )
}

export default function QAPanel({ sessionId, notify }) {
  const [question, setQuestion] = useState('')
  const [history, setHistory] = useState([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)
  const abortRef = useRef(null)
  const inputRef = useRef(null)

  async function ask(event) {
    event?.preventDefault()
    const trimmed = question.trim()
    if (trimmed.length < 3) {
      setError('Please enter a question of at least three characters.')
      return
    }

    setLoading(true)
    setError(null)
    const controller = new AbortController()
    abortRef.current = controller

    try {
      const answer = await askQuestion(sessionId, trimmed, { signal: controller.signal })
      setHistory((current) => [{ ...answer, question: trimmed, key: Date.now() }, ...current])
      setQuestion('')
      inputRef.current?.focus()
    } catch (caught) {
      if (caught?.code === 'cancelled') return
      setError(caught.message)
      notify?.(caught.message, { variant: 'error' })
    } finally {
      setLoading(false)
      abortRef.current = null
    }
  }

  const cancel = () => {
    abortRef.current?.abort()
    setLoading(false)
  }

  return (
    <section className="panel qa-panel" aria-labelledby="qa-heading">
      <h2 id="qa-heading">Ask a legal question</h2>
      <p className="panel-subtitle">
        Every question is answered from your uploaded documents <em>and</em> the indexed
        Pakistani statutes together, with the specific provision cited.
      </p>

      <div className="qa-examples" role="group" aria-label="Example questions">
        {EXAMPLES.map((example) => (
          <button
            key={example}
            type="button"
            className="qa-example-chip"
            onClick={() => {
              setQuestion(example)
              inputRef.current?.focus()
            }}
          >
            {example.length > 62 ? `${example.slice(0, 62)}…` : example}
          </button>
        ))}
      </div>

      <form className="qa-input-row" onSubmit={ask}>
        <label className="sr-only" htmlFor="qa-question">Your question</label>
        <textarea
          id="qa-question"
          ref={inputRef}
          className="qa-input"
          rows={3}
          maxLength={MAX_LENGTH}
          placeholder="e.g. Does this deed satisfy the registration requirements of Section 17?"
          value={question}
          disabled={loading}
          onChange={(event) => setQuestion(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) ask(event)
          }}
        />
        <div className="qa-meta">
          <span>Ctrl + Enter to submit</span>
          <span aria-live="polite">{question.length}/{MAX_LENGTH}</span>
        </div>
        <div className="btn-row">
          <button
            type="submit"
            className="btn btn-secondary"
            disabled={loading || question.trim().length < 3}
          >
            {loading ? (
              <>
                <span className="spinner" aria-hidden="true" /> Querying…
              </>
            ) : (
              'Ask'
            )}
          </button>
          {loading && (
            <button type="button" className="btn btn-ghost" onClick={cancel}>
              Cancel
            </button>
          )}
          {history.length > 0 && (
            <button type="button" className="btn btn-ghost" onClick={() => setHistory([])}>
              Clear history
            </button>
          )}
        </div>
      </form>

      {error && (
        <div className="alert alert-error mt-4" role="alert">
          <span aria-hidden="true">⚠</span>
          <div className="alert-body">{error}</div>
        </div>
      )}

      {history.length > 0 && (
        <div className="qa-history">
          <h3 className="section-heading">
            Answers <span className="text-muted">({history.length})</span>
          </h3>
          {history.map((entry) => (
            <AnswerCard entry={entry} key={entry.key} />
          ))}
        </div>
      )}
    </section>
  )
}
