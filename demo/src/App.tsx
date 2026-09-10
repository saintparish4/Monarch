import {useState} from 'react'
import {useMonarch, type Phase} from './lib/useMonarch'
import {resetBurner} from './lib/burner'

const EXPLORER = 'https://sepolia.basescan.org'

function short(a?: string) {
  return a ? `${a.slice(0, 6)}…${a.slice(-4)}` : '—'
}

function Status({phase}: {phase: Phase}) {
  switch (phase.kind) {
    case 'idle':
      return null
    case 'building':
      return <p className="status working">Building the operation…</p>
    case 'sponsoring':
      return <p className="status working">Asking the app to pay for it…</p>
    case 'submitting':
      return <p className="status working">Submitting to the bundler…</p>
    case 'mining':
      return <p className="status working">Waiting for it to be included…</p>
    case 'done':
      return (
        <p className="status ok">
          Done — the app paid {(Number(phase.actualGasCost) / 1e18).toFixed(8)} ETH.{' '}
          <a href={`${EXPLORER}/tx/${phase.txHash}`} target="_blank" rel="noreferrer">
            View the transaction
          </a>
        </p>
      )
    case 'error':
      return <p className="status bad">{phase.message}</p>
  }
}

export function App() {
  const m = useMonarch()
  const [message, setMessage] = useState('')
  const busy = ['building', 'sponsoring', 'submitting', 'mining'].includes(m.phase.kind)
  const zeroBalance = m.ownerBalance === 0n

  return (
    <main>
      <header>
        <h1>Monarch</h1>
        <p className="tagline">
          This wallet holds <strong>no ETH</strong>. It is about to write to a contract anyway,
          because the app is paying its gas.
        </p>
      </header>

      <section className="wallet">
        <dl>
          <div>
            <dt>Your burner wallet</dt>
            <dd>
              <code>{short(m.ownerAddress)}</code>
            </dd>
          </div>
          <div>
            <dt>Its balance</dt>
            <dd>
              <code className={zeroBalance ? 'zero' : ''}>
                {m.ownerBalanceEth === undefined ? '…' : `${m.ownerBalanceEth} ETH`}
              </code>
              {zeroBalance && <span className="badge">nothing to pay gas with</span>}
            </dd>
          </div>
          <div>
            <dt>Smart account</dt>
            <dd>
              <code>{short(m.smartAccount)}</code>
            </dd>
          </div>
          <div>
            <dt>App budget remaining</dt>
            <dd>
              <code>{m.appBudgetEth === undefined ? '…' : `${m.appBudgetEth} ETH`}</code>
            </dd>
          </div>
        </dl>
        <button className="link" onClick={() => { resetBurner(); location.reload() }}>
          Start over with a new wallet
        </button>
      </section>

      <section className="compose">
        <label htmlFor="msg">Sign the guestbook</label>
        <textarea
          id="msg"
          value={message}
          maxLength={280}
          rows={3}
          placeholder="Anything, up to 280 characters."
          onChange={(e) => setMessage(e.target.value)}
          disabled={busy}
        />
        <div className="row">
          <button
            className="primary"
            disabled={busy || message.trim().length === 0}
            onClick={() => void m.sign(message.trim())}
          >
            {busy ? 'Working…' : 'Sign — costs you nothing'}
          </button>
          <span className="count">{message.length}/280</span>
        </div>
        <Status phase={m.phase} />
      </section>

      <section className="entries">
        <h2>Recent entries</h2>
        {m.entries.length === 0 ? (
          <p className="empty">Nothing here yet.</p>
        ) : (
          <ul>
            {m.entries.map((e, i) => (
              <li key={`${e.author}-${e.timestamp}-${i}`}>
                <p className="msg">{e.message}</p>
                <p className="meta">
                  <a href={`${EXPLORER}/address/${e.author}`} target="_blank" rel="noreferrer">
                    {short(e.author)}
                  </a>{' '}
                  · {new Date(Number(e.timestamp) * 1000).toLocaleString()}
                </p>
              </li>
            ))}
          </ul>
        )}
      </section>

      <footer>
        <p>
          Base Sepolia · EntryPoint v0.8 ·{' '}
          <a href="https://github.com/saintparish4/Monarch" target="_blank" rel="noreferrer">
            source
          </a>
        </p>
      </footer>
    </main>
  )
}
