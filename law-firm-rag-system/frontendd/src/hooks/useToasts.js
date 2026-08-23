import { useCallback, useRef, useState } from 'react'

/**
 * Transient notifications.
 *
 * Errors previously appeared only as inline text inside whichever panel was
 * mounted, so a failure raised while the lawyer was on another tab was never
 * seen at all. Toasts render into a polite live region so screen readers
 * announce them too.
 */
export default function useToasts() {
  const [toasts, setToasts] = useState([])
  const timers = useRef(new Map())
  const counter = useRef(0)

  const dismiss = useCallback((id) => {
    setToasts((current) => current.filter((toast) => toast.id !== id))
    const timer = timers.current.get(id)
    if (timer) {
      clearTimeout(timer)
      timers.current.delete(id)
    }
  }, [])

  const push = useCallback(
    (message, { variant = 'info', duration = 6000 } = {}) => {
      counter.current += 1
      const id = counter.current
      setToasts((current) => [...current.slice(-3), { id, message, variant }])
      if (duration > 0) {
        timers.current.set(id, setTimeout(() => dismiss(id), duration))
      }
      return id
    },
    [dismiss],
  )

  return {
    toasts,
    dismiss,
    notify: push,
    success: useCallback((m, o) => push(m, { ...o, variant: 'success' }), [push]),
    error: useCallback((m, o) => push(m, { ...o, variant: 'error', duration: 9000 }), [push]),
    warning: useCallback((m, o) => push(m, { ...o, variant: 'warning' }), [push]),
  }
}
