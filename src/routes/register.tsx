import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { Eye, EyeOff } from "lucide-react";
import { useState, type FormEvent } from "react";
import { AuthShell } from "@/components/auth/AuthShell";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/register")({
  head: () => ({ meta: [
    { title: "Create account — Auto Upi" },
    { name: "description", content: "Create your Auto Upi merchant account and start managing UPI payments." },
    { property: "og:title", content: "Create account — Auto Upi" },
    { property: "og:description", content: "Register for a secure Auto Upi merchant workspace." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ]}),
  component: RegisterPage,
});

function RegisterPage() {
  const navigate = useNavigate();
  const [form, setForm] = useState({ name: "", mobile: "", email: "", password: "", confirm: "" });
  const [showPassword, setShowPassword] = useState(false);
  const [agreed, setAgreed] = useState(true);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [success, setSuccess] = useState(false);
  const update = (key: keyof typeof form, value: string) => setForm((current) => ({ ...current, [key]: value }));

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage("");
    if (form.password !== form.confirm) { setMessage("Passwords do not match."); return; }
    if (!agreed) { setMessage("Please accept the terms and privacy policy."); return; }
    setLoading(true);
    const { data, error } = await supabase.auth.signUp({
      email: form.email.trim(), password: form.password,
      options: { emailRedirectTo: `${window.location.origin}/auth`, data: { full_name: form.name.trim(), mobile: form.mobile.trim() } },
    });
    if (error) { setLoading(false); setMessage(error.message); return; }
    if (data.session && data.user) {
      await supabase.from("profiles").upsert({ id: data.user.id, full_name: form.name.trim(), mobile: form.mobile.trim(), updated_at: new Date().toISOString() });
      setLoading(false);
      await navigate({ to: "/dashboard", replace: true });
      return;
    }
    setLoading(false);
    setSuccess(true);
  }

  if (success) return <AuthShell><div className="auth-form auth-success"><span>ACCOUNT CREATED</span><h1>Check your email</h1><p>We sent a confirmation link to <strong>{form.email}</strong>. Confirm it, then sign in to continue.</p><Button asChild className="auth-submit"><Link to="/auth">GO TO LOGIN</Link></Button></div></AuthShell>;

  return (
    <AuthShell>
      <form className="auth-form auth-form-register" onSubmit={handleSubmit}>
        <div className="auth-form-heading"><span>JOIN AUTO UPI</span><h1>Register new account</h1><p>Create your secure merchant workspace.</p></div>
        <div className="auth-field-grid"><label className="auth-field">Name<Input value={form.name} onChange={(event) => update("name", event.target.value)} placeholder="Enter your name" autoComplete="name" required /></label><label className="auth-field">Mobile number<Input type="tel" value={form.mobile} onChange={(event) => update("mobile", event.target.value)} placeholder="Enter mobile number" autoComplete="tel" pattern="[0-9+ -]{8,15}" required /></label></div>
        <label className="auth-field">Email address<Input type="email" value={form.email} onChange={(event) => update("email", event.target.value)} placeholder="Enter email address" autoComplete="email" required /></label>
        <label className="auth-field">Password<span className="auth-password-wrap"><Input type={showPassword ? "text" : "password"} value={form.password} onChange={(event) => update("password", event.target.value)} placeholder="Create a strong password" autoComplete="new-password" minLength={8} required /><Button type="button" variant="ghost" size="icon" aria-label={showPassword ? "Hide password" : "Show password"} onClick={() => setShowPassword((value) => !value)}>{showPassword ? <EyeOff /> : <Eye />}</Button></span></label>
        <label className="auth-field">Confirm password<Input type="password" value={form.confirm} onChange={(event) => update("confirm", event.target.value)} placeholder="Enter password again" autoComplete="new-password" minLength={8} required /></label>
        <label className="auth-check"><Checkbox checked={agreed} onCheckedChange={(value) => setAgreed(value === true)} /> I agree to the Terms and Privacy Policy</label>
        {message && <p className="auth-message auth-error" role="alert">{message}</p>}
        <Button className="auth-submit" type="submit" disabled={loading}>{loading ? "Creating account…" : "REGISTER"}</Button>
        <p className="auth-login-link">Have an account? <Link to="/auth">Login</Link></p>
      </form>
    </AuthShell>
  );
}
