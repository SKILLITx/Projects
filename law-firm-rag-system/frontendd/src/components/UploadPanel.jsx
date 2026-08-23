import { useEffect, useMemo, useRef, useState } from 'react'

import { getOptions, uploadBundle } from '../lib/api'
import { formatBytes, titleCase } from '../lib/format'

/**
 * Bundle upload and review configuration.
 *
 * The previous version hard-coded the city list, the housing-society list and
 * both firm letterheads as JavaScript constants — duplicating server-side JSON
 * that the server never even read. Everything is now fetched from
 * `/api/options`, so adding a city is a server-side change only.
 *
 * It also validated nothing beyond the file extension, and offered no way to
 * remove a file once selected.
 */

const FALLBACK_OPTIONS = {
  transaction_types: ['property', 'loan', 'acquisition'],
  cities: [{ key: 'islamabad', label: 'Islamabad', authority: 'CDA' }],
  housing_societies: [],
  firm_profiles: {},
  limits: { max_files: 10, max_file_mb: 50, max_bundle_mb: 150 },
}

const PDF_SIGNATURE = '%PDF-'

/** Read the first bytes so a renamed .docx is caught before it is uploaded. */
async function looksLikePdf(file) {
  try {
    const header = await file.slice(0, 5).text()
    return header === PDF_SIGNATURE
  } catch {
    return true // if the browser will not let us peek, defer to the server
  }
}

