import { useDeferredValue, useMemo, useState } from 'react'

import RiskDonut from './RiskDonut'
import { RISK_LEVELS, normaliseRisk, titleCase } from '../lib/format'

/**
 * Findings triage.
 *
 * The previous version rendered every finding fully expanded in question order,
 * which on a nineteen-question review meant a partner scrolled past four screens
 * of LOW-risk prose before reaching the first HIGH-risk item. Findings are now
 * sorted by risk, collapsed by default with HIGH auto-expanded, and filterable
 * by risk level, topic and free text.
 */

const RISK_RANK = { HIGH: 0, MEDIUM: 1, LOW: 2 }

function FindingCard({ finding, defaultOpen }) {
  const [open, setOpen] = useState(defaultOpen)
  const risk = normaliseRisk(finding.risk_level)
  const bodyId = `finding-body-${finding.question_id}`
  const missing = finding.missing_documents || []

  return (
    <article className={`finding-card ${risk.toLowerCase()}`}>
      <button
        type="button"
        className="finding-card-header"
        aria-expanded={open}
        aria-controls={bodyId}
        onClick={() => setOpen((value) => !value)}
      >
        <span className="q-number">Q{finding.question_id}</span>
        <span className="question-text">{finding.question}</span>
        <span className={`risk-badge ${risk}`}>{risk}</span>
        <span className="chevron" aria-hidden="true">▾</span>
      </button>

      {open && (
        <div className="finding-card-body" id={bodyId}>
          <div className="finding-row">
            <span className="finding-row-label">Finding</span>
            <span className="finding-row-value">{finding.finding || '—'}</span>
          </div>

          {finding.reasoning && (
            <div className="finding-row">
              <span className="finding-row-label">Reasoning</span>
              <span className="finding-row-value">{finding.reasoning}</span>
            </div>
          )}

          <div className="finding-row">
            <span className="finding-row-label">Citations</span>
            <span className="finding-row-value">
              {finding.document_citation && (
                <span className="citation-chip">
                  <span aria-hidden="true">📄</span> {finding.document_citation}
                </span>
              )}
              {finding.statutory_citation && (
                <span className="citation-chip statute">
                  <span aria-hidden="true">⚖</span> {finding.statutory_citation}
                </span>
              )}
              {finding.constitutional_basis && (
                <span className="citation-chip constitution">
                  <span aria-hidden="true">🏛</span> {finding.constitutional_basis}
                </span>
              )}
            </span>
          </div>

          <div className="finding-row">
            <span className="finding-row-label">Recommendation</span>
            <span className="finding-row-value">{finding.recommendation || '—'}</span>
          </div>

          {missing.length > 0 && (
            <div className="finding-row">
              <span className="finding-row-label">Documents required</span>
              <span className="finding-row-value">
                {missing.map((document) => (
                  <span className="missing-tag" key={document}>
                    <span aria-hidden="true">⚠</span>&nbsp;{document}
                  </span>
                ))}
              </span>
            </div>
          )}

          {(finding.confidence || finding.failed) && (
            <div className="finding-row">
              <span className="finding-row-label">Assessment</span>
              <span className="finding-row-value text-muted">
                {finding.failed
                  ? 'This question could not be assessed automatically — manual review required.'
                  : `Model confidence: ${finding.confidence}`}
                {finding.client_chunks != null && !finding.failed && (
                  <>
                    {' · '}
                    {finding.client_chunks} document extract
                    {finding.client_chunks === 1 ? '' : 's'} and {finding.statute_chunks}{' '}
                    statute extract{finding.statute_chunks === 1 ? '' : 's'} consulted
                  </>
                )}
              </span>
            </div>
          )}
        </div>
      )}
    </article>
  )
}

