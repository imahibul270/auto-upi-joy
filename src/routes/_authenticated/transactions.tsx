import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { Receipt, Search } from "lucide-react";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";
import {
  detectionSeconds,
  formatInr,
  formatTime,
  usePaymentDetection,
  useTransactions,
} from "@/lib/gateway";

export const Route = createFileRoute("/_authenticated/transactions")({
  head: () => ({ meta: [
    { title: "autoupi | Transactions" },
    { name: "description", content: "View every UPI payment captured by your Auto Upi account, with payer name and detection time." },
    { property: "og:title", content: "autoupi | Transactions" },
    { property: "og:description", content: "Every payment your Auto Upi account has processed, in one live list." },
  ]}),
  component: TransactionsPage,
});

function TransactionsPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);
  usePaymentDetection();
  const { rows } = useTransactions();
  const [search, setSearch] = useState("");

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter((row) => `${row.order_id} ${row.customer_name}`.toLowerCase().includes(q));
  }, [rows, search]);

  return (
    <ConsoleLayout title="Transactions" user={user} userName={name}>
      <section className="console-card reveal-delay-1" data-reveal>
        <div className="console-card-head">
          <h3>All transactions</h3>
          <div className="console-search">
            <Search />
            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search order ID" />
          </div>
        </div>
        {filtered.length === 0 ? (
          <div className="console-empty console-empty-row">
            <Receipt />
            <p>{search.trim() ? "No matching transaction" : "No transactions yet"}</p>
            <small>{search.trim() ? "Check the order ID and try again." : "Once a payment is detected or a link expires, it appears here."}</small>
          </div>
        ) : (
          <div className="console-table-wrap">
            <table className="console-table">
              <thead>
                <tr>
                  <th>ORDER ID</th><th>CUSTOMER</th><th>PAYER</th><th>AMOUNT</th>
                  <th>STATUS</th><th>DETECTED IN</th><th>TIME</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => {
                  const seconds = detectionSeconds(row);
                  return (
                    <tr key={row.id}>
                      <td><strong>{row.order_id}</strong></td>
                      <td className="console-cell-customer">{row.customer_name || "—"}</td>
                      <td>{row.payer_name || "—"}</td>
                      <td><strong>{formatInr(row.amount)}</strong></td>
                      <td>
                        <span className={`console-pill ${row.status === "paid" ? "is-paid" : "is-muted"}`}>
                          {row.status === "paid" ? "Success" : "Failed"}
                        </span>
                      </td>
                      <td>{row.status === "paid" ? (seconds === null ? "—" : `${seconds}s`) : "—"}</td>
                      <td>{formatTime(row.paid_at ?? row.created_at)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </ConsoleLayout>
  );
}