export default function UploadPanel({ onSessionStart, notify }) {
  const [options, setOptions] = useState(FALLBACK_OPTIONS)
  const [optionsError, setOptionsError] = useState(null)

  const [files, setFiles] = useState([])
  const [transactionType, setTransactionType] = useState('property')
  const [city, setCity] = useState('islamabad')
  const [society, setSociety] = useState('')
  const [firmKey, setFirmKey] = useState('custom')
  const [firm, setFirm] = useState({
    name: '', address: '', phone: '', email: '', tagline: '',
  })

  const [uploading, setUploading] = useState(false)
  const [uploadPct, setUploadPct] = useState(0)
  const [errors, setErrors] = useState([])
  const [dragging, setDragging] = useState(false)

  const inputRef = useRef(null)
  const dragDepth = useRef(0)

  useEffect(() => {
    let cancelled = false
    getOptions()
      .then((payload) => {
        if (cancelled) return
        setOptions({ ...FALLBACK_OPTIONS, ...payload })
        if (payload.cities?.length) setCity(payload.cities[0].key)
      })
      .catch((error) => {
        if (cancelled) return
        setOptionsError(error.message)
      })
    return () => {
      cancelled = true
    }
  }, [])

  const limits = options.limits ?? FALLBACK_OPTIONS.limits
  const selectedCity = useMemo(
    () => options.cities?.find((entry) => entry.key === city),
    [options.cities, city],
  )
  const totalBytes = useMemo(
    () => files.reduce((sum, file) => sum + file.size, 0),
    [files],
  )

  function applyFirmProfile(key) {
    setFirmKey(key)
    const profile = options.firm_profiles?.[key]
    if (profile) {
      setFirm({
        name: profile.name || '',
        address: profile.address || '',
        phone: profile.phone || '',
        email: profile.email || '',
        tagline: profile.tagline || '',
      })
    } else {
      setFirm({ name: '', address: '', phone: '', email: '', tagline: '' })
    }
  }

  async function addFiles(fileList) {
    const incoming = Array.from(fileList || [])
    if (!incoming.length) return

    const problems = []
    const accepted = []
    const existing = new Set(files.map((file) => `${file.name}:${file.size}`))

    for (const file of incoming) {
      const key = `${file.name}:${file.size}`
      if (existing.has(key)) {
        problems.push(`${file.name} was already added.`)
        continue
      }
      if (!file.name.toLowerCase().endsWith('.pdf')) {
        problems.push(`${file.name} is not a PDF.`)
        continue
      }
      if (file.size === 0) {
        problems.push(`${file.name} is empty.`)
        continue
      }
      if (file.size > limits.max_file_mb * 1024 * 1024) {
        problems.push(`${file.name} exceeds the ${limits.max_file_mb} MB per-file limit.`)
        continue
      }
      if (!(await looksLikePdf(file))) {
        problems.push(`${file.name} has a .pdf name but is not a PDF file.`)
        continue
      }
      existing.add(key)
      accepted.push(file)
    }

    const combined = [...files, ...accepted]
    if (combined.length > limits.max_files) {
      problems.push(`A review accepts at most ${limits.max_files} files.`)
      combined.length = limits.max_files
    }
    const bundleBytes = combined.reduce((sum, file) => sum + file.size, 0)
    if (bundleBytes > limits.max_bundle_mb * 1024 * 1024) {
      problems.push(`The bundle exceeds the ${limits.max_bundle_mb} MB total limit.`)
    }

    setFiles(combined)
    setErrors(problems)
    if (problems.length) notify?.(problems[0], { variant: 'warning' })
  }

  const removeFile = (index) => {
    setFiles((current) => current.filter((_, position) => position !== index))
    setErrors([])
  }

  async function handleSubmit(event) {
    event.preventDefault()
    if (!files.length) {
      setErrors(['Select at least one PDF before running the review.'])
      return
    }

    setUploading(true)
    setUploadPct(0)
    setErrors([])

    const form = new FormData()
    files.forEach((file) => form.append('files', file))
    form.append('transaction_type', transactionType)
    form.append('city', city)
    form.append('housing_society', society)
    form.append('firm_name', firm.name.trim() || 'Law Firm')
    form.append('firm_address', firm.address.trim())
    form.append('firm_phone', firm.phone.trim())
    form.append('firm_email', firm.email.trim())
    form.append('firm_tagline', firm.tagline.trim())

    try {
      const payload = await uploadBundle(form, {
        onUploadProgress: (event) => {
          if (event.total) setUploadPct(Math.round((event.loaded / event.total) * 100))
        },
      })
      onSessionStart(payload.session_id)
    } catch (error) {
      setErrors([error.message])
      notify?.(error.message, { variant: 'error' })
    } finally {
      setUploading(false)
      setUploadPct(0)
    }
  }

  return (
    <form className="panel upload-panel" onSubmit={handleSubmit} noValidate>
      <h2>Upload legal documents</h2>
      <p className="panel-subtitle">
        Add the PDF bundle and set the review parameters. The system runs a full due
        diligence analysis against your documents and the indexed Pakistani statutes,
        then produces a branded memorandum in Word and PDF.
      </p>

      {optionsError && (
        <div className="alert alert-warning" role="status">
          <span aria-hidden="true">⚠</span>
          <div className="alert-body">
            <div className="alert-title">Using built-in defaults</div>
            <div className="alert-detail">
              The server&rsquo;s configuration could not be loaded: {optionsError}
            </div>
          </div>
        </div>
      )}

      <fieldset>
        <legend>Law firm letterhead</legend>

        <div className="field-group">
          <label className="field-label" htmlFor="firm-profile">Saved profile</label>
          <select
            id="firm-profile"
            className="select-input"
            value={firmKey}
            onChange={(event) => applyFirmProfile(event.target.value)}
          >
            <option value="custom">Enter manually</option>
            {Object.entries(options.firm_profiles || {})
              .filter(([key, profile]) => key !== 'custom' && profile.name)
              .map(([key, profile]) => (
                <option key={key} value={key}>
                  {profile.name}
                </option>
              ))}
          </select>
        </div>

        <div className="field-group">
          <label className="field-label" htmlFor="firm-name">Firm name</label>
          <input
            id="firm-name"
            className="text-input"
            type="text"
            placeholder="e.g. Rana Ijaz &amp; Partners"
            value={firm.name}
            maxLength={200}
            onChange={(event) => setFirm({ ...firm, name: event.target.value })}
          />
          <p className="field-hint">
            Appears on the memorandum letterhead. Leave blank for an unbranded memo.
          </p>
        </div>

        <div className="field-row">
          <div className="field-group">
            <label className="field-label" htmlFor="firm-phone">Phone</label>
            <input
              id="firm-phone"
              className="text-input"
              type="tel"
              placeholder="+92-51-XXXXXXX"
              value={firm.phone}
              maxLength={60}
              onChange={(event) => setFirm({ ...firm, phone: event.target.value })}
            />
          </div>
          <div className="field-group">
            <label className="field-label" htmlFor="firm-email">Email</label>
            <input
              id="firm-email"
              className="text-input"
              type="email"
              placeholder="info@firm.com"
              value={firm.email}
              maxLength={120}
              onChange={(event) => setFirm({ ...firm, email: event.target.value })}
            />
          </div>
        </div>

        <div className="field-group">
          <label className="field-label" htmlFor="firm-address">Address</label>
          <input
            id="firm-address"
            className="text-input"
            type="text"
            placeholder="Chamber number, street, city"
            value={firm.address}
            maxLength={300}
            onChange={(event) => setFirm({ ...firm, address: event.target.value })}
          />
        </div>

        <div className="field-group">
          <label className="field-label" htmlFor="firm-tagline">Tagline</label>
          <input
            id="firm-tagline"
            className="text-input"
            type="text"
            placeholder="Advocates &amp; Legal Consultants"
            value={firm.tagline}
            maxLength={200}
            onChange={(event) => setFirm({ ...firm, tagline: event.target.value })}
          />
        </div>
      </fieldset>

      <fieldset>
        <legend>Review parameters</legend>

        <div className="field-row">
          <div className="field-group">
            <label className="field-label" htmlFor="transaction-type">Transaction type</label>
            <select
              id="transaction-type"
              className="select-input"
              value={transactionType}
              onChange={(event) => setTransactionType(event.target.value)}
            >
              {options.transaction_types.map((type) => (
                <option key={type} value={type}>{titleCase(type)}</option>
              ))}
            </select>
          </div>

          <div className="field-group">
            <label className="field-label" htmlFor="city">City</label>
            <select
              id="city"
              className="select-input"
              value={city}
              onChange={(event) => setCity(event.target.value)}
            >
              {options.cities.map((entry) => (
                <option key={entry.key} value={entry.key}>
                  {entry.label || titleCase(entry.key)}
                  {entry.authority ? ` — ${entry.authority}` : ''}
                </option>
              ))}
            </select>
            {selectedCity?.authority_full_name && (
              <p className="field-hint">
                Checklist questions will be written against{' '}
                {selectedCity.authority_full_name}
                {selectedCity.bylaws ? ` under ${selectedCity.bylaws}` : ''}.
              </p>
            )}
          </div>
        </div>

        {options.housing_societies?.length > 0 && (
          <div className="field-group">
            <label className="field-label" htmlFor="society">
              Housing society <span className="text-muted">(optional)</span>
            </label>
            <select
              id="society"
              className="select-input"
              value={society}
              onChange={(event) => setSociety(event.target.value)}
            >
              <option value="">Not applicable</option>
              {options.housing_societies.map((entry) => (
                <option key={entry.key} value={entry.key}>{entry.key}</option>
              ))}
            </select>
            <p className="field-hint">
              Adds a question covering that society&rsquo;s own transfer formalities.
            </p>
          </div>
        )}
      </fieldset>

      <div className="field-group">
        <span className="field-label" id="documents-label">PDF documents</span>
        <div
          className={`upload-zone${dragging ? ' dragging' : ''}`}
          role="button"
          tabIndex={0}
          aria-labelledby="documents-label"
          aria-describedby="upload-help"
          onClick={() => inputRef.current?.click()}
          onKeyDown={(event) => {
            if (event.key === 'Enter' || event.key === ' ') {
              event.preventDefault()
              inputRef.current?.click()
            }
          }}
          onDragEnter={(event) => {
            event.preventDefault()
            dragDepth.current += 1
            setDragging(true)
          }}
          onDragOver={(event) => event.preventDefault()}
          onDragLeave={(event) => {
            event.preventDefault()
            dragDepth.current -= 1
            if (dragDepth.current <= 0) setDragging(false)
          }}
          onDrop={(event) => {
            event.preventDefault()
            dragDepth.current = 0
            setDragging(false)
            addFiles(event.dataTransfer.files)
          }}
        >
          <input
            ref={inputRef}
            type="file"
            accept="application/pdf,.pdf"
            multiple
            className="sr-only"
            onChange={(event) => {
              addFiles(event.target.files)
              event.target.value = ''
            }}
          />
          <span className="upload-icon" aria-hidden="true">📎</span>
          <h3>{dragging ? 'Drop the files here' : 'Drag and drop PDFs, or browse'}</h3>
          <p id="upload-help">
            Text-based and scanned PDFs · Urdu and English · up to {limits.max_files} files,{' '}
            {limits.max_file_mb} MB each
          </p>
        </div>

        {files.length > 0 && (
          <>
            <ul className="file-list" aria-label="Selected documents">
              {files.map((file, index) => (
                <li className="file-item" key={`${file.name}-${file.size}-${index}`}>
                  <span aria-hidden="true">📄</span>
                  <span className="file-item-name" title={file.name}>{file.name}</span>
                  <span className="file-item-size">{formatBytes(file.size)}</span>
                  <button
                    type="button"
                    className="file-remove"
                    onClick={() => removeFile(index)}
                    aria-label={`Remove ${file.name}`}
                  >
                    ✕
                  </button>
                </li>
              ))}
            </ul>
            <p className="field-hint" aria-live="polite">
              {files.length} file{files.length === 1 ? '' : 's'} · {formatBytes(totalBytes)}{' '}
              of {limits.max_bundle_mb} MB
            </p>
          </>
        )}
      </div>

      {errors.length > 0 && (
        <div className="alert alert-error" role="alert">
          <span aria-hidden="true">⚠</span>
          <div className="alert-body">
            <div className="alert-title">
              {errors.length === 1 ? 'There is a problem' : `${errors.length} problems`}
            </div>
            {errors.map((message) => (
              <div className="alert-detail" key={message}>{message}</div>
            ))}
          </div>
        </div>
      )}

      {uploading && uploadPct > 0 && (
        <div className="field-group" aria-live="polite">
          <div className="progress-track">
            <div className="progress-fill" style={{ width: `${uploadPct}%` }} />
          </div>
          <p className="field-hint">Uploading — {uploadPct}%</p>
        </div>
      )}

      <button className="btn btn-primary" type="submit" disabled={uploading || !files.length}>
        {uploading ? (
          <>
            <span className="spinner" aria-hidden="true" /> Uploading…
          </>
        ) : (
          <>
            <span aria-hidden="true">🔍</span> Run due diligence review
          </>
        )}
      </button>
    </form>
  )
}
