/**
 * Toast region.
 *
 * `role="status"` with `aria-live="polite"` so notifications are announced by
 * screen readers without interrupting whatever the user is doing.
 */
export default function Toasts({ toasts, onDismiss }) {
  return (
    <div className="toast-region" role="status" aria-live="polite" aria-atomic="false">
      {toasts.map((toast) => (
        <div className={`toast ${toast.variant}`} key={toast.id}>
          <span aria-hidden="true">
            {toast.variant === 'error' ? '⚠' : toast.variant === 'success' ? '✓' : 'ℹ'}
          </span>
          <div className="toast-body">{toast.message}</div>
          <button
            type="button"
            className="toast-close"
            onClick={() => onDismiss(toast.id)}
            aria-label="Dismiss notification"
          >
            ✕
          </button>
        </div>
      ))}
    </div>
  )
}
