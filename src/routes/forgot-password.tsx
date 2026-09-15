import { createFileRoute, Link } from "@tanstack/react-router";
import { useState, type FormEvent } from "react";
import { AuthShell } from "@/components/auth/AuthShell";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { supabase } from "@/integrations/supabase/client";
import { Swal } from "@/lib/swal";

export const Route = createFileRoute("/forgot-password")({
  head: () => ({ meta: [
    { title: "Reset password — Auto Upi" },
    { name: "description", content: "Request a secure password reset link for your Auto Upi account." },
    { property: "og:title", content: "Reset password — Auto Upi" },
    { property: "og:description", content: "Recover access to your Auto Upi account." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ]}), component: ForgotPasswordPage,
});

function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(false);
  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setLoading(true); setMessage("");
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: `${window.location.origin}/reset-password` });
    setLoading(false);
    setMessage(error ? error.message : "Reset link sent. Please check your email.");
    if (error) {
      void Swal.fire({ icon: "error", title: "Could not send reset link", text: error.message });
    } else {
      void Swal.fire({ icon: "success", title: "Reset link sent", text: "Please check your email.", draggable: true });
    }
  }
  return <AuthShell><form className="auth-form" onSubmit={handleSubmit}><div className="auth-form-heading"><span>ACCOUNT RECOVERY</span><h1>Forgot your password?</h1><p>Enter your email and we’ll send a secure reset link.</p></div><label className="auth-field">Email address<Input type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="Enter email address" required /></label>{message && <p className="auth-message" role="status">{message}</p>}<Button className="auth-submit" type="submit" disabled={loading}>{loading ? "Sending…" : "SEND RESET LINK"}</Button><p className="auth-login-link"><Link to="/auth">Back to login</Link></p></form></AuthShell>;
}
