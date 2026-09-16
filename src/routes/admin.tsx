import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import type { User } from "@supabase/supabase-js";
import {
  Activity, IndianRupee, LayoutGrid, Lock, LogOut, QrCode, Search, ShieldCheck, Sparkles, Users, X,
} from "lucide-react";
import { BrandLogo } from "@/components/BrandLogo";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { supabaseAdminAuth as supabase } from "@/integrations/supabase/admin-client";
import { Swal } from "@/lib/swal";

/** The only account that can ever open this panel. Enforced again in the database. */
const ADMIN_EMAIL = "aminulislam78131@gmail.com";

export const Route = createFileRoute("/admin")({
  head: () => ({ meta: [
    { title: "autoupi | Admin" },
    { name: "description", content: "Private Auto Upi admin panel for managing users, plans and QR limits." },
    { property: "og:title", content: "autoupi | Admin" },
    { property: "og:description", content: "Private Auto Upi admin panel." },
    { name: "robots", content: "noindex, nofollow" },
  ]}),
  ssr: false,
  component: AdminPage,
});

type AdminUser = {
  user_id: string;
  email: string;
  created_at: string;
  full_name: string;
  mobile: string;
  plan: "free" | "pro";
  started_at: string | null;
  expires_at: string | null;
  qr_limit: number;
  qr_used: number;
  links_total: number;
  links_paid: number;
  revenue: number;
  connected_accounts: number;
};

type Overview = {
  users: number; pro_users: number; qr_codes: number; links: number;
  paid_links: number; revenue: number; subscription_revenue: number;
};

type PaymentLog = {
  id: string; order_id: string; slug: string; amount: number; payable_amount: number;
  status: "active" | "paid" | "expired"; customer_name: string; payer_name: string | null;
  clicks: number; created_at: string; paid_at: string | null; expires_at: string;
  user_id: string; merchant_name: string; merchant_email: string;
};

const inr = (n: number) => `₹${Number(n || 0).toLocaleString("en-IN", { maximumFractionDigits: 2 })}`;
const day = (value: string | null) =>
  value ? new Date(value).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" }) : "—";

const stamp = (value: string) =>
  new Date(value).toLocaleString("en-IN", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });

/** Skeleton placeholder rows shown while a table is loading. */
function SkeletonRows({ rows, cols }: { rows: number; cols: number }) {
  return (
    <>
      {Array.from({ length: rows }).map((_, r) => (
        <tr key={`skeleton-${r}`} className="admin-skel-row">
          {Array.from({ length: cols }).map((__, c) => (
            <td key={c}><span className="admin-skel" /></td>
          ))}
        </tr>
      ))}
    </>
  );
}


function AdminPage() {
  const [user, setUser] = useState<User | null>(null);
  const [checking, setChecking] = useState(true);

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setUser(data.session?.user ?? null);
      setChecking(false);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => setUser(session?.user ?? null));
    return () => sub.subscription.unsubscribe();
  }, []);

  const isAdmin = (user?.email ?? "").toLowerCase() === ADMIN_EMAIL;

  if (checking) return <div className="admin-gate"><span className="pay-spinner" /></div>;
  if (!isAdmin) return <AdminLogin signedIn={Boolean(user)} />;
  return <AdminConsole user={user as User} />;
}

function AdminLogin({ signedIn }: { signedIn: boolean }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    const mail = email.trim().toLowerCase();
    if (mail !== ADMIN_EMAIL) {
      setBusy(false);
      void Swal.fire({ icon: "error", title: "Access denied", text: "This account is not an admin.", confirmButtonText: "OK" });
      return;
    }
    let { error } = await supabase.auth.signInWithPassword({ email: mail, password });
    if (error) {
      // First ever admin sign-in: create the single admin account, then retry.
      const { error: signUpError } = await supabase.auth.signUp({ email: mail, password });
      if (!signUpError) ({ error } = await supabase.auth.signInWithPassword({ email: mail, password }));
    }
    setBusy(false);
    if (error) {
      void Swal.fire({ icon: "error", title: "Login failed", text: error.message, confirmButtonText: "OK" });
      return;
    }
    void Swal.fire({ icon: "success", title: "Welcome back, admin", timer: 1200, showConfirmButton: false });
  }

  return (
    <div className="admin-gate">
      <form className="admin-login page-enter" onSubmit={submit}>
        <div className="admin-login-brand"><BrandLogo /><strong>Auto Upi</strong><em>ADMIN</em></div>
        <h1><Lock /> Restricted area</h1>
        <p>{signedIn ? "You are signed in with a non-admin account. Sign in as the admin to continue." : "Sign in with the admin account to manage users and plans."}</p>
        <label className="console-field">Email
          <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="admin email" autoComplete="username" required />
        </label>
        <label className="console-field">Password
          <Input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="••••••••" autoComplete="current-password" required />
        </label>
        <Button type="submit" disabled={busy}>{busy ? "Checking…" : "Sign in"}</Button>
      </form>
    </div>
  );
}

