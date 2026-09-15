import { createFileRoute } from "@tanstack/react-router";
import { LifeBuoy, Mail, MessageCircle } from "lucide-react";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";

export const Route = createFileRoute("/_authenticated/support")({
  head: () => ({ meta: [
    { title: "Support — Auto Upi" },
    { name: "description", content: "Get help with your Auto Upi account, payments and integrations." },
    { property: "og:title", content: "Support — Auto Upi" },
    { property: "og:description", content: "Reach the Auto Upi team for account and payment help." },
  ]}),
  component: SupportPage,
});

function SupportPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);

  return (
    <ConsoleLayout title="Support" user={user} userName={name}>
      <section className="console-page-head" data-reveal>
        <h2>Support</h2>
        <p>Need help? Our team usually replies within a few hours.</p>
      </section>
      <section className="console-support-grid">
        <article className="console-card reveal-delay-1" data-reveal>
          <div className="console-support-item"><Mail /><div><strong>Email us</strong><small>support@autoupi.app</small></div></div>
        </article>
        <article className="console-card reveal-delay-2" data-reveal>
          <div className="console-support-item"><MessageCircle /><div><strong>Live chat</strong><small>Available Mon–Sat, 10 AM – 7 PM IST</small></div></div>
        </article>
        <article className="console-card reveal-delay-3" data-reveal>
          <div className="console-support-item"><LifeBuoy /><div><strong>Help centre</strong><small>Guides for setup, links and payouts</small></div></div>
        </article>
      </section>
    </ConsoleLayout>
  );
}
