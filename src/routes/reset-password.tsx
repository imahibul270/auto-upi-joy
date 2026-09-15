import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useState, type FormEvent } from "react";
import { AuthShell } from "@/components/auth/AuthShell";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/reset-password")({
  head: () => ({ meta: [
    { title: "Choose new password — Auto Upi" },
    { name: "description", content: "Choose a new password for your Auto Upi account." },
    { property: "og:title", content: "Choose new password — Auto Upi" },
    { property: "og:description", content: "Securely update your Auto Upi account password." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ]}), component: ResetPasswordPage,
});

function ResetPasswordPage() {
  const navigate = useNavigate();
  const [password, setPassword] = useState(""); const [confirm, setConfirm] = useState("");
  const [message, setMessage] = useState(""); const [loading, setLoading] = useState(false);
  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setMessage("");
    if (password !== confirm) { setMessage("Passwords do not match."); return; }
    setLoading(true); const { error } = await supabase.auth.updateUser({ password }); setLoading(false);
    if (error) { setMessage(error.message); return; }
    await navigate({ to: "/dashboard", replace: true });
  }
  return <AuthShell><form className="auth-form" onSubmit={handleSubmit}><div className="auth-form-heading"><span>SECURE YOUR ACCOUNT</span><h1>Choose a new password</h1><p>Use at least eight characters for your new password.</p></div><label className="auth-field">New password<Input type="password" value={password} onChange={(event) => setPassword(event.target.value)} minLength={8} autoComplete="new-password" placeholder="Enter new password" required /></label><label className="auth-field">Confirm password<Input type="password" value={confirm} onChange={(event) => setConfirm(event.target.value)} minLength={8} autoComplete="new-password" placeholder="Enter password again" required /></label>{message && <p className="auth-message auth-error" role="alert">{message}</p>}<Button className="auth-submit" type="submit" disabled={loading}>{loading ? "Updating…" : "UPDATE PASSWORD"}</Button><p className="auth-login-link"><Link to="/auth">Back to login</Link></p></form></AuthShell>;
}
