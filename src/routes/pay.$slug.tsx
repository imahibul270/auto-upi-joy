import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import QRCode from "qrcode";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import bhimUpiLogo from "@/assets/bhim-upi-logo.png.asset.json";
import upiAppsRow from "@/assets/upi-apps-row.png.asset.json";

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
  // Countdown comes from the server-side expiry, so a refresh never restarts it.
  const [expiryMs, setExpiryMs] = useState<number | null>(null);
  const [skewMs, setSkewMs] = useState(0);
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

  return (
    <div className="pay-screen">
      <div className="pay-card">
        <header className="pay-head">
          <img className="pay-bhim-logo" src={bhimUpiLogo.url} alt="BHIM UPI" />
          {!loading && link && (
            <>
              <h1 className="pay-payee">{link.payee_name || link.upi_id}</h1>
              <p className="pay-transfer-label">Transfer to</p>
            </>
          )}
        </header>
        {loading ? (
          <div className="pay-state"><p className="pay-note">Loading payment…</p></div>
        ) : !link ? (
          <div className="pay-state"><p className="pay-note">This payment link does not exist.</p></div>
        ) : link.status === "paid" ? (
          <div className="pay-state">
            <h1 className="pay-amount">₹{link.payable_amount.toFixed(2)}</h1>
            <p className="pay-success">Payment received</p>
            <p className="pay-note">Order {link.order_id}</p>
          </div>
        ) : link.status === "expired" ? (
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
              {qr ? <img className="pay-qr" src={qr} alt="UPI QR code" width={250} height={250} /> : <div className="pay-qr pay-qr-skeleton" />}
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