const ADMIN_MENU = [
  { key: "overview", label: "Overview", icon: LayoutGrid },
  { key: "users", label: "Users", icon: Users },
  { key: "subscriptions", label: "Subscriptions", icon: Sparkles },
  { key: "logs", label: "Logs", icon: Activity },
] as const;

type Tab = (typeof ADMIN_MENU)[number]["key"];

function readTab(): Tab {
  if (typeof window === "undefined") return "overview";
  const value = new URLSearchParams(window.location.search).get("tab") as Tab | null;
  return ADMIN_MENU.some((m) => m.key === value) ? (value as Tab) : "overview";
}

function AdminConsole({ user }: { user: User }) {
  const [tab] = useState<Tab>(readTab);
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [editing, setEditing] = useState<AdminUser | null>(null);

  // Debounce typing so every keystroke does not hit the database.
  useEffect(() => {
    const id = window.setTimeout(() => setQuery(search.trim()), 300);
    return () => window.clearTimeout(id);
  }, [search]);

  const usersQuery = useQuery({
    queryKey: ["admin-users", tab, query],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("admin_list_users", {
        _search: query,
        _limit: tab === "overview" ? 6 : 200,
        _plan: tab === "subscriptions" ? "pro" : "",
      } as never);
      if (error) throw error;
      return (data as unknown as AdminUser[]) ?? [];
    },
    enabled: tab !== "logs",
    placeholderData: (previous) => previous,
    staleTime: 20000,
    refetchInterval: 30000,
  });

  const overviewQuery = useQuery({
    queryKey: ["admin-overview"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("admin_overview");
      if (error) throw error;
      return data as unknown as Overview;
    },
    enabled: tab === "overview",
    staleTime: 20000,
    refetchInterval: 30000,
  });

  const logsQuery = useQuery({
    queryKey: ["admin-logs", query],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("admin_payment_logs", { _search: query, _limit: 200 } as never);
      if (error) throw error;
      return (data as unknown as PaymentLog[]) ?? [];
    },
    enabled: tab === "logs",
    placeholderData: (previous) => previous,
    refetchInterval: 8000,
  });

  const filtered = useMemo(() => usersQuery.data ?? [], [usersQuery.data]);
  const usersLoading = usersQuery.isPending && tab !== "logs";
  const logsLoading = logsQuery.isPending && tab === "logs";


  async function signOut() {
    await supabase.auth.signOut();
    window.location.href = "/admin";
  }

  const stats = overviewQuery.data;

  return (
    <div className="console">
      <aside className="console-side">
        <div className="console-brand"><BrandLogo /><strong>Auto Upi</strong><em>ADMIN</em></div>
        <div className="console-side-scroll">
          <p className="console-side-label">ADMIN MENU</p>
          <nav className="console-menu">
            {ADMIN_MENU.map((item) => (
              <a
                key={item.key}
                className={`console-menu-item${tab === item.key ? " is-active" : ""}`}
                href={`/admin?tab=${item.key}`}
              >
                <item.icon /><span>{item.label}</span>
              </a>
            ))}
            <a className="console-menu-item" href="/dashboard"><QrCode /><span>Merchant view</span></a>
          </nav>
        </div>
        <div className="admin-side-foot">
          <span><ShieldCheck /> {user.email}</span>
          <Button size="sm" className="admin-signout" onClick={signOut}><LogOut /> Sign out</Button>
        </div>
      </aside>

      <div className="console-main">
        <header className="console-top page-enter page-enter-early">
          <h1>{ADMIN_MENU.find((m) => m.key === tab)?.label}</h1>
          <div className="console-top-right"><span className="console-live"><i />Live</span></div>
        </header>

        <main className="console-body">
          {tab === "overview" ? <ProPriceCard /> : null}
          {tab === "overview" ? <FreePlanCard /> : null}


          {tab === "overview" ? (
            <section className="admin-stat-grid">
              {[
                { label: "Total users", value: stats ? stats.users.toLocaleString("en-IN") : "—", icon: Users },
                { label: "Active Pro", value: stats ? stats.pro_users.toLocaleString("en-IN") : "—", icon: Sparkles },
                { label: "QR codes created", value: stats ? stats.qr_codes.toLocaleString("en-IN") : "—", icon: QrCode },
                { label: "Paid payments", value: stats ? stats.paid_links.toLocaleString("en-IN") : "—", icon: ShieldCheck },
                { label: "Collected volume", value: stats ? inr(stats.revenue) : "—", icon: IndianRupee },
                { label: "Subscription revenue", value: stats ? inr(stats.subscription_revenue) : "—", icon: IndianRupee },
              ].map((card, index) => (
                <article key={card.label} className={`console-card admin-stat reveal-delay-${(index % 4) + 1}`} data-reveal>
                  <card.icon />
                  <strong>{card.value}</strong>
                  <small>{card.label}</small>
                </article>
              ))}
            </section>
          ) : null}

          {tab === "logs" ? (
            <section className="console-card reveal-delay-1" data-reveal>
              <div className="console-card-head">
                <h3>Payment logs</h3>
                <div className="admin-search"><Search /><input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search order, merchant or customer" /></div>
              </div>
              <div className="console-table-wrap">
                <table className="console-table">
                  <thead>
                    <tr><th>ORDER ID</th><th>MERCHANT</th><th>CUSTOMER</th><th>AMOUNT</th><th>CHARGED</th><th>STATUS</th><th>CREATED</th><th>PAID AT</th></tr>
                  </thead>
                  <tbody>
                    {(logsQuery.data ?? []).map((log) => (
                      <tr key={log.id}>
                        <td><strong>{log.order_id}</strong></td>
                        <td>
                          <div className="admin-user-cell">
                            <strong>{log.merchant_name || log.merchant_email.split("@")[0]}</strong>
                            <small>{log.merchant_email}</small>
                          </div>
                        </td>
                        <td>{log.customer_name || log.payer_name || "—"}</td>
                        <td><strong>{inr(log.amount)}</strong></td>
                        <td>{inr(log.payable_amount)}</td>
                        <td>
                          <span className={`console-pill ${log.status === "paid" ? "is-paid" : log.status === "active" ? "is-active" : "is-muted"}`}>
                            {log.status === "paid" ? "Success" : log.status === "active" ? "Pending" : "Rejected"}
                          </span>
                        </td>
                        <td>{stamp(log.created_at)}</td>
                        <td>{log.paid_at ? stamp(log.paid_at) : "—"}</td>
                      </tr>
                    ))}
                    {logsLoading ? <SkeletonRows rows={6} cols={8} /> : null}
                    {!logsLoading && (logsQuery.data ?? []).length === 0 ? (
                      <tr><td colSpan={8}><div className="console-empty"><p>No payment activity yet</p></div></td></tr>
                    ) : null}

                  </tbody>
                </table>
              </div>
            </section>
          ) : (
          <section className="console-card reveal-delay-1" data-reveal>
            <div className="console-card-head">
              <h3>{tab === "subscriptions" ? "Active subscriptions" : tab === "overview" ? "Latest users" : "All users"}</h3>
              <div className="admin-search"><Search /><input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search email, name or mobile" /></div>
            </div>
            <div className="console-table-wrap">
              <table className="console-table">
                <thead>
                  <tr>
                    <th>User</th><th>Plan</th><th>QR used</th><th>Validity</th><th>Payments</th><th>Volume</th><th />
                  </tr>
                </thead>
                <tbody>
                  {(tab === "overview" ? filtered.slice(0, 6) : filtered).map((row) => (
                    <tr key={row.user_id}>
                      <td>
                        <div className="admin-user-cell">
                          <strong>{row.full_name || row.email.split("@")[0]}</strong>
                          <small>{row.mobile || "—"}</small>
                        </div>
                      </td>
                      <td><span className={`console-pill ${row.plan === "pro" ? "is-paid" : "is-muted"}`}>{row.plan.toUpperCase()}</span></td>
                      <td>{row.qr_used} / {row.qr_limit.toLocaleString("en-IN")}</td>
                      <td>{row.plan === "pro" ? day(row.expires_at) : "No expiry"}</td>
                      <td>{row.links_paid} / {row.links_total}</td>
                      <td>{inr(row.revenue)}</td>
                      <td><Button size="sm" variant="outline" onClick={() => setEditing(row)}>Manage</Button></td>
                    </tr>
                  ))}
                  {usersLoading ? <SkeletonRows rows={5} cols={7} /> : null}
                  {!usersLoading && filtered.length === 0 ? (
                    <tr><td colSpan={7}><div className="console-empty"><p>No users found</p></div></td></tr>
                  ) : null}

                </tbody>
              </table>
            </div>
          </section>
          )}
        </main>
      </div>

      {editing ? (
        <ManageUserDialog
          row={editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); void usersQuery.refetch(); void overviewQuery.refetch(); }}
        />
      ) : null}
    </div>
  );
}

