import { config } from "@/lib/config";

import { Hero } from "./hero";
import { Alert, ArrowRight, ArrowUpRight, Check, Layers, Mark, Pen, Scale, Search } from "./icons";

const REPO = "https://github.com/saintparish4/Monarch";
const file = (path: string) => `${REPO}/blob/master/${path}`;
const folder = (path: string) => `${REPO}/tree/master/${path}`;

// The six failure cases, in the words the repository's README uses for them.
const CASES = [
  ["01", "01-validation-reads-the-clock", "Validation reads the clock", "Every bundler drops the operation"],
  ["02", "02-postop-gas-ceiling", "A ceiling on the postOp gas limit", "The paymaster cannot be gas-estimated"],
  ["03", "03-starved-postop", "Too little gas for postOp", "The paymaster pays, nobody is charged"],
  ["04", "04-budget-contention", "Several sponsorships against one budget", "The overdraw lands on other apps, or a ban"],
  ["05", "05-unbound-sponsorship", "A signature that leaves fields out", "The sender spends the app's money on something else"],
  ["06", "06-withdraw-takes-deposits", "Withdrawing against the whole deposit", "The owner can take users' balances"],
] as const;

// Sponsored-mode `paymasterData`, field by field, with each field's length in
// bytes. The widths below are weights, not a scale: 65 bytes beside 1 would
// leave the mode byte too narrow to label.
const PAYMASTER_DATA = [
  ["mode", "1", 1],
  ["app", "20", 3],
  ["validUntil", "6", 2],
  ["validAfter", "6", 2],
  ["signature", "65", 4],
] as const;

// Code shown on the page, as text with the few tokens worth colouring marked:
// keyword, function, string or value, comment.
type Token = string | readonly ["k" | "f" | "s" | "c", string];

// Abbreviated from this page's own source, in hero.tsx.
const SPONSOR_SNIPPET: readonly Token[] = [
  ["k", "const"],
  " bundler = ",
  ["f", "createBundlerClient"],
  "({\n  account,\n  transport: ",
  ["f", "http"],
  "(bundlerUrl),\n  paymaster: {\n    getPaymasterStubData: (op) => ",
  ["f", "sponsor"],
  "(",
  ["s", '"stub"'],
  ", op),\n    getPaymasterData: (op) => ",
  ["f", "sponsor"],
  "(",
  ["s", '"final"'],
  ", op),\n  },\n});\n\n",
  ["k", "await"],
  " bundler.",
  ["f", "sendUserOperation"],
  "({\n  calls: [{ to: account.address, value: ",
  ["s", "0n"],
  ", data: ",
  ["s", '"0x"'],
  " }],\n});",
];

const INVARIANT_SNIPPET: readonly Token[] = [
  ["c", "// The property the whole test suite is built around."],
  "\nentryPoint.",
  ["f", "balanceOf"],
  "(paymaster)\n  ",
  ["k", ">="],
  " totalUserDeposits + totalAppBudgets",
];

// A finding as the detector prints it, from its README.
const FINDING_SNIPPET: readonly Token[] = [
  ["c", "$ slither . --detect erc7562-validation-opcodes"],
  "\n\n",
  ["f", "ClockCheckingPaymaster.validatePaymasterUserOp"],
  " reaches ",
  ["s", "TIMESTAMP"],
  " via `block.timestamp`. ERC-7562 ",
  ["s", "OP-011"],
  " forbids it during validation. Its value can change between the bundler's simulation and " +
    "the block that includes the operation, so a bundler drops any operation whose validation " +
    "uses it:\n  - block.timestamp > validUntil ",
  ["c", "(Clock.sol#27)"],
];

function Code({ tokens }: { tokens: readonly Token[] }) {
  return (
    <pre>
      <code>
        {tokens.map((token, index) =>
          typeof token === "string" ? (
            token
          ) : (
            <i key={index} className={token[0]}>
              {token[1]}
            </i>
          ),
        )}
      </code>
    </pre>
  );
}

