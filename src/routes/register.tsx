import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { Eye, EyeOff, MailCheck } from "lucide-react";
import { useState, type FormEvent } from "react";
import { AuthShell } from "@/components/auth/AuthShell";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { supabase } from "@/integrations/supabase/client";
import { sendSignupOtp, verifySignupOtp } from "@/lib/signup-otp.functions";
import { Swal } from "@/lib/swal";

export const Route = createFileRoute("/register")({
  head: () => ({ meta: [
    { title: "autoupi | Create account" },
    { name: "description", content: "Create your Auto Upi merchant account and start managing UPI payments." },
    { property: "og:title", content: "autoupi | Create account" },
    { property: "og:description", content: "Register for a secure Auto Upi merchant workspace." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ]}),
  component: RegisterPage,
});

const message = (error: unknown) => (error instanceof Error ? error.message : "Something went wrong. Please try again.");

function RegisterPage() {
  const navigate = useNavigate();
  const [form, setForm] = useState({ name: "", mobile: "", email: "", password: "", confirm: "" });
  const [showPassword, setShowPassword] = useState(false);
  const [agreed, setAgreed] = useState(true);
  const [loading, setLoading] = useState(false);
  const [note, setNote] = useState("");
  const [step, setStep] = useState<"details" | "otp">("details");
  const [code, setCode] = useState("");
  const [verifying, setVerifying] = useState(false);
  const [resending, setResending] = useState(false);
  const update = (key: keyof typeof form, value: string) => setForm((current) => ({ ...current, [key]: value }));

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setNote("");
    if (form.password !== form.confirm) {
      setNote("Passwords do not match.");
      void Swal.fire({ icon: "error", title: "Passwords do not match", text: "Please enter the same password in both fields." });
      return;
    }
    if (!agreed) {
      setNote("Please accept the terms and privacy policy.");
      void Swal.fire({ icon: "warning", title: "Terms not accepted", text: "Please accept the terms and privacy policy to continue." });
      return;
    }
    setLoading(true);
    try {
      await sendSignupOtp({ data: { email: form.email.trim() } });
      setStep("otp");
      setCode("");
    } catch (error) {
      setNote(message(error));
      void Swal.fire({ icon: "error", title: "Could not send code", text: message(error) });
    } finally {
      setLoading(false);
    }
  }

  async function resend() {
    setResending(true);
    try {
      await sendSignupOtp({ data: { email: form.email.trim() } });
      void Swal.fire({ icon: "success", title: "New code sent", timer: 1400, showConfirmButton: false });
    } catch (error) {
      void Swal.fire({ icon: "error", title: "Could not send code", text: message(error) });
    } finally {
      setResending(false);
    }
  }

  async function verify(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (verifying) return;
    setNote("");
    setVerifying(true);
    // Always show the verifying spinner for a moment before the result.
    const hold = new Promise((resolve) => window.setTimeout(resolve, 2000));
    try {
      const task = verifySignupOtp({
        data: {
          email: form.email.trim(),
          code: code.trim(),
          password: form.password,
          name: form.name.trim(),
          mobile: form.mobile.trim(),
        },
      });
      const [result] = await Promise.all([task, hold]);
      void result;
      const { error } = await supabase.auth.signInWithPassword({ email: form.email.trim(), password: form.password });
      setVerifying(false);
      await Swal.fire({ icon: "success", title: "Email verified", text: "Your Auto Upi account is ready.", timer: 1600, showConfirmButton: false });
      if (error) {
        await navigate({ to: "/auth", replace: true });
        return;
      }
      await navigate({ to: "/dashboard", replace: true });
    } catch (error) {
      await hold;
      setVerifying(false);
      setNote(message(error));
      void Swal.fire({ icon: "error", title: "Verification failed", text: message(error) });
    }
  }

  if (step === "otp") {
    return (
      <AuthShell>
        <form className="auth-form auth-form-otp" onSubmit={verify}>
          <div className="auth-form-heading">
            <span>VERIFY EMAIL</span>
            <h1>Enter the 6 digit code</h1>
            <p>We sent a one time password to <strong>{form.email}</strong>.</p>
          </div>
          <label className="auth-field">One time password
            <Input
              className="auth-otp-input"
              value={code}
              onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
              inputMode="numeric"
              autoComplete="one-time-code"
              placeholder="000000"
              maxLength={6}
              required
              autoFocus
            />
          </label>
          <p className="auth-otp-hint"><MailCheck /> Can&apos;t find the email? Please <strong>check your spam folder</strong> too.</p>
          {note && <p className="auth-message auth-error" role="alert">{note}</p>}
          <Button className="auth-submit" type="submit" disabled={verifying || code.length !== 6}>
            {verifying ? <><span className="auth-spinner" /> Verifying OTP…</> : "VERIFY AND CREATE ACCOUNT"}
          </Button>
          <div className="auth-otp-actions">
            <button type="button" onClick={() => setStep("details")} disabled={verifying}>Change details</button>
            <button type="button" onClick={() => void resend()} disabled={verifying || resending}>{resending ? "Sending…" : "Resend code"}</button>
          </div>
        </form>
      </AuthShell>
    );
  }

  return (
    <AuthShell>
      <form className="auth-form auth-form-register" onSubmit={handleSubmit}>
        <div className="auth-form-heading"><span>JOIN AUTO UPI</span><h1>Register new account</h1><p>Create your secure merchant workspace.</p></div>
        <div className="auth-field-grid"><label className="auth-field">Name<Input value={form.name} onChange={(event) => update("name", event.target.value)} placeholder="Enter your name" autoComplete="name" required /></label><label className="auth-field">Mobile number<Input type="tel" value={form.mobile} onChange={(event) => update("mobile", event.target.value)} placeholder="Enter mobile number" autoComplete="tel" pattern="[0-9+ -]{8,15}" required /></label></div>
        <label className="auth-field">Email address<Input type="email" value={form.email} onChange={(event) => update("email", event.target.value)} placeholder="Enter email address" autoComplete="email" required /></label>
        <label className="auth-field">Password<span className="auth-password-wrap"><Input type={showPassword ? "text" : "password"} value={form.password} onChange={(event) => update("password", event.target.value)} placeholder="Create a strong password" autoComplete="new-password" minLength={8} required /><Button type="button" variant="ghost" size="icon" aria-label={showPassword ? "Hide password" : "Show password"} onClick={() => setShowPassword((value) => !value)}>{showPassword ? <EyeOff /> : <Eye />}</Button></span></label>
        <label className="auth-field">Confirm password<Input type="password" value={form.confirm} onChange={(event) => update("confirm", event.target.value)} placeholder="Enter password again" autoComplete="new-password" minLength={8} required /></label>
        <label className="auth-check"><Checkbox checked={agreed} onCheckedChange={(value) => setAgreed(value === true)} /> I agree to the Terms and Privacy Policy</label>
        {note && <p className="auth-message auth-error" role="alert">{note}</p>}
        <Button className="auth-submit" type="submit" disabled={loading}>{loading ? "Sending code…" : "NEXT"}</Button>
        <p className="auth-login-link">Have an account? <Link to="/auth">Login</Link></p>
      </form>
    </AuthShell>
  );
}