function ManageUserDialog({ row, onClose, onSaved }: { row: AdminUser; onClose: () => void; onSaved: () => void }) {
  const [plan, setPlan] = useState<"free" | "pro">(row.plan);
  const [days, setDays] = useState(30);
  const [qrLimit, setQrLimit] = useState(String(row.qr_limit));
  const [amount, setAmount] = useState(String(row.plan === "pro" ? 299 : 0));
  const [resetUsage, setResetUsage] = useState(false);
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    const { error } = await supabase.rpc("admin_set_plan", {
      _user: row.user_id,
      _plan: plan,
      _days: Math.max(Number(days) || 30, 1),
      _qr_limit: Number(qrLimit) > 0 ? Math.floor(Number(qrLimit)) : null,
      _amount: Number(amount) || 0,
      _reset_usage: resetUsage,
    } as never);
    setBusy(false);
    if (error) {
      void Swal.fire({ icon: "error", title: "Could not update", text: error.message, confirmButtonText: "OK" });
      return;
    }
    void Swal.fire({ icon: "success", title: "Plan updated", timer: 1300, showConfirmButton: false });
    onSaved();
  }

  return (
    <div className="admin-modal-scrim" role="presentation" onClick={onClose}>
      <div className="admin-modal page-enter" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
        <header>
          <div>
            <h3>{row.full_name || row.email}</h3>
            <small>{row.email}</small>
          </div>
          <button type="button" aria-label="Close" onClick={onClose}><X /></button>
        </header>

        <div className="admin-modal-grid">
          <label className="console-field">Plan
            <select value={plan} onChange={(e) => setPlan(e.target.value as "free" | "pro")}>
              <option value="free">Free</option>
              <option value="pro">Pro</option>
            </select>
          </label>
          <label className="console-field">Validity (days)
            <Input type="number" min={1} value={days} onChange={(e) => setDays(Number(e.target.value))} disabled={plan === "free"} />
          </label>
          <label className="console-field">QR code limit
            <Input type="number" min={0} value={qrLimit} onChange={(e) => setQrLimit(e.target.value)} />
            <small>Leave 0 for the default limit (3 free / 3,000 pro).</small>
          </label>
          <label className="console-field">Paid amount (₹)
            <Input type="number" min={0} value={amount} onChange={(e) => setAmount(e.target.value)} disabled={plan === "free"} />
          </label>
        </div>

        <label className="admin-check">
          <input type="checkbox" checked={resetUsage} onChange={(e) => setResetUsage(e.target.checked)} />
          Reset this user's QR usage counter to zero
        </label>

        <div className="admin-modal-meta">
          <span>QR used: <strong>{row.qr_used}</strong></span>
          <span>Current limit: <strong>{row.qr_limit.toLocaleString("en-IN")}</strong></span>
          <span>Expires: <strong>{day(row.expires_at)}</strong></span>
        </div>

        <footer>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button onClick={save} disabled={busy}>{busy ? "Saving…" : "Save changes"}</Button>
        </footer>
      </div>
    </div>
  );
}

