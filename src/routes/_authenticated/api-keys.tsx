import { createFileRoute } from "@tanstack/react-router";
import { KeyRound } from "lucide-react";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";

export const Route = createFileRoute("/_authenticated/api-keys")({
  head: () => ({ meta: [
    { title: "API Keys — Auto Upi" },
    { name: "description", content: "Manage the API keys your apps use to talk to Auto Upi." },
    { property: "og:title", content: "API Keys — Auto Upi" },
    { property: "og:description", content: "Create and rotate keys for your Auto Upi integrations." },
  ]}),
  component: ApiKeysPage,
});

function ApiKeysPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);

  return (
    <ConsoleLayout title="API Keys" userName={name}>
      <section className="console-page-head" data-reveal>
        <h2>API Keys</h2>
        <p>Keys let your website or app create payments through Auto Upi.</p>
      </section>
      <section className="console-card reveal-delay-1" data-reveal>
        <div className="console-empty console-empty-row">
          <KeyRound />
          <p>No API keys yet</p>
          <small>Keys will be issued once live payments are enabled on your account.</small>
        </div>
      </section>
    </ConsoleLayout>
  );
}