export default function ResultPanel({ results }) {
  const [riskFilter, setRiskFilter] = useState(new Set())
  const [topicFilter, setTopicFilter] = useState('')
  const [search, setSearch] = useState('')
  const deferredSearch = useDeferredValue(search)

  // `results.findings || []` creates a new array identity on every render when
  // the field is absent, which would invalidate every downstream useMemo.
  const findings = useMemo(() => results.findings ?? [], [results.findings])
  const redFlags = useMemo(() => results.red_flags ?? [], [results.red_flags])

  const topics = useMemo(
    () => [...new Set(findings.map((finding) => finding.topic).filter(Boolean))].sort(),
    [findings],
  )

  const sorted = useMemo(
    () =>
      [...findings].sort((a, b) => {
        const rankDelta =
          (RISK_RANK[normaliseRisk(a.risk_level)] ?? 3) -
          (RISK_RANK[normaliseRisk(b.risk_level)] ?? 3)
        return rankDelta !== 0 ? rankDelta : (a.question_id || 0) - (b.question_id || 0)
      }),
    [findings],
  )

  const visible = useMemo(() => {
    const needle = deferredSearch.trim().toLowerCase()
    return sorted.filter((finding) => {
      if (riskFilter.size && !riskFilter.has(normaliseRisk(finding.risk_level))) return false
      if (topicFilter && finding.topic !== topicFilter) return false
      if (!needle) return true
      return [
        finding.question, finding.finding, finding.reasoning,
        finding.recommendation, finding.statutory_citation,
        finding.document_citation, finding.constitutional_basis,
      ]
        .filter(Boolean)
        .some((field) => String(field).toLowerCase().includes(needle))
    })
  }, [sorted, riskFilter, topicFilter, deferredSearch])

  const toggleRisk = (level) =>
    setRiskFilter((current) => {
      const next = new Set(current)
      if (next.has(level)) next.delete(level)
      else next.add(level)
      return next
    })

  const clearFilters = () => {
    setRiskFilter(new Set())
    setTopicFilter('')
    setSearch('')
  }

  const filtersActive = riskFilter.size > 0 || Boolean(topicFilter) || Boolean(search.trim())

  return (
    <section className="panel result-panel" aria-labelledby="results-heading">
      <h2 id="results-heading">Due diligence findings</h2>
      <p className="panel-subtitle">
        {findings.length} question{findings.length === 1 ? '' : 's'} assessed
        {results.authority_full_name ? ` against ${results.authority_full_name}` : ''}
        {results.elapsed_seconds ? ` in ${Math.round(results.elapsed_seconds)} seconds` : ''}.
        {redFlags.length > 0
          ? ` ${redFlags.length} red flag${redFlags.length === 1 ? '' : 's'} raised.`
          : ' No red flags raised.'}
      </p>

      <RiskDonut
        high={results.high_risk_count || 0}
        medium={results.medium_risk_count || 0}
        low={results.low_risk_count || 0}
        failed={results.failed_count || 0}
      />

      <div className="risk-summary">
        {[
          { key: 'high', label: 'High risk', value: results.high_risk_count || 0 },
          { key: 'medium', label: 'Medium risk', value: results.medium_risk_count || 0 },
          { key: 'low', label: 'Low risk', value: results.low_risk_count || 0 },
          { key: 'none', label: 'Not assessed', value: results.failed_count || 0 },
        ].map((box) => (
          <div className={`risk-box ${box.key}`} key={box.key}>
            <span className="risk-box-count">{box.value}</span>
            <span className="risk-box-label">{box.label}</span>
          </div>
        ))}
      </div>

      {redFlags.length > 0 ? (
        <div className="red-flags-section">
          <div className="red-flags-header">
            <span aria-hidden="true">🚨</span>
            <h3 style={{ fontSize: 'var(--fs-md)' }}>Red flags requiring attention</h3>
          </div>
          {redFlags.map((flag) => (
            <div className="flag-item" key={flag.id}>
              <span className="flag-dot" aria-hidden="true" />
              <div className="flag-content">
                <div className="flag-label">[{flag.id}] {flag.label}</div>
                {flag.description && (
                  <div className="flag-description">{flag.description}</div>
                )}
                <div className="flag-statute">
                  {flag.statute}
                  {flag.article ? ` · ${flag.article}` : ''}
                </div>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="no-issues">
          <span aria-hidden="true">✓</span>
          <div>
            No transaction-stopping defect was detected in this bundle. This is not a
            warranty of clean title — it records only that the deterministic rules did
            not fire.
          </div>
        </div>
      )}

      {(results.missing_documents || []).length > 0 && (
        <div className="alert alert-warning" role="note">
          <span aria-hidden="true">📋</span>
          <div className="alert-body">
            <div className="alert-title">
              {results.missing_documents.length} document
              {results.missing_documents.length === 1 ? '' : 's'} to requisition
            </div>
            <div className="alert-detail">{results.missing_documents.join(' · ')}</div>
          </div>
        </div>
      )}

      <h3 className="section-heading">Clause-by-clause findings</h3>

      <div className="toolbar">
        <div className="toolbar-search">
          <label className="sr-only" htmlFor="finding-search">Search findings</label>
          <input
            id="finding-search"
            type="search"
            className="text-input"
            placeholder="Search findings, statutes or recommendations…"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
          />
        </div>

        <div className="chip-row" role="group" aria-label="Filter by risk level">
          {RISK_LEVELS.map((level) => (
            <button
              key={level}
              type="button"
              className={`chip ${level.toLowerCase()}`}
              aria-pressed={riskFilter.has(level)}
              onClick={() => toggleRisk(level)}
            >
              {titleCase(level)}
            </button>
          ))}
        </div>

        {topics.length > 1 && (
          <div className="field-group" style={{ margin: 0, minWidth: '170px' }}>
            <label className="sr-only" htmlFor="topic-filter">Filter by topic</label>
            <select
              id="topic-filter"
              className="select-input"
              value={topicFilter}
              onChange={(event) => setTopicFilter(event.target.value)}
            >
              <option value="">All topics</option>
              {topics.map((topic) => (
                <option key={topic} value={topic}>{titleCase(topic)}</option>
              ))}
            </select>
          </div>
        )}

        {filtersActive && (
          <button type="button" className="btn btn-ghost" onClick={clearFilters}>
            Clear filters
          </button>
        )}
      </div>

      <p className="sr-only" aria-live="polite">
        Showing {visible.length} of {findings.length} findings.
      </p>

      <div className="findings-list">
        {visible.length === 0 ? (
          <p className="empty-state">
            No findings match the current filters.{' '}
            {filtersActive && (
              <button type="button" className="btn btn-ghost" onClick={clearFilters}>
                Clear filters
              </button>
            )}
          </p>
        ) : (
          visible.map((finding) => (
            <FindingCard
              key={finding.question_id}
              finding={finding}
              defaultOpen={normaliseRisk(finding.risk_level) === 'HIGH'}
            />
          ))
        )}
      </div>
    </section>
  )
}