/** Free plan on/off switch. When off, only paid Pro accounts can work. */
function FreePlanCard() {
  const stateQuery = useQuery({
    queryKey: ["admin-free-plan"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("is_free_plan_enabled" as never);
      if (error) throw error;
      return Boolean(data);
    },
    refetchInterval: 15000,
  });
  const [busy, setBusy] = useState(false);
  const enabled = stateQuery.data ?? true;

  async function toggle(next: boolean) {
    setBusy(true);
    const { error } = await supabase.rpc("admin_set_free_plan_enabled" as never, { _enabled: next } as never);
    setBusy(false);
    if (error) {
      void Swal.fire({ icon: "error", title: "Could not update", text: error.message, confirmButtonText: "OK" });
      return;
    }
    await stateQuery.refetch();
    void Swal.fire({
      icon: "success",
      title: next ? "Free plan enabled" : "Free plan disabled",
      text: next ? "Free users get 3 QR codes again." : "Only paid Pro users can create QR codes now.",
      timer: 1600,
      showConfirmButton: false,
    });
  }

  return (
    <section className="console-card admin-price-card reveal-delay-1" data-reveal>
      <div className="console-card-head">
        <h3>Free plan</h3>
        <span className="console-live"><i />{enabled ? "Enabled" : "Disabled"}</span>
      </div>
      <div className="admin-price-row">
        <label className="admin-check">
          <input
            type="checkbox"
            checked={enabled}
            disabled={busy || stateQuery.isPending}
            onChange={(e) => void toggle(e.target.checked)}
          />
          Allow the free plan (3 QR codes)
        </label>
      </div>
      <small>Turn this off to make Auto Upi paid-only — free accounts cannot create any QR code until they upgrade.</small>
    </section>
  );
}

