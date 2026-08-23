import { useState } from 'react'

import { downloadMemo } from '../lib/api'

/**
 * Memorandum downloads.
 *
 * The previous version was a bare `<a href>` pointing straight at the API,
 * which meant it could not send an authentication header and gave no feedback
 * when the server returned an error — the browser simply navigated to a JSON
 * body. Downloads are now fetched as blobs with real progress and error states.
 */
export default function DownloadPanel({ sessionId, results, notify }) {
  const [busy, setBusy] = useState(null)
  const available = results?.downloads || { docx: true, pdf: false }

  async function download(format) {
    setBusy(format)
    try {
      await downloadMemo(sessionId, format)
      notify?.(`${format.toUpperCase()} memorandum downloaded.`, { variant: 'success' })
    } catch (error) {
      notify?.(error.message, { variant: 'error' })
    } finally {
      setBusy(null)
    }
  }

  const formats = [
    {
      key: 'docx',
      icon: '📄',
      title: 'Word memorandum',
      blurb: 'Editable .docx on your firm’s letterhead — amend it before it goes out.',
      enabled: available.docx,
    },
    {
      key: 'pdf',
      icon: '📕',
      title: 'PDF memorandum',
      blurb: 'Print-ready and identical in content — for circulation and filing.',
      enabled: available.pdf,
    },
  ]

  return (
    <section className="panel download-panel" aria-labelledby="download-heading">
      <h2 id="download-heading">Your review memorandum is ready</h2>
      <p className="panel-subtitle">
        A structured memorandum with an executive summary, clause-by-clause findings,
        red flags, statutory and constitutional citations, and a tax and AML compliance
        assessment.
      </p>

      <div className="download-grid">
        {formats.map((format) => (
          <div className="download-card" key={format.key}>
            <span className="download-icon-wrap" aria-hidden="true">{format.icon}</span>
            <h3>{format.title}</h3>
            <p>{format.blurb}</p>
            <button
              type="button"
              className="btn btn-secondary"
              disabled={!format.enabled || busy === format.key}
              onClick={() => download(format.key)}
            >
              {busy === format.key ? (
                <>
                  <span className="spinner" aria-hidden="true" /> Preparing…
                </>
              ) : format.enabled ? (
                <>Download .{format.key}</>
              ) : (
                'Not available'
              )}
            </button>
          </div>
        ))}
      </div>

      <div className="download-meta">
        <span>Firm letterhead applied</span>
        <span>Statutory and constitutional citations</span>
        <span>Tax and AML compliance section</span>
        <span>Advocate review disclaimer</span>
      </div>

      <div className="alert alert-info mt-4" role="note">
        <span aria-hidden="true">ℹ</span>
        <div className="alert-body">
          <div className="alert-title">This is a first-pass draft</div>
          <div className="alert-detail">
            Every finding cites the document and provision it rests on so a qualified
            advocate can verify it quickly. It must be reviewed and approved before it
            is relied upon or issued to a client.
          </div>
        </div>
      </div>
    </section>
  )
}
