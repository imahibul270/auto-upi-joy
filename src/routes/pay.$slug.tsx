import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import QRCode from "qrcode";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/pay/$slug")({
  head: () => ({ meta: [
    { title: "Scan and Pay — Auto Upi" },
    { name: "description", content: "Scan the UPI QR code and pay securely through Auto Upi." },
    { property: "og:title", content: "Scan and Pay — Auto Upi" },
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
};

function PayPage() {
  const { slug } = Route.useParams();
  const [link, setLink] = useState<PublicLink | null>(null);
  const [qr, setQr] = useState("");
  const [loading, setLoading] = useState(true);

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
        <span className="pay-brand">Auto Upi</span>
        {loading ? (
          <p className="pay-note">Loading payment…</p>
        ) : !link ? (
          <p className="pay-note">This payment link does not exist.</p>
        ) : link.status === "paid" ? (
          <>
            <h1 className="pay-amount">₹{link.payable_amount.toFixed(2)}</h1>
            <p className="pay-success">Payment received</p>
            <p className="pay-note">Order {link.order_id}</p>
          </>
        ) : link.status === "expired" ? (
          <>
            <h1 className="pay-amount">₹{link.payable_amount.toFixed(2)}</h1>
            <p className="pay-note">This payment link has expired.</p>
          </>
        ) : (
          <>
            <p className="pay-payee">{link.payee_name || link.upi_id}</p>
            <h1 className="pay-amount">₹{link.payable_amount.toFixed(2)}</h1>
            {qr ? <img className="pay-qr" src={qr} alt="UPI QR code" width={220} height={220} /> : <div className="pay-qr pay-qr-skeleton" />}
            <p className="pay-note">Pay the exact amount so it is detected automatically.</p>
            <p className="pay-order">Order {link.order_id}</p>
          </>
        )}
      </div>
    </div>
  );
}
