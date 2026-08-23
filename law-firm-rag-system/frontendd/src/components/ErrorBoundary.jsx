import { Component } from 'react'

/**
 * Top-level render guard.
 *
 * The previous boundary hard-coded its colours, so it rendered as dark-on-dark
 * for anyone using a light theme, and it offered only a full page reload —
 * which discarded the session. This one uses the design tokens, shows the
 * component stack in development only, and lets the user retry in place.
 */
export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props)
    this.state = { error: null, info: null }
  }

  static getDerivedStateFromError(error) {
    return { error }
  }

  componentDidCatch(error, info) {
    this.setState({ info })
    console.error('Unhandled render error:', error, info)
  }

  handleRetry = () => this.setState({ error: null, info: null })

  render() {
    const { error, info } = this.state
    if (!error) return this.props.children

    return (
      <div
        role="alert"
        style={{
          minHeight: '100dvh',
          display: 'grid',
          placeItems: 'center',
          padding: 'var(--s-5)',
          background: 'var(--bg-base)',
        }}
      >
        <div className="panel" style={{ maxWidth: '560px', textAlign: 'center' }}>
          <div style={{ fontSize: '2.4rem', marginBottom: 'var(--s-3)' }} aria-hidden="true">
            ⚠️
          </div>
          <h2 style={{ marginBottom: 'var(--s-2)' }}>Something went wrong</h2>
          <p className="panel-subtitle" style={{ margin: '0 auto var(--s-5)' }}>
            {error?.message || 'An unexpected error occurred while rendering the page.'}
          </p>

          {import.meta.env.DEV && info?.componentStack && (
            <details style={{ textAlign: 'left', marginBottom: 'var(--s-5)' }}>
              <summary style={{ cursor: 'pointer', fontSize: 'var(--fs-sm)' }}>
                Component stack
              </summary>
              <pre
                style={{
                  fontSize: 'var(--fs-xs)',
                  overflow: 'auto',
                  maxHeight: '220px',
                  fontFamily: 'var(--font-mono)',
                  color: 'var(--text-muted)',
                  marginTop: 'var(--s-2)',
                }}
              >
                {info.componentStack}
              </pre>
            </details>
          )}

          <div className="btn-row" style={{ justifyContent: 'center' }}>
            <button type="button" className="btn btn-secondary" onClick={this.handleRetry}>
              Try again
            </button>
            <button
              type="button"
              className="btn btn-primary"
              style={{ width: 'auto' }}
              onClick={() => window.location.reload()}
            >
              Reload the application
            </button>
          </div>
        </div>
      </div>
    )
  }
}
