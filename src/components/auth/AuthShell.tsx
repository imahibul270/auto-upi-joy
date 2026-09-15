import { Link } from "@tanstack/react-router";
import { QrCode, ScanLine } from "lucide-react";
import type { ReactNode } from "react";

export function AuthShell({ children }: { children: ReactNode }) {
  return (
    <main className="auth-page">
      <Link to="/" className="auth-brand page-enter page-enter-early" aria-label="Auto Upi home">
        <BrandLogo className="brand-logo-lg" />
        <strong>Auto Upi</strong>
      </Link>
      <section className="auth-layout">
        <div className="auth-visual page-enter page-enter-left" aria-label="Secure UPI QR payment illustration">
          <div className="auth-art">
            <span className="auth-art-circle" />
            <div className="auth-back-qr"><QrCode /></div>
            <div className="auth-phone">
              <span className="auth-phone-speaker" />
              <div className="auth-phone-screen"><QrCode /><i /></div>
              <span className="auth-phone-button" />
            </div>
            <div className="auth-hand"><span /></div>
          </div>
          <p>Generate secure payment links instantly. Share, scan and collect with confidence.</p>
        </div>
        <div className="auth-divider page-enter page-enter-divider" />
        <div className="auth-form-column page-enter page-enter-right">{children}</div>
      </section>
    </main>
  );
}
