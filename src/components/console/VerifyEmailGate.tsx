import { useQuery } from "@tanstack/react-query";
import { MailCheck, ShieldCheck } from "lucide-react";
import { useState, type FormEvent } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Swal } from "@/lib/swal";
import { getVerificationState, sendAccountOtp, verifyAccountOtp } from "@/lib/signup-otp.functions";

const message = (error: unknown) => (error instanceof Error ? error.message : "Something went wrong. Please try again.");

/** One-time email check for accounts created before the OTP signup flow existed. */
export function VerifyEmailGate() {
  const { data, refetch } = useQuery({
    queryKey: ["email-verification"],
    queryFn: () => getVerificationState(),
    staleTime: 60_000,
  });
  const [sent, setSent] = useState(false);
  const [sending, setSending] = useState(false);
  const [code, setCode] = useState("");
  const [verifying, setVerifying] = useState(false);
  const [note, setNote] = useState("");

  if (!data || data.verified) return null;

  async function getOtp() {
    setSending(true);
    setNote("");
    try {
      await sendAccountOtp();
      setSent(true);
    } catch (error) {
      setNote(message(error));
      void Swal.fire({ icon: "error", title: "Could not send code", text: message(error) });
    } finally {
      setSending(false);
    }
  }

  async function verify(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (verifying) return;
    setVerifying(true);
    setNote("");
    const hold = new Promise((resolve) => window.setTimeout(resolve, 2000));
    try {
      await Promise.all([verifyAccountOtp({ data: { code: code.trim() } }), hold]);
      setVerifying(false);
      await Swal.fire({ icon: "success", title: "Email verified", timer: 1500, showConfirmButton: false });
      await refetch();
    } catch (error) {
      await hold;
      setVerifying(false);
      setNote(message(error));
      void Swal.fire({ icon: "error", title: "Verification failed", text: message(error) });
    }
  }

  return (
    <div className="verify-gate">
      <div className="verify-card">
        <span className="verify-icon"><ShieldCheck /></span>
        <h2>Verify your email</h2>
        <p>
          This is a one time check for your account <strong>{data.email}</strong>. Get the code and enter it below to
          continue using Auto Upi.
        </p>

        {!sent ? (
          <Button className="verify-btn" type="button" onClick={() => void getOtp()} disabled={sending}>
            {sending ? <><span className="auth-spinner" /> Sending code…</> : "GET OTP"}
          </Button>
        ) : (
          <form className="verify-form" onSubmit={verify}>
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
            <p className="auth-otp-hint"><MailCheck /> Can&apos;t find the email? Please <strong>check your spam folder</strong> too.</p>
            <Button className="verify-btn" type="submit" disabled={verifying || code.length !== 6}>
              {verifying ? <><span className="auth-spinner" /> Verifying OTP…</> : "VERIFY"}
            </Button>
            <button className="verify-resend" type="button" onClick={() => void getOtp()} disabled={sending || verifying}>
              {sending ? "Sending…" : "Resend code"}
            </button>
          </form>
        )}
        {note && <p className="auth-message auth-error" role="alert">{note}</p>}
      </div>
    </div>
  );
}
