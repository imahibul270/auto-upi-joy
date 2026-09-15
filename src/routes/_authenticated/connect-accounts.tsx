import { createFileRoute } from "@tanstack/react-router";
import { CreditCard } from "lucide-react";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";

export const Route = createFileRoute("/_authenticated/connect-accounts")({
  head: () => ({ meta: [
    { title: "Connect Accounts — Auto Upi" },
    { name: "description", content: "Connect your UPI IDs and bank accounts so settlements reach you automatically." },
    { property: "og:title", content: "Connect Accounts — Auto Upi" },
    { property: "og:description", content: "Link UPI IDs and bank accounts for automatic settlements." },
  ]}),
  component: ConnectAccountsPage,
});

function ConnectAccountsPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);

  return (
    <ConsoleLayout title="Connect Accounts" userName={name}>
      <section className="console-page-head" data-reveal>
        <h2>Connect Accounts</h2>
        <p>Add the UPI IDs and bank accounts where your money should settle.</p>
      </section>
      <section className="console-card reveal-delay-1" data-reveal>
        <div className="console-empty console-empty-row">
          <CreditCard />
          <p>No accounts connected</p>
          <small>Connect an account to start receiving real settlements.</small>
        </div>
      </section>
    </ConsoleLayout>
  );
}