// The page is static apart from the hero. The warning is said three times on
// purpose, in the bar at the top, beside the deployment and in the footer:
// this is a testnet deployment of unaudited code, and a page that looks
// finished must not let that slip below the fold.
export default function Page() {
  return (
    <>
      <a className="announce" href={`${REPO}#readme`} id="top">
        Testnet only and unaudited. Nothing on this page is for mainnet. Read the warning
        <ArrowRight />
      </a>

      <header className="site-header">
        <div className="container header-row">
          <a className="brand" href="#top">
            <Mark />
            Monarch
          </a>
          <nav aria-label="Sections">
            <a href="#how">How it works</a>
            <a href="#cases">Failure cases</a>
            <a href="#deployment">Deployment</a>
            <a href={file("docs/walkthrough.md")}>
              Walkthrough <ArrowUpRight />
            </a>
          </nav>
          <div className="header-actions">
            <a className="button outline" href={REPO}>
              Source
            </a>
            <a className="button dark" href="#demo">
              Try the demo
            </a>
          </div>
        </div>
      </header>

      <main>
        <Hero />

        <section className="section" id="how">
          <div className="container">
            <h2 className="title-l">Who pays for the gas</h2>
            <div className="intro">
              <p className="intro-lead">
                The user holds nothing. The app&apos;s budget pays, and only for what the app signed.
              </p>
              <p className="intro-body">
                Monarch is an <b>ERC-4337 v0.8</b> paymaster. An app registers, funds a <b>budget</b>{" "}
                and nominates a signer. To sponsor a user it signs a short authorisation off-chain;
                the paymaster recovers the signer during validation and charges the app in{" "}
                <b>postOp</b>. A second mode lets a user <b>prepay a balance</b> and spend it across
                later operations.
              </p>
            </div>
          </div>
          <div className="tabs">
            <div className="container tab-row">
              <a href="#sponsored">
                <span className="tab-icon">
                  <Pen />
                </span>
                Sponsored mode
              </a>
              <a href="#solvency">
                <span className="tab-icon">
                  <Scale />
                </span>
                Solvency
              </a>
              <a href="#static-check">
                <span className="tab-icon">
                  <Search />
                </span>
                Static check
              </a>
            </div>
          </div>
        </section>

        <section className="container feature" id="sponsored">
          <div className="feature-copy">
            <p className="eyebrow">Sponsored mode</p>
            <h3 className="title-m">The app signs off-chain. The paymaster bills it on-chain.</h3>
            <ul className="checklist">
              <li>
                <span className="check">
                  <Check />
                </span>
                The digest to sign comes from the contract, so the backend never re-derives the
                packing.
              </li>
              <li>
                <span className="check">
                  <Check />
                </span>
                The signature covers both paymaster gas limits, so a bundler cannot change them.
              </li>
              <li>
                <span className="check">
                  <Check />
                </span>
                The validity window is signed and handed to the EntryPoint. Validation never reads
                the clock.
              </li>
            </ul>
            <a className="button dark" href={file("demo/app/api/sponsor/route.ts")}>
              Read the sponsor route
            </a>
          </div>
          <div className="feature-visual">
            <div className="code-card">
              <Code tokens={SPONSOR_SNIPPET} />
            </div>
            <div className="float-card">
              <p className="float-title">paymasterData, in bytes</p>
              <div className="bytes">
                {PAYMASTER_DATA.map(([name, length, weight]) => (
                  <span key={name} style={{ flexGrow: weight }}>
                    <b>{name}</b>
                    {length}
                  </span>
                ))}
              </div>
              <p className="float-note">
                Lengths are checked for equality, never as a minimum.
              </p>
            </div>
          </div>
        </section>

        <section className="container feature flip" id="solvency">
          <div className="feature-copy">
            <p className="eyebrow lime">Solvency</p>
            <h3 className="title-m">The owner can withdraw only what is the owner&apos;s.</h3>
            <ul className="checklist">
              <li>
                <span className="check">
                  <Check />
                </span>
                User deposits and app budgets are never owner funds.
              </li>
              <li>
                <span className="check">
                  <Check />
                </span>
                Checked as a stateful invariant over every entry point that moves value.
              </li>
              <li>
                <span className="check">
                  <Check />
                </span>
                Checked again after every bundle the tests run through the real EntryPoint.
              </li>
            </ul>
            <a className="button dark" href={file("contracts/MonarchPaymaster.sol")}>
              Read the contract
            </a>
          </div>
          <div className="feature-visual">
            <div className="code-card">
              <Code tokens={INVARIANT_SNIPPET} />
            </div>
            <div className="float-card">
              <p className="float-title">The paymaster&apos;s EntryPoint deposit</p>
              <div className="pot">
                <span className="pot-users">User deposits</span>
                <span className="pot-apps">App budgets</span>
                <span className="pot-free">Free</span>
              </div>
              <p className="float-note">
                Only the free part, the excess above the sum, can leave with the owner.
              </p>
            </div>
          </div>
        </section>

        <section className="container feature" id="static-check">
          <div className="feature-copy">
            <p className="eyebrow">Static check</p>
            <h3 className="title-m">The worst bug in the code this replaced became a Slither detector.</h3>
            <ul className="checklist">
              <li>
                <span className="check">
                  <Check />
                </span>
                It walks everything reachable from validation: internal calls, modifiers, library
                calls and self-calls.
              </li>
              <li>
                <span className="check">
                  <Check />
                </span>
                Every finding names the ERC-7562 rule and says what a bundler does about it.
              </li>
              <li>
                <span className="check">
                  <Check />
                </span>
                It is an early check. A clean run does not mean a bundler will accept the
                operation.
              </li>
            </ul>
            <a className="button dark" href={folder("tools/slither-erc7562")}>
              Explore the detector
            </a>
          </div>
          <div className="feature-visual">
            <div className="code-card terminal">
              <Code tokens={FINDING_SNIPPET} />
            </div>
          </div>
        </section>

        <section className="container" id="cases">
          <div className="panel dark">
            <p className="eyebrow lime">Failure cases</p>
            <h2 className="title-l">Six ways a paymaster fails that its own tests do not show</h2>
            <p className="panel-lede">
              Each is a broken contract, its fix, and a test against the real EntryPoint v0.8 that
              tells the two apart.
            </p>
            <a className="button lime large" href={folder("cases")}>
              Read the cases
              <ArrowRight />
            </a>
            <ol className="case-grid">
              {CASES.map(([number, path, name, outcome]) => (
                <li key={number}>
                  <a href={folder(`cases/${path}`)}>
                    <span className="case-number">{number}</span>
                    <b>{name}</b>
                    <span className="case-outcome">{outcome}</span>
                  </a>
                </li>
              ))}
            </ol>
          </div>
        </section>

        <section className="container" id="deployment">
          <div className="panel light">
            <div className="panel-head">
              <h2 className="title-l">Live on Base Sepolia</h2>
              <p className="panel-lede">
                The paymaster is deployed and staked on a testnet. It has not been audited, and
                nothing here is for mainnet.
              </p>
              <a className="button dark" href={`${config.explorerUrl}/address/${config.paymaster}`}>
                View the paymaster
                <ArrowUpRight />
              </a>
            </div>
            <ul className="fact-grid">
              <li>
                <span className="fact-icon lime">
                  <Layers />
                </span>
                <b>v0.8</b>
                <span className="fact-label">EntryPoint</span>
              </li>
              <li>
                <span className="fact-icon mint">
                  <Check />
                </span>
                <b>{config.chainId}</b>
                <span className="fact-label">Chain id</span>
              </li>
              <li>
                <span className="fact-icon aqua">
                  <Scale />
                </span>
                <b>Staked</b>
                <span className="fact-label">So bundlers accept it</span>
              </li>
              <li>
                <span className="fact-icon lilac">
                  <Alert />
                </span>
                <b>Unaudited</b>
                <span className="fact-label">Testnet only</span>
              </li>
            </ul>
          </div>
        </section>

        <section className="container">
          <div className="panel dark closing">
            <h2 className="title-l">
              <span>Zero ETH in the wallet.</span> One transaction on chain.
            </h2>
            <p className="panel-lede">
              Send one from this tab, then read how the contract, its tests and the detector fit
              together.
            </p>
            <div className="actions">
              <a className="button primary large" href="#demo">
                Try the demo
                <ArrowRight />
              </a>
              <a className="button glass large" href={REPO}>
                Read the source
              </a>
            </div>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <div className="container footer-grid">
          <a className="brand" href="#top">
            <Mark />
            Monarch
          </a>
          <div>
            <h4>Project</h4>
            <a href={REPO}>Source</a>
            <a href={`${REPO}#readme`}>README</a>
            <a href={file("LICENSE")}>MIT licence</a>
          </div>
          <div>
            <h4>Read</h4>
            <a href={file("docs/walkthrough.md")}>Demo walkthrough</a>
            <a href={folder("cases")}>Failure cases</a>
            <a href={file("docs/teardown-basepaymaster.md")}>The teardown</a>
            <a href={folder("tools/slither-erc7562")}>The detector</a>
          </div>
          <div>
            <h4>On chain</h4>
            <a href={`${config.explorerUrl}/address/${config.paymaster}`}>MonarchPaymaster</a>
            <a href={`${config.explorerUrl}/address/${config.entryPoint}`}>EntryPoint v0.8</a>
            <a href={`${config.explorerUrl}/address/${config.app}`}>The demo app</a>
          </div>
        </div>
        <div className="footer-bar">
          <p className="container">
            Testnet only. Unaudited. The sponsor endpoint is unauthenticated, so anyone can spend the
            demo budget. <a href="https://github.com/saintparish4/Monarch">Source</a>
          </p>
        </div>
      </footer>
    </>
  );
}
