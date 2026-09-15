import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { ArrowRight, Check, Copy, Terminal } from "lucide-react";

export const Route = createFileRoute("/docs")({
  component: DocsPage,
  head: () => ({
    meta: [
      { title: "API Documentation — Auto Upi" },
      {
        name: "description",
        content:
          "Auto Upi REST API docs: create UPI orders, check payment status, verify webhooks and go live with automatic email-based payment detection.",
      },
      { property: "og:title", content: "Auto Upi API Documentation" },
      {
        property: "og:description",
        content: "Create orders, poll status and receive signed webhooks with the Auto Upi UPI gateway API.",
      },
      { property: "og:type", content: "article" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
    links: [{ rel: "canonical", href: "/docs" }],
  }),
});

const NAV = [
  ["introduction", "Introduction"],
  ["quickstart", "Quickstart"],
  ["authentication", "Authentication"],
  ["create-order", "Create order"],
  ["order-status", "Order status"],
  ["webhooks", "Webhooks"],
  ["detection", "Payment detection"],
  ["errors", "Errors"],
  ["pricing", "Pricing"],
  ["faq", "FAQ"],
] as const;

function CodeBlock({ title, code }: { title: string; code: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="docs-code">
      <div className="docs-code-head">
        <span><Terminal /> {title}</span>
        <button
          type="button"
          aria-label="Copy code"
          onClick={async () => {
            await navigator.clipboard.writeText(code);
            setCopied(true);
            window.setTimeout(() => setCopied(false), 1400);
          }}
        >
          {copied ? <Check /> : <Copy />}
        </button>
      </div>
      <pre><code>{code}</code></pre>
    </div>
  );
}

function DocsPage() {
  const [origin, setOrigin] = useState("https://auto-upi-joy.lovable.app");
  const [active, setActive] = useState<string>("introduction");

  useEffect(() => {
    setOrigin(window.location.origin);
    const sections = NAV.map(([id]) => document.getElementById(id)).filter(Boolean) as HTMLElement[];
    const io = new IntersectionObserver(
      (entries) => {
        const visible = entries.filter((e) => e.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0];
        if (visible) setActive(visible.target.id);
      },
      { rootMargin: "-20% 0px -65% 0px" },
    );
    sections.forEach((s) => io.observe(s));
    return () => io.disconnect();
  }, []);

  return (
    <main className="docs-page" id="top">
      <header className="docs-header">
        <Link to="/" className="docs-logo"><strong>Auto Upi</strong><em>Docs</em></Link>
        <nav>
          <Link to="/">Home</Link>
          <a href="#pricing">Pricing</a>
          <Link to="/auth">Sign in</Link>
          <Link className="docs-cta" to="/register">Get API key <ArrowRight /></Link>
        </nav>
      </header>

      <div className="docs-shell">
        <aside className="docs-side" aria-label="Documentation sections">
          <span className="docs-side-title">API REFERENCE</span>
          {NAV.map(([id, label]) => (
            <a key={id} href={`#${id}`} className={active === id ? "is-active" : undefined}>{label}</a>
          ))}
        </aside>

        <article className="docs-body">
          <section id="introduction" className="docs-section">
            <span className="docs-eyebrow">VERSION 1 · REST API</span>
            <h1>Auto Upi API documentation</h1>
            <p>
              Auto Upi is a self-serve UPI collection gateway. You create an order through the REST API, we return a hosted
              checkout link with a unique payable amount, and the payment is confirmed automatically from your bank alert
              email — no manual reconciliation and no integration with a card processor.
            </p>
            <div className="docs-grid-3">
              <div><strong>Base URL</strong><code>{origin}/api/public/v1</code></div>
              <div><strong>Format</strong><code>application/json</code></div>
              <div><strong>Auth header</strong><code>X-API-Key</code></div>
            </div>
          </section>

          <section id="quickstart" className="docs-section">
            <h2>Quickstart</h2>
            <ol className="docs-steps">
              <li><strong>Create an account</strong> and sign in to the merchant console.</li>
              <li><strong>Connect an account</strong> — pick PhonePe or Paytm, save your UPI ID, then connect your payment-alert mailbox with an email address and app password.</li>
              <li><strong>Generate an API key</strong> on the API Keys page. Copy it once; regenerating replaces the old key.</li>
              <li><strong>Create an order</strong> from your server and redirect the customer to the returned <code>payment_url</code>.</li>
              <li><strong>Confirm</strong> the payment through the status endpoint or your webhook, then fulfil the order.</li>
            </ol>
          </section>

          <section id="authentication" className="docs-section">
            <h2>Authentication</h2>
            <p>
              Every request carries your secret key in the <code>X-API-Key</code> header. Keys start with
              <code>aupi_live_</code> and are stored hashed — we can never show an old key again. Call the API only from
              your server; never expose the key in browser code.
            </p>
            <CodeBlock title="header" code={`X-API-Key: aupi_live_xxxxxxxxxxxxxxxxxxxxxxxx\nContent-Type: application/json`} />
          </section>

          <section id="create-order" className="docs-section">
            <h2>Create order</h2>
            <p className="docs-endpoint"><span className="m-post">POST</span> <code>/api/public/v1/create-order</code></p>
            <table className="docs-table">
              <thead><tr><th>Field</th><th>Type</th><th>Required</th><th>Description</th></tr></thead>
              <tbody>
                <tr><td><code>amount</code></td><td>number</td><td>Yes</td><td>Order amount in INR, 1 to 10,00,000.</td></tr>
                <tr><td><code>customer_name</code></td><td>string</td><td>No</td><td>Shown on the checkout page.</td></tr>
                <tr><td><code>link_type</code></td><td>string</td><td>No</td><td><code>one_time</code> (default) or <code>reusable</code>.</td></tr>
              </tbody>
            </table>
            <CodeBlock
              title="curl"
              code={`curl -X POST ${origin}/api/public/v1/create-order \\
  -H "X-API-Key: aupi_live_your_key" \\
  -H "Content-Type: application/json" \\
  -d '{"amount": 1499, "customer_name": "Rahul Sharma"}'`}
            />
            <CodeBlock
              title="200 response"
              code={`{
  "ok": true,
  "order_id": "ORD20260915A1B2C3",
  "slug": "9fKq2wRa",
  "amount": 1499,
  "payable_amount": 1499.01,
  "status": "active",
  "payment_url": "${origin}/pay/9fKq2wRa"
}`}
            />
            <p className="docs-note">
              <strong>Unique paise:</strong> every active order gets its own payable amount (₹1499.01, ₹1499.02 …). That is
              how a bank alert is matched to exactly one order. Always charge <code>payable_amount</code>, not
              <code>amount</code>.
            </p>
            <CodeBlock
              title="php"
              code={`$ch = curl_init("${origin}/api/public/v1/create-order");
curl_setopt_array($ch, [
  CURLOPT_RETURNTRANSFER => true,
  CURLOPT_POST => true,
  CURLOPT_HTTPHEADER => ["X-API-Key: aupi_live_your_key", "Content-Type: application/json"],
  CURLOPT_POSTFIELDS => json_encode(["amount" => 1499, "customer_name" => "Rahul"]),
]);
$order = json_decode(curl_exec($ch), true);
header("Location: " . $order["payment_url"]);`}
            />
          </section>

          <section id="order-status" className="docs-section">
            <h2>Order status</h2>
            <p className="docs-endpoint"><span className="m-get">GET</span> <code>/api/public/v1/order-status?order_id=ORD…</code></p>
            <p>Poll this endpoint from your server (or after the customer returns) to confirm a payment before fulfilment.</p>
            <CodeBlock
              title="curl"
              code={`curl "${origin}/api/public/v1/order-status?order_id=ORD20260915A1B2C3" \\
  -H "X-API-Key: aupi_live_your_key"`}
            />
            <CodeBlock
              title="200 response"
              code={`{
  "ok": true,
  "order": {
    "order_id": "ORD20260915A1B2C3",
    "slug": "9fKq2wRa",
    "customer_name": "Rahul Sharma",
    "amount": 1499,
    "payable_amount": 1499.01,
    "status": "paid",
    "payer_name": "RAHUL SHARMA",
    "paid_at": "2026-09-15T10:21:44.120Z",
    "detected_at": "2026-09-15T10:21:52.480Z",
    "expires_at": "2026-09-15T10:36:00.000Z"
  }
}`}
            />
            <table className="docs-table">
              <thead><tr><th>Status</th><th>Meaning</th></tr></thead>
              <tbody>
                <tr><td><code>active</code></td><td>Waiting for payment. Links expire 15 minutes after creation.</td></tr>
                <tr><td><code>paid</code></td><td>A matching credit alert was detected. Safe to fulfil.</td></tr>
                <tr><td><code>expired</code></td><td>No payment detected in time. Create a new order.</td></tr>
              </tbody>
            </table>
          </section>

          <section id="webhooks" className="docs-section">
            <h2>Webhooks</h2>
            <p>
              Each API key ships with a webhook secret (<code>whsec_…</code>) shown on the API Keys page. Status updates are
              signed with HMAC-SHA256 so you can verify they really came from Auto Upi.
            </p>
            <CodeBlock
              title="signature header"
              code={`X-AutoUpi-Signature: t=1789453200,v1=6f3c…9ab

signed_payload = "{t}." + raw_request_body
v1 = hex(hmac_sha256(webhook_secret, signed_payload))`}
            />
            <CodeBlock
              title="node verification"
              code={`import { createHmac, timingSafeEqual } from "crypto";

const [tPart, vPart] = req.headers["x-autoupi-signature"].split(",");
const t = tPart.split("=")[1];
const v1 = vPart.split("=")[1];
const expected = createHmac("sha256", process.env.AUTOUPI_WEBHOOK_SECRET)
  .update(\`\${t}.\${rawBody}\`)
  .digest("hex");

if (!timingSafeEqual(Buffer.from(v1), Buffer.from(expected))) {
  return res.status(401).send("bad signature");
}
// idempotent: ignore an order_id you have already fulfilled`}
            />
            <p className="docs-note">Always treat delivery as at-least-once and keep your handler idempotent.</p>
          </section>

          <section id="detection" className="docs-section">
            <h2>How payment detection works</h2>
            <div className="docs-grid-2">
              <div><strong>1. Unique amount</strong><p>Each pending order gets its own paise value, so two customers can never collide on one alert.</p></div>
              <div><strong>2. Mailbox read</strong><p>Your payment-alert mailbox is read securely with the app password you saved. Nothing is sent back to the browser.</p></div>
              <div><strong>3. Exact match</strong><p>An alert is credited only when exactly one active order matches the amount. Two candidates means neither is paid.</p></div>
              <div><strong>4. Dedupe</strong><p>Every alert is claimed by message ID, so a single email can never mark two orders paid or double-credit one.</p></div>
            </div>
            <p className="docs-note">Typical capture time is 5–15 seconds from the alert email.</p>
          </section>

          <section id="errors" className="docs-section">
            <h2>Errors</h2>
            <table className="docs-table">
              <thead><tr><th>HTTP</th><th>Code</th><th>Fix</th></tr></thead>
              <tbody>
                <tr><td>401</td><td><code>invalid_api_key</code></td><td>Key missing, revoked or replaced by a regenerate.</td></tr>
                <tr><td>400</td><td><code>invalid_amount</code></td><td>Amount must be greater than 0 and up to 10,00,000.</td></tr>
                <tr><td>400</td><td><code>UPI_NOT_CONFIGURED</code></td><td>Save a UPI ID on Connect Accounts first.</td></tr>
                <tr><td>400</td><td><code>ALL_PAYMENT_SLOTS_BUSY</code></td><td>Too many pending orders at the same amount; retry shortly.</td></tr>
                <tr><td>404</td><td><code>not_found</code></td><td>The order ID does not belong to this key.</td></tr>
              </tbody>
            </table>
          </section>

          <section id="pricing" className="docs-section">
            <h2>Pricing</h2>
            <p>No per-transaction commission — you collect straight into your own UPI account.</p>
            <div className="docs-price-grid">
              <div className="docs-price">
                <h3>Free</h3>
                <strong>₹0</strong><span>to get started</span>
                <ul>
                  <li><Check /> 3 payment QR codes total</li>
                  <li><Check /> 1 merchant account</li>
                  <li><Check /> Full REST API access</li>
                  <li><Check /> Email payment detection</li>
                </ul>
                <Link className="docs-btn" to="/register">Create account</Link>
              </div>
              <div className="docs-price is-popular">
                <span className="docs-tag">MOST POPULAR</span>
                <h3>Pro</h3>
                <strong>₹299</strong><span>per 30 days</span>
                <ul>
                  <li><Check /> 3,000 QR codes per 30 days</li>
                  <li><Check /> Unlimited payment links</li>
                  <li><Check /> Signed webhooks</li>
                  <li><Check /> Priority support</li>
                </ul>
                <Link className="docs-btn is-primary" to="/register">Start now</Link>
              </div>
              <div className="docs-price">
                <h3>Custom</h3>
                <strong>Talk to us</strong><span>high volume</span>
                <ul>
                  <li><Check /> Higher QR limits</li>
                  <li><Check /> Multiple merchant accounts</li>
                  <li><Check /> Self-hosted deployment</li>
                  <li><Check /> Dedicated support</li>
                </ul>
                <a className="docs-btn" href="mailto:support@autoupi.in">Contact sales</a>
              </div>
            </div>
          </section>

          <section id="faq" className="docs-section">
            <h2>FAQ</h2>
            <div className="docs-faq">
              <div><strong>Do I need a payment gateway account?</strong><p>No. Money reaches your own UPI account directly; Auto Upi only detects and records the payment.</p></div>
              <div><strong>What if two customers pay the same amount?</strong><p>They can't — each pending order carries its own unique paise value.</p></div>
              <div><strong>How long is a link valid?</strong><p>15 minutes. After that the order becomes <code>expired</code> and moves to Transactions.</p></div>
              <div><strong>Can I regenerate my API key?</strong><p>Yes. Regenerating issues a new key and instantly disables the previous one.</p></div>
            </div>
          </section>

          <footer className="docs-footer">
            <span>© 2026 Auto Upi · Payment infrastructure for Indian businesses.</span>
            <Link to="/">Back to home</Link>
          </footer>
        </article>
      </div>
    </main>
  );
}
