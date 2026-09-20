import { useRouterState } from "@tanstack/react-router";
import { BrandLogo } from "@/components/BrandLogo";
import {
  ArrowLeftRight, BookOpen, CreditCard, KeyRound, LayoutGrid, LifeBuoy, Link2, Menu, Sparkles, X,
} from "lucide-react";
import { NotificationBell } from "@/components/console/NotificationBell";
import { useState, type ReactNode } from "react";
import { useQueryClient } from "@tanstack/react-query";
import type { User } from "@supabase/supabase-js";
import { Button } from "@/components/ui/button";
import { ProfileSettings } from "@/components/console/ProfileSettings";
import { supabase } from "@/integrations/supabase/client";
import { planTimeLeft, useQrQuota } from "@/lib/quota";
import { VerifyEmailGate } from "@/components/console/VerifyEmailGate";

export const CONSOLE_MENU = [
  { label: "Dashboard", href: "/dashboard", icon: LayoutGrid },
  { label: "Transactions", href: "/transactions", icon: ArrowLeftRight },
  { label: "Payment Links", href: "/payment-links", icon: Link2 },
  { label: "Connect Accounts", href: "/connect-accounts", icon: CreditCard },
  { label: "Plan", href: "/plan", icon: Sparkles },
  { label: "API Keys", href: "/api-keys", icon: KeyRound },
  { label: "Support", href: "/support", icon: LifeBuoy },
  { label: "Docs", href: "/docs", icon: BookOpen },
];

export function ConsoleLayout({
  title,
  user,
  userName,
  children,
}: {
  title: string;
  user: User;
  userName: string;
  children: ReactNode;
}) {
  const queryClient = useQueryClient();
  const [menuOpen, setMenuOpen] = useState(false);
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  async function signOut() {
    await queryClient.cancelQueries();
    queryClient.clear();
    await supabase.auth.signOut();
    window.location.href = "/auth";
  }

  return (
    <div className="console">
      <aside className={`console-side${menuOpen ? " side-open" : ""}`}>
        <div className="console-brand">
          <BrandLogo />
          <strong>Auto Upi</strong>
          <em>V2</em>
        </div>
        <div className="console-side-scroll">
          <p className="console-side-label">MAIN MENU</p>
          <nav className="console-menu">
            {CONSOLE_MENU.map((item) => (
              <a
                key={item.label}
                href={item.href}
                className={`console-menu-item${pathname === item.href ? " is-active" : ""}`}
              >
                <item.icon />
                <span>{item.label}</span>
              </a>
            ))}
          </nav>
          <SidePlanChip />
        </div>
        <ProfileSettings user={user} userName={userName} onSignOut={signOut} />
      </aside>

      {menuOpen ? (
        <button type="button" className="console-scrim" aria-label="Close menu" onClick={() => setMenuOpen(false)} />
      ) : null}

      <div className="console-main">
        <header className="console-top page-enter page-enter-early">
          <button type="button" className="console-burger" aria-label="Toggle menu" onClick={() => setMenuOpen((v) => !v)}>
            {menuOpen ? <X /> : <Menu />}
          </button>
          <h1>{title}</h1>
          <div className="console-top-right">
            <span className="console-live"><i />Live</span>
            <NotificationBell user={user} />
          </div>
        </header>
        <main className="console-body">{children}</main>
      </div>
    </div>
  );
}

/** Live plan badge: always shows the plan the user is on right now. */
function SidePlanChip() {
  const { data: quota } = useQrQuota();
  if (!quota) return null;
  const isPro = quota.plan === "pro";
  const left = planTimeLeft(quota);
  return (
    <a href="/plan" className={`console-plan-chip${isPro ? " is-pro" : ""}`}>
      <span className="console-plan-chip-top">
        <Sparkles />
        <strong>{isPro ? "Pro plan" : "Free plan"}</strong>
        <em>Current</em>
      </span>
      <span className="console-plan-chip-meta">
        {quota.remaining.toLocaleString("en-IN")} of {quota.limit.toLocaleString("en-IN")} QR left
        {isPro ? ` · ${left.label}` : " · no expiry"}
      </span>
    </a>
  );
}
