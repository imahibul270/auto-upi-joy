import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { ArrowRight, Check, Copy, Terminal } from "lucide-react";
import { BrandLogo } from "@/components/BrandLogo";

export const Route = createFileRoute("/docs")({
  component: DocsPage,
  head: () => ({
    meta: [
      { title: "autoupi | API Documentation" },
      {
        name: "description",
        content:
          "Auto Upi popup checkout docs: create UPI orders, open checkout on your website and verify payments with signed webhooks or order status.",
      },
      { property: "og:title", content: "Auto Upi API Documentation" },
      {
        property: "og:description",
        content: "Integrate Auto Upi popup checkout on your website with server-side orders and signed payment verification.",
      },
      { property: "og:type", content: "article" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
    links: [{ rel: "canonical", href: "https://autoupi.in/docs" }],
  }),
});

const NAV = [
  ["introduction", "Introduction"],
  ["quickstart", "Quickstart"],
  ["authentication", "Authentication"],
  ["create-order", "Create order"],
  ["order-status", "Order status"],
  ["webhooks", "Webhooks"],
  ["popup", "Popup checkout"],
  ["php", "PHP integration"],
  
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

function CodeTabs({ samples }: { samples: { label: string; code: string }[] }) {
  const [tab, setTab] = useState(0);
  const active = samples[tab] ?? samples[0];
  if (!active) return null;
  return (
    <div>
      <div className="docs-tabs">
        {samples.map((sample, index) => (
          <button
            key={sample.label}
            type="button"
            className={index === tab ? "is-active" : undefined}
            onClick={() => setTab(index)}
          >
            {sample.label}
          </button>
        ))}
      </div>
      <CodeBlock title={active.label} code={active.code} />
    </div>
  );
}

function DocsPage() {
  const origin = "https://autoupi.in";
  const [active, setActive] = useState<string>("introduction");

  useEffect(() => {

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
        <Link to="/" className="docs-logo"><BrandLogo /><strong>Auto Upi</strong><em>DOCS</em></Link>
        <nav>
          <Link to="/">Home</Link>
          <a href="#php">PHP</a>
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
          <section id="introduction" className="docs-section docs-hero">
            <h1>Auto Upi API documentation</h1>
            <p>
              Auto Upi is a self-serve UPI collection gateway. Create an order from your server and open the
              hosted checkout as a popup on your own website. Orders are confirmed automatically — no commission, money
              straight into your UPI account.
            </p>
            <div className="docs-quick">
              <a href="#quickstart">Quickstart</a>
              <a href="#php">PHP integration</a>
              <a href="#webhooks">Webhooks</a>
              <a href="#errors">Errors</a>
            </div>
            <div className="docs-grid-3">
              <div><strong>BASE URL</strong><code>{origin}/api/public/v1</code></div>
              <div><strong>FORMAT</strong><code>application/json</code></div>
              <div><strong>AUTH HEADER</strong><code>X-API-Key</code></div>
            </div>
          </section>

          <section id="quickstart" className="docs-section">
            <h2>Quickstart</h2>
            <ol className="docs-steps">
              <li><strong>Create an account</strong> and sign in to the merchant console.</li>
              <li><strong>Connect an account</strong> — pick PhonePe or Paytm and complete the setup on the Connect Accounts page.</li>
              <li><strong>Generate an API key</strong> on the API Keys page. Copy it once; regenerating replaces the old key.</li>
              <li><strong>Copy the webhook secret</strong> from API Keys and store both credentials securely on your server.</li>
              <li><strong>Set your webhook URL</strong> on Config, or pass your HTTPS webhook endpoint when creating each order.</li>
              <li><strong>Load the popup script</strong> once from <code>https://autoupi.in/checkout.js</code>.</li>
              <li><strong>Create an order</strong> from your server, save its ID against the buyer, then call <code>AutoUpi.open({"{ url: payment_url }"})</code> on your page. See <a href="#popup">Popup checkout</a>.</li>
              <li><strong>Confirm</strong> payment through your signed webhook or a server-side status check, then update the same page and fulfil the order once.</li>
            </ol>
          </section>

          <section id="authentication" className="docs-section">
            <h2>Authentication</h2>
            <p>
              Every request carries your secret key in the <code>X-API-Key</code> header. Keys start with
              <code>aupi_live_</code> and are stored hashed — an old key can never be shown again. Call the API only from
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
                <tr><td><code>webhook_url</code></td><td>string</td><td>No</td><td>HTTPS URL that receives the signed <code>payment.paid</code> webhook.</td></tr>
                <tr><td><code>link_type</code></td><td>string</td><td>No</td><td><code>one_time</code> (default) or <code>reusable</code>.</td></tr>
              </tbody>
            </table>
            <CodeTabs
              samples={[
                {
                  label: "curl",
                  code: `curl -X POST ${origin}/api/public/v1/create-order \\
  -H "X-API-Key: aupi_live_your_key" \\
  -H "Content-Type: application/json" \\
  -d '{"amount": 1499, "customer_name": "Rahul Sharma", "webhook_url": "https://yoursite.com/autoupi-webhook.php"}'`,
                },
                {
                  label: "php",
                  code: `<?php
$ch = curl_init("${origin}/api/public/v1/create-order");
curl_setopt_array($ch, [
  CURLOPT_RETURNTRANSFER => true,
  CURLOPT_POST => true,
  CURLOPT_HTTPHEADER => ["X-API-Key: aupi_live_your_key", "Content-Type: application/json"],
  CURLOPT_POSTFIELDS => json_encode([
    "amount" => 1499,
    "customer_name" => "Rahul",
    "webhook_url" => "https://yoursite.com/autoupi-webhook.php",
  ]),
]);
$order = json_decode(curl_exec($ch), true);
curl_close($ch);

// Check API errors and save order_id against your buyer on your server.
// Return payment_url to your page for AutoUpi.open({ url: payment_url }).
header("Content-Type: application/json");
echo json_encode($order);`,
                },
                {
                  label: "node",
                  code: `const res = await fetch("${origin}/api/public/v1/create-order", {
  method: "POST",
  headers: { "X-API-Key": process.env.AUTOUPI_KEY, "Content-Type": "application/json" },
  body: JSON.stringify({ amount: 1499, customer_name: "Rahul" }),
});
const order = await res.json();
// Check res.ok and order.ok, then save order_id against your buyer.
// Return payment_url to your page for AutoUpi.open({ url: payment_url }).`,
                },
              ]}
            />
            <CodeBlock
              title="200 response"
              code={`{
  "ok": true,
  "order_id": "ORD20260915A1B2C3",
  "slug": "9fkq2wra",
  "amount": 1499,
  "payable_amount": 1499.37,
  "status": "active",
  "payment_url": "${origin}/pay/9fkq2wra"
}`}
            />
            <p className="docs-note">
              <strong>Always charge <code>payable_amount</code>:</strong> it can differ from <code>amount</code> by up to
              ₹0.99 so each active order stays unique. The customer pays <code>payable_amount</code>; your books are
              credited with the base <code>amount</code>.
            </p>
          </section>

          <section id="order-status" className="docs-section">
            <h2>Order status</h2>
            <p className="docs-endpoint"><span className="m-get">GET</span> <code>/api/public/v1/order-status?order_id=ORD…</code></p>
            <p>Check this endpoint from your server during checkout or after a popup callback to confirm payment before fulfilment. Your page calls your own status endpoint; it never sends the API key to Auto Upi directly.</p>
            <CodeTabs
              samples={[
                {
                  label: "curl",
                  code: `curl "${origin}/api/public/v1/order-status?order_id=ORD20260915A1B2C3" \\
  -H "X-API-Key: aupi_live_your_key"`,
                },
                {
                  label: "php",
                  code: `<?php
function autoupi_status(string $orderId): array {
  $ch = curl_init("${origin}/api/public/v1/order-status?order_id=" . urlencode($orderId));
  curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER => ["X-API-Key: aupi_live_your_key"],
  ]);
  $out = json_decode(curl_exec($ch), true);
  curl_close($ch);
  return $out["order"] ?? [];
}

$order = autoupi_status($_GET["order_id"]);
if (($order["status"] ?? "") === "paid") {
  // fulfil this buyer's saved order once and update the same page
}`,
                },
              ]}
            />
            <CodeBlock
              title="200 response"
              code={`{
  "ok": true,
  "order": {
    "order_id": "ORD20260915A1B2C3",
    "slug": "9fkq2wra",
    "customer_name": "Rahul Sharma",
    "amount": 1499,
    "payable_amount": 1499.37,
    "status": "paid",
    "payer_name": "RAHUL SHARMA",
    "paid_at": "2026-09-15T10:21:44.120Z",
    "detected_at": "2026-09-15T10:21:52.480Z",
    "expires_at": "2026-09-15T10:26:00.000Z"
  }
}`}
            />
            <table className="docs-table">
              <thead><tr><th>Status</th><th>Meaning</th></tr></thead>
              <tbody>
                <tr><td><code>active</code></td><td>Waiting for payment. Links expire 5 minutes after creation.</td></tr>
                <tr><td><code>paid</code></td><td>A matching credit alert was detected. Safe to fulfil.</td></tr>
                <tr><td><code>expired</code></td><td>No payment detected in time. Create a new order.</td></tr>
              </tbody>
            </table>
          </section>

          <section id="webhooks" className="docs-section">
            <h2>Webhooks</h2>
            <p>
              Each API key ships with a webhook secret (<code>whsec_…</code>) shown on the API Keys page. Pass a
              <code>webhook_url</code> when creating an order and we POST a signed <code>payment.paid</code> event the
              moment the order is confirmed as paid. You can also save one default webhook URL on the
              <strong> Config</strong> page in your dashboard — it is used for every order of your account when the
              create order call does not send its own <code>webhook_url</code>.
            </p>
            <CodeBlock
              title="payload"
              code={`POST https://yoursite.com/autoupi-webhook.php
X-AutoUpi-Signature: t=1789453200,v1=6f3c…9ab

{
  "event": "payment.paid",
  "order_id": "ORD20260915A1B2C3",
  "amount": 1499,
  "payable_amount": 1499.37,
  "status": "paid",
  "payer_name": "RAHUL SHARMA",
  "paid_at": "2026-09-15T10:21:44.120Z"
}

signed_payload = "{t}." + raw_request_body
v1 = hex(hmac_sha256(webhook_secret, signed_payload))`}
            />
            <CodeTabs
              samples={[
                {
                  label: "php",
                  code: `<?php
// autoupi-webhook.php
$secret = getenv("AUTOUPI_WEBHOOK_SECRET");
$raw    = file_get_contents("php://input");
$header = $_SERVER["HTTP_X_AUTOUPI_SIGNATURE"] ?? "";

parse_str(str_replace(",", "&", $header), $parts);   // t=..., v1=...
$expected = hash_hmac("sha256", $parts["t"] . "." . $raw, $secret);

if (!hash_equals($expected, $parts["v1"] ?? "")) {
  http_response_code(401);
  exit("bad signature");
}

$event = json_decode($raw, true);
if ($event["event"] === "payment.paid") {
  // idempotent: skip if this order_id is already fulfilled
  mark_order_paid($event["order_id"], $event["amount"]);
}
http_response_code(200);
echo "ok";`,
                },
                {
                  label: "node",
                  code: `import { createHmac, timingSafeEqual } from "crypto";

const [tPart, vPart] = req.headers["x-autoupi-signature"].split(",");
const t = tPart.split("=")[1];
const v1 = vPart.split("=")[1];
const expected = createHmac("sha256", process.env.AUTOUPI_WEBHOOK_SECRET)
  .update(\`\${t}.\${rawBody}\`)
  .digest("hex");

if (!timingSafeEqual(Buffer.from(v1), Buffer.from(expected))) {
  return res.status(401).send("bad signature");
}
// idempotent: ignore an order_id you have already fulfilled`,
                },
              ]}
            />
            <p className="docs-note">Always treat delivery as at-least-once and keep your handler idempotent.</p>
          </section>

          <section id="popup" className="docs-section">
            <h2>Popup checkout</h2>
            <p>
              Keep the customer on your own website. Load our script once, create the order on your server as usual,
              then open the returned <code>payment_url</code> as a popup. The same Auto Upi payment page opens on top of
              your page and closes by itself after the result.
            </p>
            <CodeBlock
              title="HTML / JavaScript"
              code={`<script src="https://autoupi.in/checkout.js"></script>
<button id="pay">Pay now</button>
<p id="payment-status" role="status"></p>
<script>
  const payButton = document.getElementById("pay");
  const paymentStatus = document.getElementById("payment-status");
  document.getElementById("pay").onclick = async () => {
    payButton.disabled = true;
    paymentStatus.textContent = "Starting payment…";
    try {
      // Your server uses the saved cart price, not a browser-supplied amount.
      // Protect this request with your app's session and CSRF controls.
      const response = await fetch("/checkout.php", { method: "POST" });
      const order = await response.json();
      if (!response.ok || !order.ok || !order.payment_url) {
        throw new Error("Could not start payment. Please try again.");
      }
      if (!window.AutoUpi) throw new Error("Checkout could not load. Please try again.");
      AutoUpi.open({
        url: order.payment_url,
        onSuccess: (result) => {
          paymentStatus.textContent = "Confirming payment…";
          // Call YOUR server's buyer-scoped order-status endpoint here.
          // Show success only after it reads paid from Auto Upi.
          // The signed webhook can also confirm the order independently.
          payButton.disabled = false;
        },
        onFailure: (result) => {
          paymentStatus.textContent = "Payment failed or expired. Please try again.";
          payButton.disabled = false;
        },
      });
      paymentStatus.textContent = "Waiting for payment…";
    } catch (error) {
      paymentStatus.textContent = error.message || "Could not start payment.";
      payButton.disabled = false;
    }
  };
</script>`}
            />
            <CodeBlock
              title="Server-side order creation"
              code={`<?php
$ch = curl_init("https://autoupi.in/api/public/v1/create-order");
curl_setopt_array($ch, [
  CURLOPT_POST => true,
  CURLOPT_RETURNTRANSFER => true,
  CURLOPT_HTTPHEADER => ["Content-Type: application/json", "X-API-Key: " . getenv("AUTOUPI_KEY")],
  // Example price only: use your server's saved cart amount in production.
  CURLOPT_POSTFIELDS => json_encode(["amount" => 100, "webhook_url" => "https://yoursite.com/autoupi-webhook.php"]),
]);
// For complete order saving and error handling, see checkout.php below.
header("Content-Type: application/json");
echo curl_exec($ch);`}
            />
            <p className="docs-note">
              The popup result only updates your screen. Deliver the product only after the signed webhook (or the
              order status API) says the order is paid. Update the current merchant page after confirmation; do not
              navigate the customer away. The snippets show integration hooks, not a ready-made store: connect them
              to your own saved orders, buyer authentication and fulfilment.
            </p>
            <h3>Popup size and setup checklist</h3>
            <ul>
              <li>Desktop: up to 860px wide and 520px high, limited to 94% of screen width and 80% of screen height.</li>
              <li>Mobile: 94% of screen width and 80% of the visible screen height. Short screens scroll inside the checkout so the result stays accessible.</li>
              <li>The script adds the 3px border, rounded corners and backdrop. There is no top-right close icon; keep the existing left Back control. Do not add another modal, iframe, white wrapper, padding or custom checkout styles.</li>
              <li>Load the hosted script once and call <code>AutoUpi.open</code> directly with the returned <code>payment_url</code>. Do not copy or self-host an older checkout.js.</li>
              <li>Allow <code>https://autoupi.in</code> in your site's script-src and frame-src policies if you use Content Security Policy.</li>
              <li>Keep API keys and webhook secrets on your server. Keep your existing order creation and payment verification unchanged.</li>
              <li>Use <code>onSuccess</code> and <code>onFailure</code> for result updates. The current hosted script does not emit an <code>onClose</code> callback; do not rely on it to reset your page. A buyer-scoped server status check can reconcile pending orders.</li>
              <li>Check one paid order, one failed/expired order, duplicate webhook delivery and the left Back confirmation on desktop and mobile before going live. Callbacks update your page; only server verification authorizes delivery.</li>
            </ul>
          </section>

          <section id="php" className="docs-section">
            <h2>PHP integration in 3 files</h2>
            <p>
              Use these three server-side files with the HTML / JavaScript popup example above. Store the API key
              and webhook secret securely, and connect the order-saving and fulfilment hooks to your existing site.
              WordPress, Laravel and CodeIgniter should use their own session, CSRF and request handling conventions.
            </p>
            <CodeBlock
              title="1. autoupi.php — tiny helper class"
              code={`<?php
class AutoUpi {
  private string $key;
  private string $base;

  public function __construct(string $key, string $base = "${origin}/api/public/v1") {
    $this->key = $key;
    $this->base = $base;
  }

  private function request(string $url, ?array $body = null): array {
    $ch = curl_init($url);
    $headers = ["X-API-Key: {$this->key}"];
    if ($body !== null) {
      $headers[] = "Content-Type: application/json";
      curl_setopt($ch, CURLOPT_POST, true);
      curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
    }
    curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_HTTPHEADER => $headers, CURLOPT_TIMEOUT => 20]);
    $res = json_decode(curl_exec($ch), true);
    curl_close($ch);
    return is_array($res) ? $res : ["ok" => false, "error" => "network_error"];
  }

  public function createOrder(float $amount, string $customer = "", string $webhook = ""): array {
    return $this->request($this->base . "/create-order", [
      "amount" => $amount,
      "customer_name" => $customer,
      "webhook_url" => $webhook,
    ]);
  }

  public function status(string $orderId): array {
    return $this->request($this->base . "/order-status?order_id=" . urlencode($orderId));
  }

  public static function verify(string $raw, string $header, string $secret): bool {
    parse_str(str_replace(",", "&", $header), $p);
    if (empty($p["t"]) || empty($p["v1"])) return false;
    return hash_equals(hash_hmac("sha256", $p["t"] . "." . $raw, $secret), $p["v1"]);
  }
}`}
            />
            <CodeBlock
              title="2. checkout.php — return the popup order"
              code={`<?php
require "autoupi.php";
// Require POST, authenticate the buyer, and validate CSRF using your app.
$api = new AutoUpi(getenv("AUTOUPI_KEY"));

$order = $api->createOrder(1499, "Rahul Sharma", "https://yoursite.com/autoupi-webhook.php");

if (empty($order["ok"])) {
  http_response_code(400);
  header("Content-Type: application/json");
  echo json_encode(["ok" => false, "error" => "Could not start payment"]);
  exit;
}

// store it so the webhook can find the buyer later
save_order($order["order_id"], $_SESSION["user_id"], $order["amount"]);

// save_order is your application's function, not an Auto Upi SDK method.
header("Content-Type: application/json");
echo json_encode(["ok" => true, "order_id" => $order["order_id"], "payment_url" => $order["payment_url"]]);
exit;`}
            />
            <CodeBlock
              title="3. autoupi-webhook.php — get paid automatically"
              code={`<?php
require "autoupi.php";

$raw = file_get_contents("php://input");
$sig = $_SERVER["HTTP_X_AUTOUPI_SIGNATURE"] ?? "";

if (!AutoUpi::verify($raw, $sig, getenv("AUTOUPI_WEBHOOK_SECRET"))) {
  http_response_code(401);
  exit("bad signature");
}

$event = json_decode($raw, true);
if (($event["event"] ?? "") === "payment.paid") {
  // amount = your original order value; payable_amount = what the customer actually paid
  // Look up the saved order and verify its amount before fulfilment.
  // Your mark_order_paid function must handle duplicate delivery atomically.
  mark_order_paid($event["order_id"], $event["amount"]);
}

http_response_code(200);
echo "ok";`}
            />
            <p className="docs-note">
              No webhook endpoint yet? Your page can call your own server to check <code>order-status</code> while
              the popup is open and after a result. Authenticate the buyer, check order ownership and fulfil once
              only when the server confirms <code>paid</code>. Never put the API key in that page.
            </p>
          </section>


          <section id="errors" className="docs-section">
            <h2>Errors</h2>
            <table className="docs-table">
              <thead><tr><th>HTTP</th><th>Code</th><th>Fix</th></tr></thead>
              <tbody>
                <tr><td>401</td><td><code>invalid_api_key</code></td><td>Key missing, revoked or replaced by a regenerate.</td></tr>
                <tr><td>400</td><td><code>invalid_amount</code></td><td>Amount must be greater than 0 and up to 10,00,000.</td></tr>
                <tr><td>400</td><td><code>UPI_NOT_CONFIGURED</code></td><td>Save a UPI ID on Connect Accounts first.</td></tr>
                <tr><td>400</td><td><code>QUOTA_EXCEEDED</code></td><td>QR limit finished — upgrade to Pro.</td></tr>
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
                  <li><Check /> Automatic payment confirmation</li>
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
                <a
                  className="docs-btn"
                  href="https://wa.me/918472028929?text=Hello%20Auto%20Upi%2C%20I%20need%20a%20custom%20plan."
                  target="_blank"
                  rel="noreferrer"
                >
                  Contact sales
                </a>
              </div>
            </div>
          </section>

          <section id="faq" className="docs-section">
            <h2>FAQ</h2>
            <div className="docs-faq">
              <div><strong>Do I need a payment gateway account?</strong><p>No. Money reaches your own UPI account directly; Auto Upi only confirms and records the order.</p></div>
              <div><strong>What if two customers pay the same amount?</strong><p>They can't — each active order carries its own unique <code>payable_amount</code>.</p></div>
              <div><strong>How long is a link valid?</strong><p>5 minutes. After that the order becomes <code>expired</code> and moves to Transactions.</p></div>
              <div><strong>Which PHP version do I need?</strong><p>PHP 7.4 or newer with the cURL extension — no composer package required.</p></div>
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
