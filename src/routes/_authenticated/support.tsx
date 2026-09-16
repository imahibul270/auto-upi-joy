import { createFileRoute } from "@tanstack/react-router";
import { LifeBuoy, Mail, MessageCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";

export const Route = createFileRoute("/_authenticated/support")({
  head: () => ({ meta: [
    { title: "autoupi | Support" },
    { name: "description", content: "Get help with your Auto Upi account, payments and integrations." },
    { property: "og:title", content: "autoupi | Support" },
    { property: "og:description", content: "Reach the Auto Upi team for account and payment help." },
  ]}),
  component: SupportPage,
});

const SUPPORT_EMAIL = "support@autoupi.in";
const SUPPORT_WHATSAPP = "918472028929";
const WHATSAPP_MESSAGE = "Hello Auto Upi support, I need help with my account.";
const whatsappUrl = `https://wa.me/${SUPPORT_WHATSAPP}?text=${encodeURIComponent(WHATSAPP_MESSAGE)}`;

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
          <div className="console-support-item"><Mail /><div><strong>Email us</strong><small>{SUPPORT_EMAIL}</small></div></div>
          <div className="console-support-actions">
            <Button asChild size="sm" variant="outline"><a href={`mailto:${SUPPORT_EMAIL}`}>Send email</a></Button>
          </div>
        </article>
        <article className="console-card reveal-delay-2" data-reveal>
          <div className="console-support-item"><MessageCircle /><div><strong>WhatsApp</strong><small>+91 84720 28929</small></div></div>
          <div className="console-support-actions">
            <Button asChild size="sm"><a href={whatsappUrl} target="_blank" rel="noreferrer"><MessageCircle /> Chat on WhatsApp</a></Button>
          </div>
        </article>
        <article className="console-card reveal-delay-3" data-reveal>
          <div className="console-support-item"><LifeBuoy /><div><strong>Help centre</strong><small>Guides for setup, links and payouts</small></div></div>
          <div className="console-support-actions">
            <Button asChild size="sm" variant="outline"><a href="/docs">Open docs</a></Button>
          </div>
        </article>
      </section>
    </ConsoleLayout>
  );
}
