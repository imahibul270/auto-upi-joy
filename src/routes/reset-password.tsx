import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState, type FormEvent } from "react";
import { AuthShell } from "@/components/auth/AuthShell";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { supabase } from "@/integrations/supabase/client";
import { Swal } from "@/lib/swal";

export const Route = createFileRoute("/reset-password")({
  head: () => ({ meta: [
    { title: "autoupi | Choose new password" },
    { name: "description", content: "Choose a new password for your Auto Upi account." },
    { property: "og:title", content: "autoupi | Choose new password" },
    { property: "og:description", content: "Securely update your Auto Upi account password." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ]}), component: ResetPasswordPage,
});

function ResetPasswordPage() {
  const navigate = useNavigate();
  const [password, setPassword] = useState(""); const [confirm, setConfirm] = useState("");
  const [message, setMessage] = useState(""); const [loading, setLoading] = useState(false);
  const [recoveryReady, setRecoveryReady] = useState(false);
  useEffect(() => {
    const hashIsRecovery = new URLSearchParams(window.location.hash.slice(1)).get("type") === "recovery";
    void supabase.auth.getSession().then(({ data }) => setRecoveryReady(hashIsRecovery || Boolean(data.session)));
    const { data } = supabase.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY") setRecoveryReady(true);
    });
    return () => data.subscription.unsubscribe();
  }, []);
  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setMessage("");
    if (password !== confirm) {
      setMessage("Passwords do not match.");
      void Swal.fire({ icon: "error", title: "Passwords do not match", text: "Please enter the same password in both fields." });
      return;
    }
    setLoading(true); const { error } = await supabase.auth.updateUser({ password }); setLoading(false);
    if (error) {
      setMessage(error.message);
      void Swal.fire({ icon: "error", title: "Could not update password", text: error.message });
      return;
    }
    await Swal.fire({ icon: "success", title: "Password updated", text: "Your password has been changed successfully.", draggable: true });
    await navigate({ to: "/dashboard", replace: true });
  }
  if (!recoveryReady) return <AuthShell><div className="auth-form auth-success"><span>RESET LINK REQUIRED</span><h1>Open your recovery email</h1><p>Please use the secure link from your password reset email to choose a new password.</p><Button asChild className="auth-submit"><Link to="/forgot-password">REQUEST A NEW LINK</Link></Button></div></AuthShell>;
  return <AuthShell><form className="auth-form" onSubmit={handleSubmit}><div className="auth-form-heading"><span>SECURE YOUR ACCOUNT</span><h1>Choose a new password</h1><p>Use at least eight characters for your new password.</p></div><label className="auth-field">New password<Input type="password" value={password} onChange={(event) => setPassword(event.target.value)} minLength={8} autoComplete="new-password" placeholder="Enter new password" required /></label><label className="auth-field">Confirm password<Input type="password" value={confirm} onChange={(event) => setConfirm(event.target.value)} minLength={8} autoComplete="new-password" placeholder="Enter password again" required /></label>{message && <p className="auth-message auth-error" role="alert">{message}</p>}<Button className="auth-submit" type="submit" disabled={loading}>{loading ? "Updating…" : "UPDATE PASSWORD"}</Button><p className="auth-login-link"><Link to="/auth">Back to login</Link></p></form></AuthShell>;
}
