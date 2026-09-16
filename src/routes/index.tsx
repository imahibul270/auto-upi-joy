import { createFileRoute, Link } from "@tanstack/react-router";
import { BrandLogo } from "@/components/BrandLogo";
import { useProPrice } from "@/lib/quota";
import {
  ArrowRight,
  BarChart3,
  Check,
  CheckCircle2,
  ChevronRight,
  CirclePlay,
  Code2,
  Copy,
  CreditCard,
  Link2,
  Mail,
  Menu,
  Palette,
  ShieldCheck,
  Users,
  Webhook,
  X,
  Zap,
} from "lucide-react";
import { useState, useEffect, useRef } from "react";

export const Route = createFileRoute("/")({
  component: Index,
  head: () => ({
    meta: [
      { title: "autoupi | Payment Infrastructure for India" },
      {
        name: "description",
        content:
          "Create UPI payment links, connect merchant accounts, verify transactions and automate payment updates with Auto Upi.",
      },
      { property: "og:title", content: "Auto Upi — Payments at business speed" },
      {
        property: "og:description",
        content: "A complete UPI payment workflow for modern Indian businesses.",
      },
      { property: "og:type", content: "website" },
      { property: "og:url", content: "/" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
    links: [{ rel: "canonical", href: "/" }],
  }),
});

const features = [
  { icon: Link2, title: "Connect payment accounts", text: "Add Manual UPI, Paytm or supported merchant accounts and manage active connections from one place." },
  { icon: Zap, title: "Instant payment links", text: "Create single-use or reusable links with customer, amount, order reference, callback and expiry controls." },
  { icon: CheckCircle2, title: "UTR review workflow", text: "Customers submit UTR references for Manual UPI. Review and approve before success is confirmed." },
  { icon: Palette, title: "Custom checkout themes", text: "Upload your business logo and select from five professional, responsive payment-page themes." },
  { icon: Webhook, title: "Signed status webhooks", text: "Notify connected systems when payments change state, with delivery history for debugging." },
  { icon: BarChart3, title: "Reports and customers", text: "Understand transactions, revenue, customer activity and payment performance from one dashboard." },
  { icon: Mail, title: "Email notifications", text: "Send welcome messages and instant merchant payment-success alerts." },
  { icon: Users, title: "Referral rewards", text: "Invite merchants with a unique referral link and track registered, qualified and paid rewards." },
  { icon: ShieldCheck, title: "Operational security", text: "Strong protection, rate limiting, audit activity and controlled payment finalization." },
];

const plans = [
  { name: "Free", price: "₹0", suffix: "forever", items: ["3 QR codes in total", "Basic analytics", "Email support"] },
  { name: "Pro", price: "₹299", suffix: "/ 30 days", popular: true, items: ["3,000 QR codes in 30 days", "Instant activation on payment", "Priority support"] },
  { name: "Custom", price: "Talk to us", suffix: "for higher volume", items: ["Custom QR limits", "Dedicated settlements", "Account manager"] },
];

/** Sales / support WhatsApp with a pre-filled message. */
const SUPPORT_WHATSAPP_URL =
  "https://wa.me/918472028929?text=" +
  encodeURIComponent("Hello Auto Upi, I want to know about a custom plan.");


function BrandMark() {
  return <BrandLogo />;
}

function Logo({ compact = false }: { compact?: boolean }) {
  return <a href="#top" className="logo"><BrandMark /><strong>Auto Upi</strong>{!compact && <em>V2</em>}</a>;
}

function QrCode() {
  return (
    <svg className="qr-code" viewBox="0 0 120 120" role="img" aria-label="Demo payment QR code">
      <rect width="120" height="120" fill="currentColor" opacity="0" />
      <path fill="none" stroke="currentColor" strokeWidth="7" d="M6 6h31v31H6zM83 6h31v31H83zM6 83h31v31H6z" />
      <path fill="currentColor" d="M15 15h13v13H15zM92 15h13v13H92zM15 92h13v13H15zM46 7h9v9h-9zM62 7h8v15h-8zM72 19h9v9h-9zM45 28h16v8H45zM53 40h9v11h-9zM67 34h8v18h-8zM78 43h17v8H78zM101 43h12v8h-12zM41 57h9v16h-9zM55 56h18v8H55zM77 57h8v16h-8zM90 56h17v9H90zM8 47h11v9H8zM24 43h9v19h-9zM8 66h23v8H8zM35 76h10v11H35zM50 70h10v9H50zM64 68h9v18h-9zM78 77h15v9H78zM98 69h16v9H98zM43 91h9v23h-9zM57 89h16v9H57zM64 103h9v11h-9zM78 90h8v17h-8zM89 91h24v8H89zM91 105h9v9h-9zM106 103h8v11h-8z" />
    </svg>
  );
}

function PaymentVisual() {
  return (
    <div className="payment-visual" aria-label="Auto Upi payment dashboard preview">
      <div className="dashboard-shell">
        <div className="dash-head"><Logo compact /><span className="live-dot">• LIVE</span></div>
        <div className="dash-grid">
          <div className="revenue-card">
            <small>REVENUE OVERVIEW</small>
            <div className="bars"><i /><i /><i /><i /><i /><i /></div>
          </div>
          <div className="pay-card">
            <small>PAY WITH UPI</small>
            <QrCode />
            <span>Waiting for confirmation...</span>
          </div>
        </div>
      </div>
      <div className="payment-toast payment-toast-top"><span><Check /></span><div><strong>Payment received</strong><small>₹1,499.00 · just now</small></div></div>
      <div className="payment-toast payment-toast-bottom"><span><Webhook /></span><div><strong>Webhook delivered</strong><small>HTTP 200 OK</small></div></div>
    </div>
  );
}

function Index() {
  const { data: proPrice = 299 } = useProPrice();
  const [menuOpen, setMenuOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const headerBarRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onScroll = () => {
      if (headerBarRef.current) {
        headerBarRef.current.classList.toggle("scrolled", window.scrollY > 10);
      }
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  const copyCode = async () => {
    await navigator.clipboard.writeText("curl -X POST https://autoupi.in/api/create-order");
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1500);
  };

  return (
    <main id="top">
      <div className="header-bar" ref={headerBarRef}>
        <header className="site-header">
          <Logo />
          <nav className={menuOpen ? "nav-links nav-open" : "nav-links"} aria-label="Main navigation">
            <a href="#product" onClick={() => setMenuOpen(false)}>Product</a>
            <a href="#how-it-works" onClick={() => setMenuOpen(false)}>How it works</a>
            <a href="#developers" onClick={() => setMenuOpen(false)}>Developers</a>
            <a href="#pricing" onClick={() => setMenuOpen(false)}>Pricing</a>
            <Link to="/docs" onClick={() => setMenuOpen(false)}>API Docs</Link>
            <Link to="/auth" onClick={() => setMenuOpen(false)}>Sign in</Link>
            <Link className="button button-primary nav-cta" to="/register">Create account</Link>
          </nav>
          <button className="menu-button" type="button" aria-label={menuOpen ? "Close menu" : "Open menu"} onClick={() => setMenuOpen(!menuOpen)}>{menuOpen ? <X /> : <Menu />}</button>
        </header>
      </div>
      <section className="hero-section">

        <div className="hero-content">
          <div className="hero-copy page-enter page-enter-left">
            <div className="eyebrow"><span /> PRODUCTION PAYMENT INFRASTRUCTURE · V2</div>
            <h1>Payments that move at the speed of <mark>your business.</mark></h1>
            <p>Create secure UPI checkout links, connect merchant accounts, verify transactions and automate payment updates—all from one focused platform.</p>
            <div className="hero-actions">
              <Link className="button button-primary" to="/register">Start accepting payments <ArrowRight /></Link>
              <a className="button button-outline" href="#how-it-works"><CirclePlay /> View payment demo</a>
            </div>
            <div className="trust-row"><span><ShieldCheck /> Secure checkout</span><span><Webhook /> Real-time webhooks</span><span><Code2 /> Developer-ready API</span></div>
          </div>
          <div className="page-enter page-enter-right"><PaymentVisual /></div>
        </div>
      </section>

      <section className="stat-wrap" aria-label="Platform highlights" data-reveal>
        {[['UPI', 'QR & app intents'], ['24×7', 'Payment collection'], ['REST', 'Simple JSON APIs'], ['Live', 'Status notifications']].map(([value, label]) => <div className="stat" key={value}><strong>{value}</strong><span>{label}</span></div>)}
      </section>

      <section className="section product-section" id="product">
        <div className="section-heading" data-reveal><span>ONE CONNECTED PAYMENT WORKSPACE</span><h2>Everything required to collect,<br /> verify and manage payments.</h2><p>V2 brings the complete workflow together with clearer operations, stronger controls and a checkout that merchants can brand.</p></div>
        <div className="feature-grid">{features.map(({ icon: Icon, title, text }, index) => <article className={`feature-card reveal-delay-${(index % 3) + 1}`} data-reveal key={title}><div className="feature-icon"><Icon /></div><h3>{title}</h3><p>{text}</p><ChevronRight /></article>)}</div>
      </section>

      <section className="workflow-section" id="how-it-works">
        <div className="section workflow-inner">
          <div className="section-heading align-left" data-reveal><span>SIMPLE FROM DAY ONE</span><h2>From account setup to verified payment in four steps.</h2><p>A focused workflow keeps merchants in control while customers get a fast, mobile-ready UPI checkout.</p></div>
          <div className="workflow-grid">
            <div className="steps">
              {[['01','Connect an account','Add the business name, mobile number and merchant UPI details.'],['02','Create an order or payment link','Use the dashboard or REST API with amount, customer and callback data.'],['03','Customer completes UPI payment','Share the hosted checkout with QR, UPI intent and reference submission.'],['04','Verify and automate','Update the transaction, notify the merchant and dispatch the configured webhook.']].map(([n,t,d], index) => <div className={`step reveal-delay-${index + 1}`} data-reveal key={n}><span>{n}</span><div><h3>{t}</h3><p>{d}</p></div></div>)}
            </div>
            <div className="checkout-card reveal-delay-2" data-reveal>
              <div className="verified"><CheckCircle2 /> Verified merchant</div><h3>Your Business</h3><small>ORDER REF: ORD2026V2</small><strong>₹1,499.00</strong><div className="qr-wrap"><QrCode /></div><p>merchant@upi · Scan demo QR</p><button className="button button-primary" type="button">Pay with any UPI app</button>
            </div>
          </div>
        </div>
      </section>

      <section className="developer-section" id="developers">
        <div className="section developer-grid">
          <div data-reveal><div className="section-heading align-left light"><span>BUILT FOR DEVELOPERS</span><h2>A clean API, without the integration maze.</h2><p>Create an order with JSON, redirect the customer to hosted checkout and verify the result through status APIs or webhooks.</p></div><div className="dev-points"><span><strong>API credentials</strong>Dedicated key and secret</span><span><strong>Order status</strong>Server-side verification</span><span><strong>Webhooks</strong>Automatic event delivery</span></div><Link className="button button-primary" to="/docs">Read API documentation <ArrowRight /></Link></div>
          <div className="code-panel reveal-delay-2" data-reveal id="code-example"><div className="code-head"><span><i /><i /><i /></span><small>create-order.php</small><button type="button" onClick={copyCode} aria-label="Copy API example">{copied ? <Check /> : <Copy />}</button></div><pre><code><b>curl</b> -X POST https://autoupi.in/api/create-order \
  -H <em>"X-API-Key: pi_live_your_key"</em> \
  -H <em>"X-API-Secret: sk_live_your_secret"</em> \
  -H <em>"Content-Type: application/json"</em> \
  -d '{'{'}
    <i>"amount"</i>: <em>"1499.00"</em>,
    <i>"order_id"</i>: <em>"ORD_2026_V2"</em>,
    <i>"customer_name"</i>: <em>"Customer Name"</em>,
    <i>"callback_url"</i>: <em>"https://shop.example/success"</em>
  {'}'}'</code></pre></div>
        </div>
      </section>

      <section className="section pricing-section" id="pricing">
        <div className="section-heading" data-reveal><span>PLANS THAT SCALE WITH YOU</span><h2>Start focused. Upgrade when ready.</h2><p>Simple plans for every stage of your payment journey.</p></div>
        <div className="pricing-grid">{plans.map((plan, index) => <article className={`${plan.popular ? "price-card popular" : "price-card"} reveal-delay-${index + 1}`} data-reveal key={plan.name}>{plan.popular && <div className="popular-label">MOST POPULAR</div>}<h3>{plan.name}</h3><div className="price"><strong>{plan.name === 'Pro' ? `₹${proPrice.toLocaleString('en-IN')}` : plan.price}</strong><span>{plan.suffix}</span></div><ul>{plan.items.map(item => <li key={item}><Check /> {item}</li>)}</ul>{plan.name === 'Custom' ? <a className="button button-dark" href={SUPPORT_WHATSAPP_URL} target="_blank" rel="noreferrer">Talk on WhatsApp +91 84720 28929 <ArrowRight /></a> : <a className={plan.popular ? "button button-primary" : "button button-dark"} href="mailto:support@autoupi.in">Choose {plan.name} <ArrowRight /></a>}</article>)}</div>
      </section>

       <section className="cta-section" data-reveal><div><span>READY FOR PRODUCTION</span><h2>Turn every payment into a clear,<br /> trackable workflow.</h2><p>Set up your merchant workspace and create your first payment link.</p><Link className="button button-primary" to="/register">Create free account <ArrowRight /></Link></div></section>
      <footer data-reveal><div><Logo /><p>Payment infrastructure built for ambitious Indian businesses.</p></div><div><a href="#product">Product</a><a href="#developers">Developers</a><Link to="/docs">API Docs</Link><a href="#pricing">Pricing</a></div><span>© 2026 Auto Upi. All rights reserved.</span></footer>
    </main>
  );
}
