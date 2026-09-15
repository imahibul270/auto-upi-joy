import { createFileRoute } from "@tanstack/react-router";
import { Check } from "lucide-react";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";

export const Route = createFileRoute("/_authenticated/plan")({
  head: () => ({ meta: [
    { title: "Plan — Auto Upi" },
    { name: "description", content: "See your current Auto Upi plan, limits and upgrade options." },
    { property: "og:title", content: "Plan — Auto Upi" },
    { property: "og:description", content: "Your Auto Upi subscription, limits and upgrade options." },
  ]}),
  component: PlanPage,
});

const PLANS = [
  { name: "Free", price: "₹0", note: "Current plan", points: ["Up to 50 payments / month", "Basic analytics", "Email support"], active: true },
  { name: "Starter", price: "₹499", note: "per month", points: ["Unlimited payments", "Payment links", "Priority support"] },
  { name: "Business", price: "Custom", note: "talk to us", points: ["Dedicated settlements", "Custom webhooks", "Account manager"] },
];

function PlanPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);

  return (
    <ConsoleLayout title="Plan" user={user} userName={name}>
      <section className="console-page-head" data-reveal>
        <h2>Your Plan</h2>
        <p>You are on the Free plan. Upgrade anytime as your payment volume grows.</p>
      </section>
      <section className="console-plan-grid">
        {PLANS.map((p, i) => (
          <article key={p.name} className={`console-card console-plan${p.active ? " is-active" : ""} reveal-delay-${i + 1}`} data-reveal>
            <h3>{p.name}</h3>
            <strong>{p.price}</strong>
            <small>{p.note}</small>
            <ul>
              {p.points.map((point) => (
                <li key={point}><Check />{point}</li>
              ))}
            </ul>
          </article>
        ))}
      </section>
    </ConsoleLayout>
  );
}
