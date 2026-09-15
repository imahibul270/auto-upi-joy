import { createFileRoute } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";
import { Copy, Link2, Sparkles, XCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";
import { Swal } from "@/lib/swal";
import {
  createPaymentLink,
  expirePaymentLink,
  formatDate,
  formatInr,
  paymentLinkUrl,
  useActiveLinks,
  usePaymentDetection,
  useMerchantAccounts,
} from "@/lib/gateway";

export const Route = createFileRoute("/_authenticated/payment-links")({
  head: () => ({ meta: [
    { title: "Payment Links — Auto Upi" },
    { name: "description", content: "Create and share Auto Upi payment links to collect money without writing any code." },
    { property: "og:title", content: "Payment Links — Auto Upi" },
    { property: "og:description", content: "Share a link, get paid instantly with Auto Upi." },
  ]}),
  component: PaymentLinksPage,
});

const LINK_ERRORS: Record<string, string> = {
  UPI_NOT_CONFIGURED: "Save a UPI ID on Connect Accounts first.",
  INVALID_AMOUNT: "Enter an amount between ₹1 and ₹10,00,000.",
  ALL_PAYMENT_SLOTS_BUSY: "Too many open links for this amount. Try again in a moment.",
};

function PaymentLinksPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);
  const queryClient = useQueryClient();
  usePaymentDetection();
  const { rows: links } = useActiveLinks();
  const { data: accounts = [] } = useMerchantAccounts();
  const [amount, setAmount] = useState("");
  const [customer, setCustomer] = useState("");
  const [creating, setCreating] = useState(false);

  const hasUpi = accounts.some((item) => item.upi_id);

  async function copyLink(slug: string) {
    try {
      await navigator.clipboard.writeText(paymentLinkUrl(slug));
      void Swal.fire({ icon: "success", title: "Link copied", timer: 1200, showConfirmButton: false });
    } catch {
      void Swal.fire({ icon: "error", title: "Could not copy", text: paymentLinkUrl(slug) });
    }
  }

  async function generate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setCreating(true);
    try {
      const created = await createPaymentLink({ amount: Number(amount), customerName: customer });
      setAmount("");
      setCustomer("");
      await queryClient.invalidateQueries({ queryKey: ["payment-links"] });
      void Swal.fire({
        icon: "success",
        title: "Payment link ready",
        html: `Order <b>${created.order_id}</b><br/>Payable amount <b>${formatInr(created.payable_amount)}</b>`,
        draggable: true,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const key = Object.keys(LINK_ERRORS).find((code) => message.includes(code));
      void Swal.fire({ icon: "error", title: "Could not generate link", text: key ? LINK_ERRORS[key] : message });
    } finally {
      setCreating(false);
    }
  }

  function cancelLink(id: string) {
    void Swal.fire({
      icon: "warning",
      title: "Expire this link?",
      text: "Customers will no longer be able to pay with it.",
      showCancelButton: true,
      confirmButtonText: "Yes, expire",
      cancelButtonText: "Cancel",
    }).then(async (result) => {
      if (!result.isConfirmed) return;
      await expirePaymentLink(id);
      await queryClient.invalidateQueries({ queryKey: ["payment-links"] });
    });
  }

  return (
    <ConsoleLayout title="Payment Links" user={user} userName={name}>
      <section className="console-page-head" data-reveal>
        <h2>Payment Links</h2>
        <p>Create shareable links and collect payments without any integration.</p>
      </section>

      <section className="console-card reveal-delay-1" data-reveal>
        <div className="console-card-head"><h3>Generate link</h3><small>{hasUpi ? "Uses your saved UPI ID" : "Save a UPI ID first"}</small></div>
        <form className="console-link-form" onSubmit={generate}>
          <label className="console-field">
            Amount (₹)
            <Input type="number" min="1" step="0.01" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="1.00" required />
          </label>
          <label className="console-field">
            Customer name
            <Input value={customer} onChange={(event) => setCustomer(event.target.value)} placeholder="Aminul" />
          </label>
          <Button type="submit" disabled={creating || !hasUpi}><Sparkles />{creating ? "Generating…" : "Generate link"}</Button>
        </form>
      </section>

      <section className="console-card reveal-delay-2" data-reveal>
        <div className="console-card-head"><h3>Active links</h3><small>Paid and expired links move to Transactions</small></div>
        {links.length === 0 ? (
          <div className="console-empty console-empty-row">
            <Link2 />
            <p>No active links</p>
            <small>Generate a link above; settled links are listed under Transactions.</small>
          </div>
        ) : (
          <div className="console-table-wrap">
            <table className="console-table">
              <thead>
                <tr>
                  <th>ORDER ID</th><th>CUSTOMER</th><th>AMOUNT</th><th>LINK URL</th>
                  <th>TYPE</th><th>STATUS</th><th>CLICKS / PAID</th><th>CREATED</th><th />
                </tr>
              </thead>
              <tbody>
                {links.map((row) => (
                  <tr key={row.id}>
                    <td><strong>{row.order_id}</strong></td>
                    <td className="console-cell-customer">{row.customer_name || "—"}</td>
                    <td><strong>{formatInr(row.payable_amount)}</strong></td>
                    <td>
                      <span className="console-secret">
                        <code>{paymentLinkUrl(row.slug).replace(/^https?:\/\//, "").slice(0, 26)}…</code>
                        <button type="button" aria-label="Copy payment link" onClick={() => void copyLink(row.slug)}><Copy /></button>
                      </span>
                    </td>
                    <td><span className="console-pill is-type">{row.link_type === "reusable" ? "Reusable" : "One-Time"}</span></td>
                    <td>
                      <span className={`console-pill ${row.status === "paid" ? "is-paid" : row.status === "expired" ? "is-muted" : "is-active"}`}>
                        {row.status === "paid" ? "Paid" : row.status === "expired" ? "Expired" : "Active"}
                      </span>
                    </td>
                    <td><strong>{row.clicks}</strong> / <strong className="console-paid-count">{row.paid_count}</strong></td>
                    <td>{formatDate(row.created_at)}</td>
                    <td>{row.status === "active" ? <button type="button" className="console-row-action" aria-label="Expire link" onClick={() => cancelLink(row.id)}><XCircle /></button> : null}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </ConsoleLayout>
  );
}
