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

const SERIES: Record<string, { day: string; revenue: number; orders: number }[]> = {
  Today: [
    { day: "12 AM", revenue: 0, orders: 0 }, { day: "4 AM", revenue: 0, orders: 0 },
    { day: "8 AM", revenue: 0, orders: 0 }, { day: "12 PM", revenue: 0, orders: 0 },
    { day: "4 PM", revenue: 0, orders: 0 }, { day: "8 PM", revenue: 0, orders: 0 },
  ],
  "Last 7 Days": [
    { day: "Mon", revenue: 0, orders: 0 }, { day: "Tue", revenue: 0, orders: 0 },
    { day: "Wed", revenue: 0, orders: 0 }, { day: "Thu", revenue: 0, orders: 0 },
    { day: "Fri", revenue: 0, orders: 0 }, { day: "Sat", revenue: 0, orders: 0 },
    { day: "Sun", revenue: 0, orders: 0 },
  ],
  "Last 30 Days": [
    { day: "W1", revenue: 0, orders: 0 }, { day: "W2", revenue: 0, orders: 0 },
    { day: "W3", revenue: 0, orders: 0 }, { day: "W4", revenue: 0, orders: 0 },
  ],
};

const METHODS = [
  { name: "UPI", value: 0 }, { name: "Cards", value: 0 }, { name: "Netbanking", value: 0 },
];
const METHOD_COLORS = ["oklch(0.72 0.19 128)", "oklch(0.46 0.14 164)", "oklch(0.8 0.12 88)"];

function DashboardPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);
  const [range, setRange] = useState<(typeof RANGES)[number]>("Today");
  const chartData = useMemo(() => SERIES[range] ?? SERIES["Today"] ?? [], [range]);
  const hasMethodData = METHODS.some((m) => m.value > 0);

  const stats = [
    { label: "Total Revenue", value: "₹0.00", icon: BadgeIndianRupee, tone: "lime",
      trend: "+12.5% vs last period", trendIcon: TrendingUp, trendTone: "up" },
    { label: "Total Orders", value: "0", icon: ShoppingBag, tone: "blue",
      trend: "+8.2% vs last period", trendIcon: TrendingUp, trendTone: "up" },
    { label: "Success Rate", value: "0%", icon: ShieldCheck, tone: "mint",
      trend: "Healthy status", trendIcon: TrendingUp, trendTone: "up" },
    { label: "Pending / Failed", value: "0 / 0", icon: Activity, tone: "amber",
      trend: "Actions required", trendIcon: TrendingDown, trendTone: "down" },
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
                <Area type="monotone" dataKey="revenue" stroke="oklch(0.58 0.16 128)" strokeWidth={2.4} fill="url(#revFill)" animationDuration={1100} />
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
                  <Pie data={METHODS} dataKey="value" nameKey="name" innerRadius="58%" outerRadius="85%" paddingAngle={3} animationDuration={1100}>
                    {METHODS.map((m, i) => <Cell key={m.name} fill={METHOD_COLORS[i]} />)}
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
            {METHODS.map((m, i) => (
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
        <div className="console-empty console-empty-row">
          <Receipt />
          <p>No transactions yet</p>
          <small>Share a payment link to receive your first payment.</small>
        </div>
      </section>
    </ConsoleLayout>
  );
}
