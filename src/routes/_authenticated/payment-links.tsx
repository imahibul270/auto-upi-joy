import { createFileRoute } from "@tanstack/react-router";
import { Link2 } from "lucide-react";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";

export const Route = createFileRoute("/_authenticated/payment-links")({
  head: () => ({ meta: [
    { title: "Payment Links — Auto Upi" },
    { name: "description", content: "Create and share Auto Upi payment links to collect money without writing any code." },
    { property: "og:title", content: "Payment Links — Auto Upi" },
    { property: "og:description", content: "Share a link, get paid instantly with Auto Upi." },
  ]}),
  component: PaymentLinksPage,
});

function PaymentLinksPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);

  return (
    <ConsoleLayout title="Payment Links" user={user} userName={name}>
      <section className="console-page-head" data-reveal>
        <h2>Payment Links</h2>
        <p>Create shareable links and collect payments without any integration.</p>
      </section>
      <section className="console-card reveal-delay-1" data-reveal>
        <div className="console-empty console-empty-row">
          <Link2 />
          <p>No payment links yet</p>
          <small>Link creation unlocks once your account starts generating real payments.</small>
        </div>
      </section>
    </ConsoleLayout>
  );
}
