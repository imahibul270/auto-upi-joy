import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import QRCode from "qrcode";
import { supabase } from "@/integrations/supabase/client";
import { Check, ChevronLeft, ChevronRight, Copy, CreditCard, Landmark } from "lucide-react";
import { brandLogoUrl } from "@/components/BrandLogo";
import { Button } from "@/components/ui/button";
import upiAppsReal from "@/assets/upi-apps-real.jpg.asset.json";
import checkoutSideArt from "@/assets/checkout-side-art.png";

export const Route = createFileRoute("/pay/$slug")({
  head: () => ({ meta: [
    { title: "autoupi | Scan and Pay" },
    { name: "description", content: "Scan the UPI QR code and pay securely through Auto Upi." },
    { property: "og:title", content: "autoupi | Scan and Pay" },
    { property: "og:description", content: "Scan the UPI QR code and pay securely through Auto Upi." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary_large_image" },
  ]}),
  ssr: false,
  component: PayPage,
});

type PublicLink = {
  order_id: string;
  amount: number;
  payable_amount: number;
  status: "active" | "paid" | "expired";
  upi_id: string;
  payee_name: string;
  customer_name: string;
  expires_at: string;
  success_url?: string | null;
  failure_url?: string | null;
  server_now: string;
  provider?: string | null;
  payer_name?: string | null;
  utr?: string | null;
};

function PayPage() {
  const { slug } = Route.useParams();
  const [link, setLink] = useState<PublicLink | null>(null);
  const [qr, setQr] = useState("");
  const [loading, setLoading] = useState(true);
  // Show a short "processing" moment before revealing the paid / expired result.
  const [processing, setProcessing] = useState(false);
  const [shownStatus, setShownStatus] = useState<PublicLink["status"] | null>(null);
  const shownRef = useRef<PublicLink["status"] | null>(null);
  const processingRef = useRef(false);
  // Countdown comes from the server-side expiry, so a refresh never restarts it.
  const [expiryMs, setExpiryMs] = useState<number | null>(null);
  const [skewMs, setSkewMs] = useState(0);
  const [copied, setCopied] = useState(false);
  const [now, setNow] = useState(() => Date.now());
  const [redirectSeconds, setRedirectSeconds] = useState(3);
  const [exitConfirmation, setExitConfirmation] = useState(false);
  const backButtonRef = useRef<HTMLButtonElement>(null);

  const cancelExit = () => {
    setExitConfirmation(false);
    backButtonRef.current?.focus({ preventScroll: true });
  };

  useEffect(() => {
    // Payment results keep priority if detection completes during confirmation.
    if (processing || shownStatus === "paid" || shownStatus === "expired") {
      setExitConfirmation(false);
    }
  }, [processing, shownStatus]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  const secondsLeft =
    expiryMs === null ? 0 : Math.max(0, Math.round((expiryMs - (now + skewMs)) / 1000));

  useEffect(() => {
    let active = true;
    let pending = true;
    void supabase.rpc("register_payment_link_click", { _slug: slug });

    let inFlight = false;
    const kickDetection = () => {
      if (!pending || inFlight) return;
      inFlight = true;
      void fetch("/api/public/payments/poll", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ slug }),
      })
        .then((r) => r.json())
        .then((r: { matched?: number }) => { if (active && (r?.matched ?? 0) > 0) void load(); })
        .catch(() => {})
        .finally(() => { inFlight = false; });
    };

    const load = async () => {
      const { data } = await supabase.rpc("get_public_payment_link", { _slug: slug });
      if (!active) return;
      const next = (data as unknown as PublicLink) ?? null;
      pending = next?.status === "active";
      if (next?.expires_at) {
        setExpiryMs(Date.parse(next.expires_at));
        if (next.server_now) setSkewMs(Date.parse(next.server_now) - Date.now());
      }
      setLink(next);
      setLoading(false);

      if (next) {
        const previous = shownRef.current;
        if (previous === "active" && next.status !== "active") {
          // Hold the QR behind a short processing state before the final result.
          if (!processingRef.current) {
            processingRef.current = true;
            setProcessing(true);
            window.setTimeout(() => {
              processingRef.current = false;
              setProcessing(false);
              shownRef.current = next.status;
              setShownStatus(next.status);
            }, 2000);
          }
        } else if (!processingRef.current) {
          shownRef.current = next.status;
          setShownStatus(next.status);
        }
      }
    };
    void load();
    kickDetection();
    const timer = setInterval(() => void load(), 2000);
    const poller = setInterval(kickDetection, 2000);
    return () => { active = false; clearInterval(timer); clearInterval(poller); };
  }, [slug]);

  const upiParams = link
    ? `pa=${encodeURIComponent(link.upi_id)}&pn=${encodeURIComponent(link.payee_name || "Auto Upi")}&am=${link.payable_amount.toFixed(2)}&cu=INR&tn=${encodeURIComponent(link.order_id)}`
    : "";


  useEffect(() => {
    if (!link || link.status !== "active") return;
    void QRCode.toDataURL(`upi://pay?${upiParams}`, { width: 640, margin: 1, errorCorrectionLevel: "H" })
      .then(setQr);
  }, [link, upiParams]);


  const status = processing ? "active" : shownStatus ?? link?.status ?? "active";
  const redirectTarget = status === "paid" ? link?.success_url : status === "expired" ? link?.failure_url : null;
  const autoCloseUpgrade =
    typeof window !== "undefined" && new URLSearchParams(window.location.search).get("autoclose") === "1";
  // Opened inside a merchant site's popup (checkout.js): tell the parent, never redirect.
  const embedded =
    typeof window !== "undefined" && new URLSearchParams(window.location.search).get("embed") === "1" && window.parent !== window;

  // Tabs opened by our own upgrade flow tell the opener and then close themselves.
  const [closeBlocked, setCloseBlocked] = useState(false);

  // Merchant redirect: send the payer back to the merchant's own result page.
  useEffect(() => {
    if (!link?.order_id || (status !== "paid" && status !== "expired")) return;
    if (autoCloseUpgrade || embedded || !redirectTarget || !/^https?:\/\//i.test(redirectTarget)) return;

    setRedirectSeconds(3);
    const destination = new URL(redirectTarget);
    destination.searchParams.set("order_id", link.order_id);
    destination.searchParams.set("status", status === "paid" ? "paid" : "failed");

    const countdown = window.setInterval(() => {
      setRedirectSeconds((current) => Math.max(1, current - 1));
    }, 1000);
    const redirect = window.setTimeout(() => {
      window.clearInterval(countdown);
      window.location.replace(destination.toString());
    }, 3000);

    return () => {
      window.clearInterval(countdown);
      window.clearTimeout(redirect);
    };
  }, [autoCloseUpgrade, embedded, link?.order_id, redirectTarget, status]);
  useEffect(() => {
    if (!autoCloseUpgrade || !link || (status !== "paid" && status !== "expired")) return;
    const opener = typeof window !== "undefined" ? window.opener : null;
    if (!opener) return;
    try {
      opener.postMessage(
        { type: status === "paid" ? "autoupi:paid" : "autoupi:expired", order_id: link.order_id },
        window.location.origin,
      );
    } catch { /* opener gone */ }
    const id = window.setTimeout(() => {
      window.close();
      window.setTimeout(() => setCloseBlocked(true), 400);
    }, 2000);
    return () => window.clearTimeout(id);
  }, [autoCloseUpgrade, link?.order_id, status]);


  useEffect(() => {
    if (!embedded || !link || (status !== "paid" && status !== "expired")) return;
    // Let the result animation play, then hand the result to the merchant page.
    const id = window.setTimeout(() => {
      window.parent.postMessage(
        { type: status === "paid" ? "autoupi:paid" : "autoupi:failed", order_id: link.order_id },
        "*",
      );
    }, 2500);
    return () => window.clearTimeout(id);
  }, [embedded, link?.order_id, status]);

  const copyOrder = async () => {
    if (!link) return;
    try {
      await navigator.clipboard.writeText(link.order_id);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch { /* clipboard unavailable */ }
  };

  const mm = Math.floor(secondsLeft / 60).toString().padStart(2, "0");
  const ss = (secondsLeft % 60).toString().padStart(2, "0");

  return (
    <div className={`chk-screen${embedded ? " chk-embedded" : ""}`}>
      <div className="chk-shell">
        <aside className="chk-left">
          <div className="chk-left-top">
            <button ref={backButtonRef} type="button" className="chk-back" aria-label="Back" onClick={() => setExitConfirmation(true)}>
              <ChevronLeft />
            </button>
            <img className="chk-logo" src={brandLogoUrl} alt="Auto Upi" />
            {loading ? (
              <span className="pay-skeleton pay-skeleton-title" />
            ) : (
              <h1 className="chk-payee">{link ? link.payee_name || link.upi_id : "Auto Upi"}</h1>
            )}
            <div className="chk-amount">
              {loading ? <span className="pay-skeleton pay-skeleton-amount" /> : link ? <>₹{link.payable_amount.toFixed(2)} <ChevronRight /></> : "—"}
            </div>
          </div>
          <img className="chk-art" src={checkoutSideArt} alt="" width={1024} height={1024} loading="lazy" />
          <div className="chk-secured">
            <span>Secured by</span>
            <img src={brandLogoUrl} alt="" width={18} height={18} />
            <strong>Auto Upi</strong>
          </div>
        </aside>

        <main className="chk-right">
          <div className="chk-head">
            <p>Payment Options for <strong>{loading ? "…" : link?.order_id ?? "—"}</strong></p>
            <button type="button" className="chk-change">Change</button>
          </div>

          {!loading && !link ? (
            <div className="chk-card chk-state"><p className="pay-note">This payment link does not exist.</p></div>
          ) : (
            <div className="chk-card chk-qr-card">
              <div className="chk-qr-col">
                <div className={`pay-qr-wrap chk-qr-wrap${link && (processing || status !== "active") ? " is-blurred" : ""}`}>
                  {qr && !loading ? <img className="pay-qr chk-qr" src={qr} alt="UPI QR code" width={160} height={160} /> : <div className="pay-qr chk-qr pay-skeleton" />}
                  {qr && !loading ? <span className="pay-qr-logo"><img src={brandLogoUrl} alt="" /></span> : null}
                </div>
                <p className="chk-expire">Expires in <b>{mm}:{ss}</b> mins</p>
              </div>
              <div className="chk-apps-col">
                <p>Scan and pay with</p>
                <img className="chk-apps" src={upiAppsReal.url} alt="PhonePe, Google Pay, Paytm and other UPI apps" />
                <p>or other UPI apps</p>
              </div>
            </div>
          )}

          <div className="chk-options-wrap">
          <p className="chk-other-title">Other Payment Options</p>
          <div className="chk-card chk-options">
            <button type="button" className="chk-option">
              <CreditCard className="chk-opt-icon" />
              <span>Card</span>
              <span className="chk-brands"><i>VISA</i><i>MC</i><i>RuPay</i></span>
              <ChevronRight />
            </button>
            <button type="button" className="chk-option">
              <Landmark className="chk-opt-icon" />
              <span>Net Banking</span>
              <span className="chk-brands" />
              <ChevronRight />
            </button>
          </div>
          {exitConfirmation ? (
            <div className="chk-sheet chk-exit-sheet" role="dialog" aria-labelledby="chk-exit-title" onKeyDown={(event) => {
              if (event.key === "Escape") cancelExit();
            }}>
              <div className="chk-badge chk-exit-badge" aria-hidden="true">?</div>
              <div className="chk-sheet-info">
                <h2 id="chk-exit-title">Are you sure you want to exit?</h2>
                <div className="chk-exit-actions">
                  <Button type="button" variant="outline" size="sm" ref={(el) => { el?.focus({ preventScroll: true }); }} onClick={cancelExit}>No</Button>
                  <Button type="button" size="sm" onClick={() => window.history.back()}>Yes</Button>
                </div>
              </div>
            </div>
          ) : link && (processing || status === "paid" || status === "expired") ? (
            <div className={`chk-sheet ${processing ? "is-processing" : status === "paid" ? "is-success" : "is-failed"}`} role="status">
              {processing ? (
                <>
                  <span className="chk-ring" />
                  <h2>Processing payment…</h2>
                  <p>Please don&apos;t close this page</p>
                </>
              ) : (
                <>
                  <div className="chk-badge">
                    <span className="chk-pulse" />
                    {status === "paid" ? <><span className="chk-wave" /><span className="chk-wave chk-wave-2" /></> : null}
                    <svg viewBox="0 0 52 52" className="chk-mark" aria-hidden="true">
                      {status === "paid" ? <path d="M15 27l7 7 15-16" /> : <path d="M17 17l18 18M35 17L17 35" />}
                    </svg>
                  </div>
                  <div className="chk-sheet-info">
                  <h2>{status === "paid" ? "Payment successful" : "Payment failed"}</h2>
                  <b className="chk-sheet-amt">₹{link.amount.toFixed(2)}</b>
                  <div className="chk-sheet-order">
                    <span>Order ID <small>{link.order_id}</small></span>
                    <button type="button" onClick={copyOrder} aria-label="Copy order ID">
                      {copied ? <Check strokeWidth={2.6} /> : <Copy strokeWidth={2.2} />}
                    </button>
                  </div>
                  {redirectTarget && !autoCloseUpgrade && !embedded ? <p>Redirecting back to merchant&apos;s website... {redirectSeconds}s</p> : null}
                  {closeBlocked ? <p>You can close this window.</p> : null}
                  </div>
                </>
              )}
            </div>
          ) : null}
          </div>
          <div className="chk-secured chk-secured-mobile">
            <span>Secured by</span>
            <img src={brandLogoUrl} alt="" width={18} height={18} />
            <strong>Auto Upi</strong>
          </div>
        </main>
      </div>
    </div>
  );
}
