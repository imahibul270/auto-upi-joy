import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { CreditCard, Link2, LogOut, UserRound } from "lucide-react";
import { useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/_authenticated/dashboard")({
  head: () => ({ meta: [
    { title: "Dashboard — Auto Upi" },
    { name: "description", content: "View your Auto Upi merchant account and payment workspace." },
    { property: "og:title", content: "Dashboard — Auto Upi" },
    { property: "og:description", content: "Your secure Auto Upi merchant workspace." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ]}), component: DashboardPage,
});

function DashboardPage() {
  const { user } = Route.useRouteContext();
  const navigate = useNavigate(); const queryClient = useQueryClient();
  const [name, setName] = useState(user.user_metadata?.full_name as string || "Merchant");
  useEffect(() => {
    const syncProfile = async () => {
      const fullName = (user.user_metadata?.full_name as string | undefined) ?? "";
      const mobile = (user.user_metadata?.mobile as string | undefined) ?? "";
      const { data } = await supabase.from("profiles").select("full_name").eq("id", user.id).maybeSingle();
      if (!data) await supabase.from("profiles").insert({ id: user.id, full_name: fullName, mobile });
      else if (data.full_name) setName(data.full_name);
    };
    void syncProfile();
  }, [user]);
  async function signOut() { await queryClient.cancelQueries(); queryClient.clear(); await supabase.auth.signOut(); await navigate({ to: "/auth", replace: true }); }
  return <main className="account-page"><header className="account-header"><a href="/" className="account-logo">Auto Upi</a><Button variant="outline" onClick={signOut}><LogOut /> Sign out</Button></header><section className="account-content"><div className="account-welcome"><span><UserRound /></span><div><p>WELCOME BACK</p><h1>{name}</h1><small>{user.email}</small></div></div><div className="account-grid"><article><CreditCard /><h2>Payments</h2><p>Your payment activity will appear here.</p></article><article><Link2 /><h2>Payment links</h2><p>Create and manage your checkout links.</p></article></div></section></main>;
}
