import { Link } from "@tanstack/react-router";
import { BrandLogo } from "@/components/BrandLogo";
import type { ReactNode } from "react";

export function LegalPage({ title, updated, children }: { title: string; updated: string; children: ReactNode }) {
  return (
    <div className="legal-page">
      <header className="legal-head">
        <Link to="/" className="legal-brand"><BrandLogo /><span>Auto Upi</span></Link>
        <nav className="legal-nav">
          <Link to="/">Home</Link>
          <Link to="/docs">Docs</Link>
          <Link to="/refund-policy">Refund</Link>
          <Link to="/privacy-policy">Privacy</Link>
        </nav>
      </header>
      <main className="legal-main">
        <h1>{title}</h1>
        <p className="legal-updated">Last updated: {updated}</p>
        <div className="legal-body">{children}</div>
      </main>
      <footer className="legal-foot">
        <span>© 2026 Auto Upi. All rights reserved.</span>
        <span>support@autoupi.in · +91 84720 28929</span>
      </footer>
    </div>
  );
}
