import { useCallback, useEffect, useMemo, useState } from 'react'

import DownloadPanel from './components/DownloadPanel'
import ProgressBar from './components/ProgressBar'
import QAPanel from './components/QAPanel'
import ResultPanel from './components/ResultPanel'
import Toasts from './components/Toasts'
import UploadPanel from './components/UploadPanel'
import useToasts from './hooks/useToasts'
import { deleteSession, getResults, getStatus } from './lib/api'

/**
 * Application shell and state machine.
 *
 * Two behaviours the previous shell lacked:
 *
 * • **Session resume.**  A page refresh mid-review discarded the session id, so
 *   a review that was still running on the server became permanently
 *   unreachable and had to be paid for again. The id is now kept in
 *   sessionStorage and rehydrated on mount.
 * • **Real tab semantics.**  The tabs were plain buttons with no roles, so
 *   assistive technology announced them as unlabelled controls and arrow-key
 *   navigation did nothing. They now implement the WAI-ARIA tabs pattern.
 */

const STORAGE_KEY = 'legal-rag.session'

const TABS = [
  { id: 'checklist', icon: '📋', label: 'Review findings' },
  { id: 'qa', icon: '💬', label: 'Ask a question' },
  { id: 'download', icon: '⬇️', label: 'Download memo' },
]

