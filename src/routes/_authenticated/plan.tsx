import { createFileRoute } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { Check, IndianRupee, Phone } from "lucide-react";
import { checkProUpgrade, startProUpgrade } from "@/lib/upgrade.functions";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";
import { Button } from "@/components/ui/button";
import { Swal } from "@/lib/swal";
import {
  FREE_QR_LIMIT, PRO_QR_LIMIT, SALES_CONTACT_PHONE, SALES_WHATSAPP_URL, daysLeft, useProPrice, useQrQuota,
} from "@/lib/quota";

/** Shows a result popup with a live "redirecting" countdown, then goes to the dashboard. */
function resultThenRedirect(options: { icon: "success" | "error" | "info"; title: string; html?: string; seconds?: number }) {
  const total = (options.seconds ?? 3) * 1000;
  const line = (s: number) => `Redirecting to your plan page… ${Math.max(s, 0)}s`;
  return Swal.fire({
    icon: options.icon,
    title: options.title,
    html: `${options.html ? `${options.html}<br/>` : ""}<b class="swal-countdown">${line(Math.round(total / 1000))}</b>`,
    timer: total,
    timerProgressBar: true,
    showConfirmButton: false,
    allowOutsideClick: false,
    didOpen: () => {
      const node = Swal.getHtmlContainer()?.querySelector(".swal-countdown");
      const id = window.setInterval(() => {
        const left = Math.ceil((Swal.getTimerLeft() ?? 0) / 1000);
        if (node) node.textContent = line(left);
      }, 250);
      (Swal as unknown as { __countdown?: number }).__countdown = id;
    },
    willClose: () => {
      window.clearInterval((Swal as unknown as { __countdown?: number }).__countdown);
    },
  }).then(() => {
    window.location.href = "/plan";
  });
}


export const Route = createFileRoute("/_authenticated/plan")({
  head: () => ({ meta: [
    { title: "autoupi | Plan" },
    { name: "description", content: "See your current Auto Upi plan, QR limits, validity and upgrade options." },
    { property: "og:title", content: "autoupi | Plan" },
    { property: "og:description", content: "Your Auto Upi subscription, QR limits and upgrade options." },
  ]}),
  component: PlanPage,
});

function PlanPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);
  const { data: quota } = useQrQuota();
  const { data: proPrice = 299 } = useProPrice();
  const queryClient = useQueryClient();
  const start = useServerFn(startProUpgrade);
  const check = useServerFn(checkProUpgrade);
  const [paying, setPaying] = useState(false);
  const timers = useRef<number[]>([]);

  useEffect(() => () => timers.current.forEach((id) => window.clearInterval(id)), []);


  const isPro = quota?.plan === "pro";
  const used = quota?.used ?? 0;
  const limit = quota?.limit ?? FREE_QR_LIMIT;
  const remaining = quota?.remaining ?? 0;
  const pct = limit > 0 ? Math.min(Math.round((used / limit) * 100), 100) : 0;
  const left = daysLeft(quota?.period_end ?? null);

  async function upgrade() {
    if (paying) return;
    setPaying(true);
    const tab = window.open("", "_blank");
    try {
      const order = await start({ data: { origin: window.location.origin } });
      if (tab) tab.location.href = order.payment_url;
      else window.location.href = order.payment_url;

      void Swal.fire({
        title: "Waiting for payment…",
        html: `<b>${order.order_id}</b>`,
        allowOutsideClick: false,
        didOpen: () => Swal.showLoading(),
      });

      const started = Date.now();
      let done = false;
      let onMessage: ((event: MessageEvent) => void) | null = null;

      const finish = (run: () => void) => {
        if (done) return;
        done = true;
        window.clearInterval(id);
        if (onMessage) window.removeEventListener("message", onMessage);
        setPaying(false);
        Swal.close();
        run();
      };

      const tick = async () => {
        if (done) return;
        if (Date.now() - started > 6 * 60 * 1000) {
          finish(() => void resultThenRedirect({ icon: "info", title: "Payment window closed" }));
          return;
        }
        const result = await check({ data: { order_id: order.order_id } }).catch(() => null);
        if (result?.status === "paid") {
          await queryClient.invalidateQueries({ queryKey: ["qr-quota"] });
          finish(() =>
            void resultThenRedirect({
              icon: "success",
              title: "Payment successful",
              html: `Pro is active · ${PRO_QR_LIMIT.toLocaleString("en-IN")} QR codes for 30 days.`,
            }),
          );
        } else if (result?.status === "expired") {
          finish(() => void resultThenRedirect({ icon: "error", title: "Payment failed", html: "The payment link expired." }));
        }
      };

      const id = window.setInterval(() => void tick(), 3000);
      timers.current.push(id);

      // The payment tab tells us the moment it finishes, so we don't wait for the next poll.
      onMessage = (event: MessageEvent) => {
        if (event.origin !== window.location.origin) return;
        const data = event.data as { type?: string; order_id?: string } | null;
        if (!data || data.order_id !== order.order_id) return;
        if (data.type === "autoupi:paid" || data.type === "autoupi:expired") void tick();
      };
      window.addEventListener("message", onMessage);

    } catch (error) {
      tab?.close();
      setPaying(false);
      Swal.close();
      void Swal.fire({
        icon: "error",
        title: "Could not start payment",
        html: `${error instanceof Error ? error.message : String(error)}<br/>Need help? WhatsApp <b>${SALES_CONTACT_PHONE}</b>.`,
      });
    }
  }

  function contactSales() {
    window.open(SALES_WHATSAPP_URL, "_blank", "noopener,noreferrer");
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
          {!isPro ? <span className="console-plan-badge">Current plan</span> : null}
          <h3>Free</h3>
          <strong>₹0</strong>
          <small>{!isPro ? `${remaining.toLocaleString("en-IN")} of ${limit.toLocaleString("en-IN")} QR left` : "Basic"}</small>
          <ul>
            <li><Check />{(!isPro ? limit : FREE_QR_LIMIT).toLocaleString("en-IN")} QR codes in total</li>
            <li><Check />Basic analytics</li>
            <li><Check />Email support</li>
          </ul>
        </article>

        <article className={`console-card console-plan${isPro ? " is-active" : ""} reveal-delay-2`} data-reveal>
          {isPro ? <span className="console-plan-badge">Current plan</span> : null}
          <h3>Pro</h3>
          <strong><IndianRupee className="inline-rupee" />{proPrice.toLocaleString("en-IN")}</strong>
          <small>{isPro ? `${left} day${left === 1 ? "" : "s"} left · ${remaining.toLocaleString("en-IN")} QR left` : "per 30 days"}</small>
          <ul>
            <li><Check />{(isPro ? limit : PRO_QR_LIMIT).toLocaleString("en-IN")} QR codes in 30 days</li>
            <li><Check />Instant activation on payment</li>
            <li><Check />Priority support</li>
          </ul>
          {!isPro ? (
            <Button className="console-plan-cta" onClick={() => void upgrade()} disabled={paying}>
              {paying ? "Opening payment…" : `Upgrade for ₹${proPrice.toLocaleString("en-IN")}`}
            </Button>
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
