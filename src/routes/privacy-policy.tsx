import { createFileRoute } from "@tanstack/react-router";
import { LegalPage } from "@/components/LegalPage";

export const Route = createFileRoute("/privacy-policy")({
  component: PrivacyPolicy,
  head: () => ({
    meta: [
      { title: "autoupi | Privacy Policy" },
      { name: "description", content: "How Auto Upi collects, uses, stores and protects your personal and payment information." },
      { property: "og:title", content: "autoupi | Privacy Policy" },
      { property: "og:description", content: "How Auto Upi handles your data, mailbox access and payment information." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});

function PrivacyPolicy() {
  return (
    <LegalPage title="Privacy Policy" updated="19 September 2026">
      <h2>1. Information we collect</h2>
      <ul>
        <li>Account details: name, email address, mobile number and password (stored only in encrypted form).</li>
        <li>Business details: UPI ID, payee name and the payment links you create.</li>
        <li>Mailbox details: the email address and app password you add so we can read payment alert emails.</li>
        <li>Transaction data: order IDs, amounts, status, timestamps and payer names from payment alerts.</li>
        <li>Technical data: IP address, browser type and basic usage logs needed for security.</li>
      </ul>

      <h2>2. How we use your information</h2>
      <p>
        We use your information only to run the service: creating payment links, confirming payments automatically,
        showing your transactions, managing your plan and limits, sending you service notifications, and protecting
        the platform from fraud and abuse.
      </p>

      <h2>3. Mailbox access</h2>
      <p>
        If you connect a mailbox, we read only payment alert emails in order to match a payment to your payment link.
        We never send email from your account, never read unrelated personal mail, and never share mailbox content with
        anyone. Your app password is stored securely and is used only for this purpose. You can disconnect the mailbox
        at any time from your dashboard, and access stops immediately.
      </p>

      <h2>4. Payment information</h2>
      <p>
        Payments move directly between the customer and your own UPI account through UPI apps. We do not collect or
        store card numbers, UPI PINs, bank passwords or any other banking credentials.
      </p>

      <h2>5. Data sharing</h2>
      <p>
        We do not sell or rent your data. Information is shared only with the hosting, database and email
        infrastructure providers required to operate the service, or where disclosure is required by law.
      </p>

      <h2>6. Data security</h2>
      <p>
        Data is transmitted over encrypted connections and stored with per-account access rules, so one merchant can
        never see another merchant's data. Webhook messages we send to your systems are signed so you can verify they
        came from us.
      </p>

      <h2>7. Data retention and your rights</h2>
      <p>
        We keep your account and transaction records while your account is active and for as long as required by law.
        You may request a copy of your data, correction of wrong details, or deletion of your account by writing to us.
        Deleting your account removes your mailbox credentials and payment links.
      </p>

      <h2>8. Cookies</h2>
      <p>
        We use only essential cookies and local storage to keep you signed in and to remember basic preferences. We do
        not use advertising trackers.
      </p>

      <h2>9. Children</h2>
      <p>The service is not intended for anyone under 18 years of age.</p>

      <h2>10. Changes and contact</h2>
      <p>
        We may update this policy from time to time and the revised date will appear at the top of this page. For any
        privacy question, contact <a href="mailto:support@autoupi.in">support@autoupi.in</a> or WhatsApp{" "}
        <a href="https://wa.me/918472028929" target="_blank" rel="noreferrer">+91 84720 28929</a>.
      </p>
    </LegalPage>
  );
}