export default function App() {
  const [sessionId, setSessionId] = useState(null)
  const [results, setResults] = useState(null)
  const [phase, setPhase] = useState('idle') // idle | running | complete | failed
  const [activeTab, setActiveTab] = useState('checklist')
  // Derived at mount rather than defaulted to true and corrected inside the
  // effect: with no stored session there is nothing to rehydrate, so the
  // upload form should render on the first paint with no flash.
  const [rehydrating, setRehydrating] = useState(
    () => Boolean(sessionStorage.getItem(STORAGE_KEY)),
  )

  const { toasts, dismiss, notify, success, error: notifyError } = useToasts()

  /* ── Resume an interrupted session across a refresh ─────────────────── */
  useEffect(() => {
    let cancelled = false
    const stored = sessionStorage.getItem(STORAGE_KEY)
    if (!stored) return undefined

    getStatus(stored)
      .then(async (status) => {
        if (cancelled) return
        setSessionId(stored)
        if (status.status === 'complete') {
          const payload = await getResults(stored)
          if (cancelled) return
          setResults(payload)
          setPhase('complete')
          notify('Resumed your previous review.', { variant: 'info' })
        } else if (status.status === 'failed') {
          setPhase('failed')
        } else {
          setPhase('running')
          notify('Resumed a review that is still in progress.', { variant: 'info' })
        }
      })
      .catch(() => {
        // The session expired or the server is down — start clean rather than
        // leaving the user staring at a spinner for a session that is gone.
        sessionStorage.removeItem(STORAGE_KEY)
      })
      .finally(() => {
        if (!cancelled) setRehydrating(false)
      })

    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const handleSessionStart = useCallback(
    (id) => {
      sessionStorage.setItem(STORAGE_KEY, id)
      setSessionId(id)
      setResults(null)
      setPhase('running')
      setActiveTab('checklist')
      notify('Bundle uploaded — the review has started.', { variant: 'info' })
    },
    [notify],
  )

  const handleComplete = useCallback(
    (payload) => {
      setResults(payload)
      setPhase('complete')
      const high = payload.high_risk_count || 0
      const flags = (payload.red_flags || []).length
      success(
        flags > 0
          ? `Review complete — ${high} high-risk item${high === 1 ? '' : 's'} and ` +
              `${flags} red flag${flags === 1 ? '' : 's'}.`
          : `Review complete — ${high} high-risk item${high === 1 ? '' : 's'}.`,
      )
    },
    [success],
  )

  const handleFailure = useCallback(
    (message) => {
      setPhase('failed')
      notifyError(message)
    },
    [notifyError],
  )

  const handleReset = useCallback(async () => {
    const previous = sessionId
    sessionStorage.removeItem(STORAGE_KEY)
    setSessionId(null)
    setResults(null)
    setPhase('idle')
    setActiveTab('checklist')
    if (previous) {
      // Best-effort: discharge the firm's retention policy immediately rather
      // than waiting for the TTL to elapse.
      try {
        await deleteSession(previous)
      } catch {
        /* the cleanup worker will collect it */
      }
    }
  }, [sessionId])

  const onTabKeyDown = (event, index) => {
    const keys = { ArrowRight: 1, ArrowLeft: -1 }
    if (event.key in keys) {
      event.preventDefault()
      const next = (index + keys[event.key] + TABS.length) % TABS.length
      setActiveTab(TABS[next].id)
      document.getElementById(`tab-${TABS[next].id}`)?.focus()
    } else if (event.key === 'Home') {
      event.preventDefault()
      setActiveTab(TABS[0].id)
    } else if (event.key === 'End') {
      event.preventDefault()
      setActiveTab(TABS[TABS.length - 1].id)
    }
  }

  const stats = useMemo(
    () => [
      { value: '15–21', label: 'Diligence questions' },
      { value: '9', label: 'Red-flag rules' },
      { value: '4', label: 'City authorities' },
      { value: '2', label: 'Output formats' },
    ],
    [],
  )

  const flagCount = (results?.red_flags || []).length

  return (
    <div className="app">
      <a className="skip-link" href="#main">Skip to main content</a>

      <header className="app-header">
        <span className="header-badge">
          <span aria-hidden="true">⚖️</span> AI-assisted legal due diligence
        </span>
        <h1>Legal RAG System</h1>
        <p>
          First-pass due diligence review for Pakistani property, lending and
          corporate acquisition transactions.
        </p>
        <div className="header-stats">
          {stats.map((stat) => (
            <div className="header-stat" key={stat.label}>
              <span className="header-stat-value">{stat.value}</span>
              <span className="header-stat-label">{stat.label}</span>
            </div>
          ))}
        </div>
      </header>

      <main className="app-main" id="main">
        {rehydrating && (
          <div className="panel" aria-busy="true">
            <p className="text-muted">Checking for an existing review…</p>
          </div>
        )}

        {!rehydrating && phase === 'idle' && (
          <UploadPanel onSessionStart={handleSessionStart} notify={notify} />
        )}

        {!rehydrating && (phase === 'running' || phase === 'failed') && sessionId && (
          <ProgressBar
            sessionId={sessionId}
            onComplete={handleComplete}
            onFailure={handleFailure}
            onCancel={handleReset}
          />
        )}

        {!rehydrating && phase === 'complete' && results && (
          <>
            <div className="tab-bar" role="tablist" aria-label="Review sections">
              {TABS.map((tab, index) => (
                <button
                  key={tab.id}
                  id={`tab-${tab.id}`}
                  type="button"
                  role="tab"
                  className="tab-btn"
                  aria-selected={activeTab === tab.id}
                  aria-controls={`panel-${tab.id}`}
                  tabIndex={activeTab === tab.id ? 0 : -1}
                  onClick={() => setActiveTab(tab.id)}
                  onKeyDown={(event) => onTabKeyDown(event, index)}
                >
                  <span aria-hidden="true">{tab.icon}</span> {tab.label}
                  {tab.id === 'checklist' && flagCount > 0 && (
                    <span className="tab-count" aria-label={`${flagCount} red flags`}>
                      {flagCount}
                    </span>
                  )}
                </button>
              ))}
            </div>

            <div
              id="panel-checklist"
              role="tabpanel"
              aria-labelledby="tab-checklist"
              hidden={activeTab !== 'checklist'}
              tabIndex={0}
            >
              {activeTab === 'checklist' && <ResultPanel results={results} />}
            </div>

            <div
              id="panel-qa"
              role="tabpanel"
              aria-labelledby="tab-qa"
              hidden={activeTab !== 'qa'}
              tabIndex={0}
            >
              {activeTab === 'qa' && <QAPanel sessionId={sessionId} notify={notify} />}
            </div>

            <div
              id="panel-download"
              role="tabpanel"
              aria-labelledby="tab-download"
              hidden={activeTab !== 'download'}
              tabIndex={0}
            >
              {activeTab === 'download' && (
                <DownloadPanel sessionId={sessionId} results={results} notify={notify} />
              )}
            </div>

            <div className="btn-row mt-4">
              <button type="button" className="btn btn-secondary" onClick={handleReset}>
                <span aria-hidden="true">🔄</span> Start a new review
              </button>
            </div>
          </>
        )}
      </main>

      <footer className="app-footer">
        <p>
          <strong>Legal RAG System</strong> — an AI-supported first-pass review. Every
          memorandum must be verified and approved by a qualified Pakistani advocate
          before it is relied upon.
        </p>
      </footer>

      <Toasts toasts={toasts} onDismiss={dismiss} />
    </div>
  )
}
