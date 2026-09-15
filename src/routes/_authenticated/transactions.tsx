import { createFileRoute } from "@tanstack/react-router";
import { Receipt } from "lucide-react";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";

export const Route = createFileRoute("/_authenticated/transactions")({
  head: () => ({ meta: [
    { title: "Transactions — Auto Upi" },
    { name: "description", content: "View every UPI, card and netbanking transaction captured by your Auto Upi account." },
    { property: "og:title", content: "Transactions — Auto Upi" },
    { property: "og:description", content: "Every payment your Auto Upi account has processed, in one searchable list." },
  ]}),
  component: TransactionsPage,
});

function TransactionsPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);

  return (
    <ConsoleLayout title="Transactions" user={user} userName={name}>
      <section className="console-page-head" data-reveal>
        <h2>Transactions</h2>
        <p>All payments captured on your account will be listed here.</p>
      </section>
      <section className="console-card reveal-delay-1" data-reveal>
        <div className="console-empty console-empty-row">
          <Receipt />
          <p>No transactions yet</p>
          <small>Once a real payment is generated, it will appear here with status, amount and method.</small>
        </div>
      </section>
    </ConsoleLayout>
  );
}