/** Live Pro plan price control. Saving updates the price everywhere instantly. */
function ProPriceCard() {

  const priceQuery = useQuery({
    queryKey: ["admin-pro-price"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("get_pro_price" as never);
      if (error) throw error;
      return Number(data ?? 299);
    },
    refetchInterval: 15000,
  });
  const [value, setValue] = useState("");
  const [busy, setBusy] = useState(false);
  const current = priceQuery.data ?? 299;

  useEffect(() => {
    if (priceQuery.data != null) setValue(String(priceQuery.data));
  }, [priceQuery.data]);

  async function save() {
    const price = Number(value);
    if (!Number.isFinite(price) || price < 1) {
      void Swal.fire({ icon: "error", title: "Enter a valid price", confirmButtonText: "OK" });
      return;
    }
    setBusy(true);
    const { error } = await supabase.rpc("admin_set_pro_price" as never, { _price: price } as never);
    setBusy(false);
    if (error) {
      void Swal.fire({ icon: "error", title: "Could not update price", text: error.message, confirmButtonText: "OK" });
      return;
    }
    await priceQuery.refetch();
    void Swal.fire({ icon: "success", title: `Pro price set to ₹${price}`, timer: 1300, showConfirmButton: false });
  }

  return (
    <section className="console-card admin-price-card reveal-delay-1" data-reveal>
      <div className="console-card-head">
        <h3>Pro plan price</h3>
        <span className="console-live"><i />Live · {inr(current)}</span>
      </div>
      <div className="admin-price-row">
        <label className="console-field">Price (₹ per 30 days)
          <Input type="number" min={1} value={value} onChange={(e) => setValue(e.target.value)} />
        </label>
        <Button onClick={() => void save()} disabled={busy}>{busy ? "Saving…" : "Update price"}</Button>
      </div>
      <small>New price applies instantly on the landing page, Plan page and every upgrade payment.</small>
    </section>
  );
}
