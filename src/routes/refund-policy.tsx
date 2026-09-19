import { createFileRoute } from "@tanstack/react-router";
import { LegalPage } from "@/components/LegalPage";

export const Route = createFileRoute("/refund-policy")({
  component: RefundPolicy,
  head: () => ({
    meta: [
      { title: "autoupi | Refund Policy" },
      { name: "description", content: "Auto Upi refund policy for digital products, software licences, source code and subscriptions." },
      { property: "og:title", content: "autoupi | Refund Policy" },
      { property: "og:description", content: "How refunds work for Auto Upi digital products and subscriptions." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});

function RefundPolicy() {
  return (
    <LegalPage title="Refund Policy" updated="19 September 2026">
      <h2>1. Digital products are non-refundable</h2>
      <p>
        Everything we sell — applications, websites, source code, extensions, scripts, plugins, licence keys and
        subscriptions — is a digital product. Once a digital product is delivered, it can be copied, stored or shared
        instantly, and the work behind it cannot be returned to us. For this reason, all sales are final and we do not
        offer refunds after delivery is complete.
      </p>

      <h2>2. You always see the product before you buy</h2>
      <p>
        Before any purchase, we provide a complete live demo of the product so you can check every feature yourself. We
        never pressure or force anyone to buy. Every purchase is made voluntarily, with full knowledge of what the
        product does and what it does not do. Please review the demo carefully and ask us anything before paying.
      </p>

      <h2>3. Support and remote setup are included</h2>
      <p>
        We do not leave you alone after payment. When the product is delivered, our team personally sets it up and
        tests it remotely with you, so that everything works correctly on your server, hosting or device before the
        delivery is treated as complete.
      </p>

      <h2>4. When a refund is possible</h2>
      <p>
        If, at the time of installation or setup, the product cannot be made to work because of a genuine fault on our
        side, and we are unable to fix it, we will issue a refund for that purchase. This applies only during the
        installation and testing stage, before delivery is marked complete.
      </p>

      <h2>5. When a refund is not possible</h2>
      <ul>
        <li>After successful testing and complete delivery of the product.</li>
        <li>Change of mind, or buying the wrong product by mistake.</li>
        <li>Lack of the technical knowledge, hosting or third-party services needed to run the product.</li>
        <li>Requests for features that were never part of the product or the demo.</li>
        <li>Problems caused by your own modification of the code, or by a third party.</li>
        <li>Suspension or termination of your account for misuse, fraud or illegal activity.</li>
        <li>Subscription periods that have already started or partly been used.</li>
      </ul>

      <h2>6. Failed or duplicate payments</h2>
      <p>
        If money is debited but the order or subscription does not activate, or if you are charged twice for the same
        order, contact us with the order ID and payment reference. After verification, the extra or failed amount is
        returned to the original payment method, normally within 5–7 working days.
      </p>

      <h2>7. How to contact us</h2>
      <p>
        Write to <a href="mailto:support@autoupi.in">support@autoupi.in</a> or message us on WhatsApp at{" "}
        <a href="https://wa.me/918472028929" target="_blank" rel="noreferrer">+91 84720 28929</a> with your order ID
        and a clear description of the issue. We reply to every genuine request.
      </p>
    </LegalPage>
  );
}
