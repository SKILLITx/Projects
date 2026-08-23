import { useCallback, useEffect, useRef, useState } from 'react'

import { getResults, getStatus } from '../lib/api'

/**
 * Poll a session to completion.
 *
 * Three defects in the previous implementation are fixed here:
 *
 * 1. `setInterval` fired regardless of whether the previous request had
 *    returned, so a slow backend accumulated overlapping in-flight requests.
 *    This schedules the next tick only after the current one settles.
 * 2. A transient network blip logged to the console and was otherwise ignored,
 *    leaving the UI spinning forever. Consecutive failures are counted and the
 *    poll gives up with a real error after a threshold.
 * 3. Nothing was aborted on unmount, so a resolved request could call
 *    `setState` on a dead component. Every request now carries an AbortSignal.
 */
const BASE_INTERVAL_MS = 2000
const MAX_INTERVAL_MS = 8000
const MAX_CONSECUTIVE_FAILURES = 5

export default function useSessionPolling(sessionId, { onComplete, onError } = {}) {
  const [status, setStatus] = useState(null)
  const [progress, setProgress] = useState(0)
  const [label, setLabel] = useState('')
  const [error, setError] = useState(null)

  const onCompleteRef = useRef(onComplete)
  const onErrorRef = useRef(onError)

  // Assigned in an effect rather than during render: React 19 treats a render
  // -phase ref write as a correctness bug, and it genuinely is one under
  // concurrent rendering, where a render can be discarded and replayed.
  useEffect(() => {
    onCompleteRef.current = onComplete
    onErrorRef.current = onError
  }, [onComplete, onError])

  const timeoutRef = useRef(null)
  const abortRef = useRef(null)
  const stoppedRef = useRef(false)

  const stop = useCallback(() => {
    stoppedRef.current = true
    if (timeoutRef.current) clearTimeout(timeoutRef.current)
    if (abortRef.current) abortRef.current.abort()
  }, [])

  useEffect(() => {
    if (!sessionId) return undefined

    stoppedRef.current = false
    let failures = 0

    const controller = new AbortController()
    abortRef.current = controller

    const schedule = (delay) => {
      if (stoppedRef.current) return
      timeoutRef.current = setTimeout(tick, delay)
    }

    async function tick() {
      if (stoppedRef.current) return
      try {
        const payload = await getStatus(sessionId, { signal: controller.signal })
        if (stoppedRef.current) return

        failures = 0
        setStatus(payload.status)
        setProgress(payload.progress ?? 0)
        setLabel(payload.label ?? '')

        if (payload.status === 'complete') {
          const results = await getResults(sessionId, { signal: controller.signal })
          if (stoppedRef.current) return
          onCompleteRef.current?.(results)
          return
        }

        if (payload.status === 'failed') {
          const message = payload.error || 'The review could not be completed.'
          setError(message)
          onErrorRef.current?.(message)
          return
        }

        schedule(BASE_INTERVAL_MS)
      } catch (caught) {
        if (stoppedRef.current || caught?.code === 'cancelled') return

        // A 404 means the session is genuinely gone — never retry that.
        if (caught?.isNotFound) {
          const message = 'This review session has expired or no longer exists.'
          setError(message)
          onErrorRef.current?.(message)
          return
        }

        failures += 1
        if (failures >= MAX_CONSECUTIVE_FAILURES) {
          const message = caught?.message || 'Lost contact with the review server.'
          setError(message)
          onErrorRef.current?.(message)
          return
        }
        // Back off so a struggling server is not hammered.
        schedule(Math.min(BASE_INTERVAL_MS * 2 ** failures, MAX_INTERVAL_MS))
      }
    }

    tick()

    return () => {
      stoppedRef.current = true
      if (timeoutRef.current) clearTimeout(timeoutRef.current)
      controller.abort()
    }
  }, [sessionId])

  return { status, progress, label, error, stop }
}
