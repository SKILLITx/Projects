/**
 * Typed client for the Legal RAG API.
 *
 * The previous build scattered raw `axios` calls across four components, each
 * reading `e.response?.data?.detail` — a field the server had already stopped
 * sending in some paths, so several failures surfaced to the lawyer as the
 * literal string "undefined". Every request now goes through one place, and
 * every failure becomes an `ApiError` carrying the server's stable machine
 * code alongside a message written for a human.
 */

import axios from 'axios'

export const API_BASE =
  import.meta.env.VITE_API_URL?.replace(/\/+$/, '') || 'http://localhost:8000'

const API_KEY = import.meta.env.VITE_API_KEY || ''

/** A failure with a stable `code` the UI can branch on. */
export class ApiError extends Error {
  constructor(message, { code = 'unknown_error', status = 0, details = null } = {}) {
    super(message)
    this.name = 'ApiError'
    this.code = code
    this.status = status
    this.details = details
  }

  /** Whether retrying the same request could plausibly succeed. */
  get isRetryable() {
    return this.status === 0 || this.status === 429 || this.status >= 500
  }

  get isNotFound() {
    return this.status === 404
  }

  get isNotReady() {
    return this.code === 'results_not_ready'
  }
}

const client = axios.create({
  baseURL: API_BASE,
  timeout: 60_000,
  headers: API_KEY ? { 'X-API-Key': API_KEY } : {},
})

function toApiError(error) {
  if (axios.isCancel?.(error) || error?.code === 'ERR_CANCELED') {
    return new ApiError('The request was cancelled.', { code: 'cancelled' })
  }

  const response = error?.response
  if (!response) {
    return new ApiError(
      'Could not reach the review server. Check that the backend is running ' +
        `at ${API_BASE}.`,
      { code: 'network_error' },
    )
  }

  const body = response.data
  // The server's envelope: { error: { code, message, details } }
  if (body?.error?.message) {
    return new ApiError(body.error.message, {
      code: body.error.code || 'server_error',
      status: response.status,
      details: body.error.details || null,
    })
  }
  // FastAPI's own validation envelope: { detail: [...] } or { detail: "..." }
  if (body?.detail) {
    const detail = Array.isArray(body.detail)
      ? body.detail.map((d) => d.msg || String(d)).join('; ')
      : String(body.detail)
    return new ApiError(detail, { code: 'validation_error', status: response.status })
  }
  return new ApiError(`Request failed with status ${response.status}.`, {
    code: 'server_error',
    status: response.status,
  })
}

async function request(config) {
  try {
    const response = await client.request(config)
    return response.data
  } catch (error) {
    throw toApiError(error)
  }
}

/* ── Endpoints ─────────────────────────────────────────────────────────── */

export const getOptions = () => request({ url: '/api/options', method: 'GET' })

export const getHealth = () => request({ url: '/api/health', method: 'GET' })

export function uploadBundle(formData, { onUploadProgress, signal } = {}) {
  return request({
    url: '/api/upload',
    method: 'POST',
    data: formData,
    signal,
    timeout: 300_000, // a 150 MB bundle on a slow link needs room
    onUploadProgress,
  })
}

export const getStatus = (sessionId, { signal } = {}) =>
  request({ url: `/api/status/${encodeURIComponent(sessionId)}`, method: 'GET', signal })

export const getResults = (sessionId, { signal } = {}) =>
  request({ url: `/api/results/${encodeURIComponent(sessionId)}`, method: 'GET', signal })

export const askQuestion = (sessionId, question, { signal } = {}) =>
  request({
    url: '/api/query',
    method: 'POST',
    data: { session_id: sessionId, question },
    signal,
    timeout: 180_000,
  })

export const deleteSession = (sessionId) =>
  request({ url: `/api/session/${encodeURIComponent(sessionId)}`, method: 'DELETE' })

/**
 * Download a memorandum.
 *
 * Fetched as a blob rather than exposed as a bare `<a href>`, because the
 * previous build's plain link could not send the `X-API-Key` header — so the
 * download broke the moment authentication was switched on.
 */
export async function downloadMemo(sessionId, format = 'docx') {
  const path =
    format === 'pdf'
      ? `/api/download/${encodeURIComponent(sessionId)}/pdf`
      : `/api/download/${encodeURIComponent(sessionId)}`

  let blob
  try {
    const response = await client.request({
      url: path,
      method: 'GET',
      responseType: 'blob',
      timeout: 120_000,
    })
    blob = response.data
  } catch (error) {
    // An error body arrives as a Blob; decode it so the message is usable.
    if (error?.response?.data instanceof Blob) {
      try {
        const text = await error.response.data.text()
        const parsed = JSON.parse(text)
        throw new ApiError(parsed?.error?.message || 'Download failed.', {
          code: parsed?.error?.code || 'download_failed',
          status: error.response.status,
        })
      } catch (parseFailure) {
        if (parseFailure instanceof ApiError) throw parseFailure
      }
    }
    throw toApiError(error)
  }

  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = `due_diligence_memo_${sessionId.slice(0, 8)}.${format}`
  document.body.appendChild(anchor)
  anchor.click()
  anchor.remove()
  // Revoke on the next tick so Safari has begun the download.
  setTimeout(() => URL.revokeObjectURL(url), 1000)
  return true
}
