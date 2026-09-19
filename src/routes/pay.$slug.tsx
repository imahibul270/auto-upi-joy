import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import QRCode from "qrcode";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Check, Copy, Store } from "lucide-react";
import { brandLogoUrl } from "@/components/BrandLogo";
import bhimUpiLogo from "@/assets/bhim-upi-logo.png.asset.json";
import upiAppsRow from "@/assets/upi-apps-row.png.asset.json";
import paytmLogo from "@/assets/paytm-logo.png.asset.json";

export const Route = createFileRoute("/pay/$slug")({
  head: () => ({ meta: [
    { title: "autoupi | Scan and Pay" },
    { name: "description", content: "Scan the UPI QR code and pay securely through Auto Upi." },
    { property: "og:title", content: "autoupi | Scan and Pay" },
    { property: "og:description", content: "Scan the UPI QR code and pay securely through Auto Upi." },
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
  server_now: string;
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

    const kickDetection = () => {
      if (!pending) return;
      void fetch("/api/public/payments/poll", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ slug }),
      }).catch(() => {});
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
    const poller = setInterval(kickDetection, 3000);
    return () => { active = false; clearInterval(timer); clearInterval(poller); };
  }, [slug]);

  useEffect(() => {
    if (!link || link.status !== "active") return;
    const uri = `upi://pay?pa=${encodeURIComponent(link.upi_id)}&pn=${encodeURIComponent(link.payee_name || "Auto Upi")}&am=${link.payable_amount.toFixed(2)}&cu=INR&tn=${encodeURIComponent(link.order_id)}`;
    void QRCode.toDataURL(uri, { width: 640, margin: 1, errorCorrectionLevel: "H" }).then(setQr);
  }, [link]);

  const status = processing ? "active" : shownStatus ?? link?.status ?? "active";

  // Tabs opened by our own upgrade flow tell the opener and then close themselves.
  const [closeBlocked, setCloseBlocked] = useState(false);
  useEffect(() => {
    if (!link || (status !== "paid" && status !== "expired")) return;
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
  }, [link, status]);


  const copyOrder = async () => {
    if (!link) return;
    try {
      await navigator.clipboard.writeText(link.order_id);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch { /* clipboard unavailable */ }
  };

  if (!loading && link && status === "paid") {
    return (
      <div className="pay-screen">
        <div className="pay-done">
          <div className="pay-done-top">
            <div className="pay-done-tick"><Check strokeWidth={4} /></div>
            <h1>Payment successful!</h1>
            <p>Redirecting back to merchant&apos;s website...</p>
          </div>
          <div className="pay-done-row">
            <span className="pay-done-avatar"><Store strokeWidth={2.4} /></span>
            <div className="pay-done-meta">
              <strong>{link.order_id}</strong>
              <b>₹{link.amount.toFixed(2)}</b>
            </div>
          </div>
          <div className="pay-done-order">
            <div>
              <span>Order ID</span>
              <small>{link.order_id}</small>
            </div>
            <button type="button" onClick={copyOrder} aria-label="Copy order ID">
              {copied ? <Check strokeWidth={2.6} /> : <Copy strokeWidth={2.2} />}
            </button>
          </div>
          {closeBlocked ? <p className="pay-done-note">You can close this window.</p> : null}
        </div>

      </div>
    );
  }

  return (
    <div className="pay-screen">
      <div className="pay-card">
        <header className="pay-head">
          <img className="pay-bhim-logo" src={bhimUpiLogo.url} alt="BHIM UPI" />
          {loading ? (
            <>
              <span className="pay-skeleton pay-skeleton-title" />
              <span className="pay-skeleton pay-skeleton-line" />
            </>
          ) : link ? (
            <>
              <h1 className="pay-payee">{link.payee_name || link.upi_id}</h1>
              <p className="pay-transfer-label">Transfer to</p>
            </>
          ) : null}
        </header>
        {loading ? (
          <>
            <section className="pay-total">
              <span>Total Amount</span>
              <strong><span className="pay-skeleton pay-skeleton-amount" /></strong>
            </section>
            <section className="pay-code-area">
              <div className="pay-qr pay-skeleton" />
              <span className="pay-skeleton pay-skeleton-apps" />
            </section>
            <footer className="pay-footer">
              <span className="pay-skeleton pay-skeleton-line" />
              <span className="pay-skeleton pay-skeleton-button" />
            </footer>
          </>
        ) : !link ? (
          <div className="pay-state"><p className="pay-note">This payment link does not exist.</p></div>
        ) : status === "paid" ? (
          <div className="pay-state">
            <h1 className="pay-amount">₹{link.payable_amount.toFixed(2)}</h1>
            <p className="pay-success">Payment received</p>
            <p className="pay-note">Order {link.order_id}</p>
          </div>
        ) : status === "expired" ? (
          <div className="pay-state">
            <h1 className="pay-amount">₹{link.payable_amount.toFixed(2)}</h1>
            <p className="pay-note">This payment link has expired.</p>
          </div>
        ) : (
          <>
            <section className="pay-total">
              <span>Total Amount</span>
              <strong>₹{link.payable_amount.toFixed(2)}</strong>
            </section>
            <section className="pay-code-area">
              <div className="pay-qr-wrap">
                {qr ? <img className="pay-qr" src={qr} alt="UPI QR code" width={250} height={250} /> : <div className="pay-qr pay-skeleton" />}
                {qr ? <span className="pay-qr-logo"><img src={brandLogoUrl} alt="" /></span> : null}
                {processing && (
                  <div className="pay-processing">
                    <span className="pay-spinner" />
                    <p>Processing payment…</p>
                  </div>
                )}
              </div>
              <img className="pay-apps" src={upiAppsRow.url} alt="Supported UPI payment apps" />
            </section>
            <footer className="pay-footer">
              <p>Expire in <strong>{Math.floor(secondsLeft / 60).toString().padStart(2, "0")}:{(secondsLeft % 60).toString().padStart(2, "0")}</strong></p>
              <Button type="button" className="pay-cancel">Cancel</Button>
            </footer>
          </>
        )}
      </div>
    </div>
  );
}
