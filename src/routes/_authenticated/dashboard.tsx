import { createFileRoute } from "@tanstack/react-router";
import {
  Activity, BadgeIndianRupee, CreditCard, Receipt, ShieldCheck, ShoppingBag, TrendingDown, TrendingUp,
} from "lucide-react";
import { useMemo, useState } from "react";
import {
  Area, AreaChart, CartesianGrid, Cell, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from "recharts";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";
import {
  formatInr, formatTime, usePaymentDetection, usePaymentLinks, type PaymentLinkRow,
} from "@/lib/gateway";

export const Route = createFileRoute("/_authenticated/dashboard")({
  head: () => ({ meta: [
    { title: "Dashboard — Auto Upi" },
    { name: "description", content: "Track revenue, orders, success rate and payment analytics inside your Auto Upi merchant workspace." },
    { property: "og:title", content: "Dashboard — Auto Upi" },
    { property: "og:description", content: "Your secure Auto Upi merchant workspace with live payment analytics." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ]}),
  component: DashboardPage,
});

const RANGES = ["Today", "Last 7 Days", "Last 30 Days"] as const;
const RANGE_DAYS: Record<(typeof RANGES)[number], number> = {
  Today: 1, "Last 7 Days": 7, "Last 30 Days": 30,
};
const METHOD_COLORS = ["oklch(0.72 0.19 128)", "oklch(0.46 0.14 164)", "oklch(0.8 0.12 88)"];

function rangeStart(range: (typeof RANGES)[number]) {
  const now = new Date();
  if (range === "Today") {
    const start = new Date(now);
    start.setHours(0, 0, 0, 0);
    return start;
  }
  return new Date(now.getTime() - (RANGE_DAYS[range] - 1) * 86400000);
}

function buildSeries(rows: PaymentLinkRow[], range: (typeof RANGES)[number]) {
  const days = RANGE_DAYS[range];
  return Array.from({ length: days }, (_, index) => {
    const day = new Date(Date.now() - (days - 1 - index) * 86400000);
    const key = day.toDateString();
    const slot = rows.filter((row) => row.status === "paid" && new Date(row.paid_at ?? row.created_at).toDateString() === key);
    return {
      day: day.toLocaleDateString("en-IN", { day: "2-digit", month: "short" }),
      revenue: slot.reduce((s, r) => s + Number(r.payable_amount), 0),
      orders: slot.length,
    };
  });
}

function DashboardPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);
  usePaymentDetection();
  const { data: links = [] } = usePaymentLinks();
  const [range, setRange] = useState<(typeof RANGES)[number]>("Today");

  const rows = useMemo(() => {
    const start = rangeStart(range).getTime();
    return links.filter((row) => Date.parse(row.paid_at ?? row.created_at) >= start);
  }, [links, range]);

  const chartData = useMemo(() => buildSeries(rows, range), [rows, range]);

  const paid = rows.filter((row) => row.status === "paid");
  const active = rows.filter((row) => row.status === "active");
  const failed = rows.filter((row) => row.status === "expired");
  const revenue = paid.reduce((sum, row) => sum + Number(row.payable_amount), 0);
  const settled = paid.length + failed.length;
  const successRate = settled === 0 ? 0 : Math.round((paid.length / settled) * 100);

  const methods = [
    { name: "UPI", value: paid.length ? 100 : 0 },
    { name: "Cards", value: 0 },
    { name: "Netbanking", value: 0 },
  ];
  const hasMethodData = methods.some((m) => m.value > 0);

  const recent = [...links]
    .filter((row) => row.status !== "active")
    .sort((a, b) => Date.parse(b.paid_at ?? b.created_at) - Date.parse(a.paid_at ?? a.created_at))
    .slice(0, 4);

  const stats = [
    { label: "Total Revenue", value: formatInr(revenue), icon: BadgeIndianRupee, tone: "lime",
      trend: `${paid.length} successful payments`, trendIcon: TrendingUp, trendTone: "up" },
    { label: "Total Orders", value: String(rows.length), icon: ShoppingBag, tone: "blue",
      trend: `${active.length} still awaiting payment`, trendIcon: TrendingUp, trendTone: "up" },
    { label: "Success Rate", value: `${successRate}%`, icon: ShieldCheck, tone: "mint",
      trend: settled ? "Based on settled links" : "No settled links yet", trendIcon: TrendingUp, trendTone: "up" },
    { label: "Pending / Failed", value: `${active.length} / ${failed.length}`, icon: Activity, tone: "amber",
      trend: active.length ? "Waiting for payment" : "Nothing pending", trendIcon: TrendingDown, trendTone: "down" },
  ];

  return (
    <ConsoleLayout title="Dashboard" user={user} userName={name}>
      <section className="console-welcome" data-reveal>
        <div>
          <h2>Welcome Back, {name}!</h2>
          <p>Here&apos;s what&apos;s happening with your payments.</p>
        </div>
        <div className="console-range">
          {RANGES.map((r) => (
            <button key={r} type="button" className={range === r ? "is-active" : ""} onClick={() => setRange(r)}>{r}</button>
          ))}
        </div>
      </section>

      <section className="console-stats">
        {stats.map((s, i) => (
          <article key={s.label} className={`console-stat reveal-delay-${i + 1}`} data-reveal>
            <div className="console-stat-head">
              <span>{s.label}</span>
              <i className={`console-stat-icon tone-${s.tone}`}><s.icon /></i>
            </div>
            <strong>{s.value}</strong>
            <p className={`console-trend trend-${s.trendTone}`}><s.trendIcon />{s.trend}</p>
          </article>
        ))}
      </section>

      <section className="console-analytics">
        <article className="console-card reveal-delay-1" data-reveal>
          <div className="console-card-head">
            <h3>Transaction &amp; Revenue Analytics</h3>
            <small>{range}</small>
          </div>
          <div className="console-chart">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={chartData} margin={{ top: 10, right: 8, left: -18, bottom: 0 }}>
                <defs>
                  <linearGradient id="revFill" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="oklch(0.72 0.19 128)" stopOpacity={0.45} />
                    <stop offset="100%" stopColor="oklch(0.72 0.19 128)" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="4 6" stroke="var(--border)" vertical={false} />
                <XAxis dataKey="day" tickLine={false} axisLine={false} fontSize={11} stroke="var(--muted-foreground)" />
                <YAxis tickLine={false} axisLine={false} fontSize={11} stroke="var(--muted-foreground)" allowDecimals />
                <Tooltip contentStyle={{ borderRadius: 10, border: "1px solid var(--border)", fontSize: 12 }} />
                <Area type="monotone" dataKey="revenue" stroke="oklch(0.58 0.16 128)" strokeWidth={2.4} fill="url(#revFill)" dot={{ r: 3 }} animationDuration={1100} />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </article>

        <article className="console-card reveal-delay-2" data-reveal>
          <div className="console-card-head">
            <h3>Payment Methods</h3>
          </div>
          {hasMethodData ? (
            <div className="console-chart console-chart-sm">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie data={methods} dataKey="value" nameKey="name" innerRadius="58%" outerRadius="85%" paddingAngle={3} animationDuration={1100}>
                    {methods.map((m, i) => <Cell key={m.name} fill={METHOD_COLORS[i]} />)}
                  </Pie>
                  <Tooltip contentStyle={{ borderRadius: 10, border: "1px solid var(--border)", fontSize: 12 }} />
                </PieChart>
              </ResponsiveContainer>
            </div>
          ) : (
            <div className="console-empty">
              <CreditCard />
              <p>No payments yet</p>
              <small>Method split will appear after your first transaction.</small>
            </div>
          )}
          <ul className="console-legend">
            {methods.map((m, i) => (
              <li key={m.name}><i style={{ background: METHOD_COLORS[i] }} />{m.name}<span>{m.value}%</span></li>
            ))}
          </ul>
        </article>
      </section>

      <section className="console-card console-recent" data-reveal>
        <div className="console-card-head">
          <h3>Recent Transactions</h3>
          <small>Latest activity on your account</small>
        </div>
        {recent.length === 0 ? (
          <div className="console-empty console-empty-row">
            <Receipt />
            <p>No transactions yet</p>
            <small>Share a payment link to receive your first payment.</small>
          </div>
        ) : (
          <div className="console-table-wrap">
            <table className="console-table">
              <thead>
                <tr><th>ORDER ID</th><th>CUSTOMER</th><th>AMOUNT</th><th>STATUS</th><th>TIME</th></tr>
              </thead>
              <tbody>
                {recent.map((row) => (
                  <tr key={row.id}>
                    <td><strong>{row.order_id}</strong></td>
                    <td className="console-cell-customer">{row.payer_name || row.customer_name || "—"}</td>
                    <td><strong>{formatInr(row.payable_amount)}</strong></td>
                    <td>
                      <span className={`console-pill ${row.status === "paid" ? "is-paid" : "is-muted"}`}>
                        {row.status === "paid" ? "Success" : "Failed"}
                      </span>
                    </td>
                    <td>{formatTime(row.paid_at ?? row.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </ConsoleLayout>
  );
}
