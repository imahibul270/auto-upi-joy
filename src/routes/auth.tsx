import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { Eye, EyeOff } from "lucide-react";
import { useState, type FormEvent } from "react";
import { AuthShell } from "@/components/auth/AuthShell";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/auth")({
  head: () => ({ meta: [
    { title: "Sign in — Auto Upi" },
    { name: "description", content: "Sign in securely to your Auto Upi merchant account." },
    { property: "og:title", content: "Sign in — Auto Upi" },
    { property: "og:description", content: "Access your Auto Upi merchant workspace." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ]}),
  component: SignInPage,
});

function SignInPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [remember, setRemember] = useState(true);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setMessage("");
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    setLoading(false);
    if (error) { setMessage(error.message); return; }
    await navigate({ to: "/dashboard", replace: true });
  }

  return (
    <AuthShell>
      <form className="auth-form" onSubmit={handleSubmit}>
        <div className="auth-form-heading"><span>WELCOME BACK</span><h1>Sign in to your account</h1><p>Manage payments, links and merchant activity.</p></div>
        <label className="auth-field">Email address<Input type="email" autoComplete="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="Enter email address" required /></label>
        <label className="auth-field">Password
          <span className="auth-password-wrap"><Input type={showPassword ? "text" : "password"} autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Enter your password" required /><Button type="button" variant="ghost" size="icon" aria-label={showPassword ? "Hide password" : "Show password"} onClick={() => setShowPassword((value) => !value)}>{showPassword ? <EyeOff /> : <Eye />}</Button></span>
        </label>
        <div className="auth-form-row"><label className="auth-check"><Checkbox checked={remember} onCheckedChange={(value) => setRemember(value === true)} /> Keep me logged in</label><Link to="/forgot-password">Forgot password?</Link></div>
        {message && <p className="auth-message auth-error" role="alert">{message}</p>}
        <Button className="auth-submit" type="submit" disabled={loading}>{loading ? "Signing in…" : "LOGIN"}</Button>
        <div className="auth-switch"><span>New to Auto Upi?</span><Button asChild variant="secondary"><Link to="/register">CREATE NEW ACCOUNT</Link></Button></div>
      </form>
    </AuthShell>
  );
}
