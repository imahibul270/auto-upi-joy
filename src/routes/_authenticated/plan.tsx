import { createFileRoute } from "@tanstack/react-router";
import { Check, IndianRupee, Phone } from "lucide-react";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";
import { Button } from "@/components/ui/button";
import { Swal } from "@/lib/swal";
import {
  FREE_QR_LIMIT, PRO_PRICE_INR, PRO_QR_LIMIT, SALES_CONTACT_PHONE, daysLeft, useQrQuota,
} from "@/lib/quota";

export const Route = createFileRoute("/_authenticated/plan")({
  head: () => ({ meta: [
    { title: "Plan — Auto Upi" },
    { name: "description", content: "See your current Auto Upi plan, QR limits, validity and upgrade options." },
    { property: "og:title", content: "Plan — Auto Upi" },
    { property: "og:description", content: "Your Auto Upi subscription, QR limits and upgrade options." },
  ]}),
  component: PlanPage,
});

function PlanPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);
  const { data: quota } = useQrQuota();

  const isPro = quota?.plan === "pro";
  const used = quota?.used ?? 0;
  const limit = quota?.limit ?? FREE_QR_LIMIT;
  const remaining = quota?.remaining ?? 0;
  const pct = limit > 0 ? Math.min(Math.round((used / limit) * 100), 100) : 0;
  const left = daysLeft(quota?.period_end ?? null);

  function upgrade() {
    void Swal.fire({
      icon: "info",
      title: `Pro plan — ₹${PRO_PRICE_INR}`,
      html: `30 days validity · ${PRO_QR_LIMIT.toLocaleString("en-IN")} QR codes.<br/>Online payment is being set up. To activate now, contact us at <b>${SALES_CONTACT_PHONE}</b>.`,
      confirmButtonText: "OK",
    });
  }

  function contactSales() {
    void Swal.fire({
      icon: "info",
      title: "Custom plan",
      html: `For a custom plan please contact us at <b>${SALES_CONTACT_PHONE}</b>.`,
      confirmButtonText: "OK",
    });
  }

  return (
    <ConsoleLayout title="Plan" user={user} userName={name}>
      <section className="console-card console-quota reveal-delay-1" data-reveal>
        <div className="console-quota-head">
          <div>
            <span className="console-quota-tag">{isPro ? "PRO" : "FREE"}</span>
            <h3>QR codes used</h3>
          </div>
          <strong>{used} / {limit.toLocaleString("en-IN")}</strong>
        </div>
        <div className="console-quota-bar"><i style={{ width: `${pct}%` }} /></div>
        <div className="console-quota-meta">
          <span>{remaining.toLocaleString("en-IN")} remaining</span>
          <span>
            {isPro && quota?.period_end
              ? `Valid till ${new Date(quota.period_end).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" })}`
              : "Free plan · no expiry"}
          </span>
        </div>
        {!isPro && remaining === 0 ? (
          <p className="console-quota-warn">Free QR limit finished. Upgrade to Pro to generate more.</p>
        ) : null}
      </section>

      <section className="console-plan-grid">
        <article className={`console-card console-plan${!isPro ? " is-active" : ""} reveal-delay-1`} data-reveal>
          <h3>Free</h3>
          <strong>₹0</strong>
          <small>{!isPro ? "Current plan" : "Basic"}</small>
          <ul>
            <li><Check />{FREE_QR_LIMIT} QR codes in total</li>
            <li><Check />Basic analytics</li>
            <li><Check />Email support</li>
          </ul>
        </article>

        <article className={`console-card console-plan${isPro ? " is-active" : ""} reveal-delay-2`} data-reveal>
          <h3>Pro</h3>
          <strong><IndianRupee className="inline-rupee" />{PRO_PRICE_INR}</strong>
          <small>{isPro ? `Active · ${left} day${left === 1 ? "" : "s"} left` : "per 30 days"}</small>
          <ul>
            <li><Check />{PRO_QR_LIMIT.toLocaleString("en-IN")} QR codes in 30 days</li>
            <li><Check />Instant activation on payment</li>
            <li><Check />Priority support</li>
          </ul>
          {!isPro ? (
            <Button className="console-plan-cta" onClick={upgrade}>Upgrade for ₹{PRO_PRICE_INR}</Button>
          ) : null}
        </article>

        <article className="console-card console-plan reveal-delay-3" data-reveal>
          <h3>Custom</h3>
          <strong>Talk to us</strong>
          <small>for higher volume</small>
          <ul>
            <li><Check />Custom QR limits</li>
            <li><Check />Dedicated settlements</li>
            <li><Check />Account manager</li>
          </ul>
          <Button variant="outline" className="console-plan-cta" onClick={contactSales}>
            <Phone /> {SALES_CONTACT_PHONE}
          </Button>
        </article>
      </section>
    </ConsoleLayout>
  );
}
