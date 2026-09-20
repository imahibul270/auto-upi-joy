import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState, type FormEvent } from "react";
import { CheckCircle2, Globe, Webhook } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";
import { Swal } from "@/lib/swal";
import { fetchMerchantConfig, saveMerchantConfig } from "@/lib/gateway";

export const Route = createFileRoute("/_authenticated/config")({
  head: () => ({ meta: [
    { title: "autoupi | Config" },
    { name: "description", content: "Set your success redirect URL, failed redirect URL and webhook URL for Auto Upi payments." },
    { property: "og:title", content: "autoupi | Config" },
    { property: "og:description", content: "Configure redirect and webhook URLs for your Auto Upi account." },
  ]}),
  component: ConfigPage,
});

const FRIENDLY: Record<string, string> = {
  INVALID_SUCCESS_URL: "Success URL must start with http:// or https://",
  INVALID_FAILURE_URL: "Failed URL must start with http:// or https://",
  INVALID_WEBHOOK_URL: "Webhook URL must start with https://",
};

function friendly(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  const key = Object.keys(FRIENDLY).find((code) => message.includes(code));
  return key ? FRIENDLY[key] : message;
}

function ConfigPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);
  const queryClient = useQueryClient();
  const { data: config } = useQuery({ queryKey: ["merchant-config"], queryFn: fetchMerchantConfig });

  const [successUrl, setSuccessUrl] = useState("");
  const [failureUrl, setFailureUrl] = useState("");
  const [webhookUrl, setWebhookUrl] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setSuccessUrl(config?.success_url ?? "");
    setFailureUrl(config?.failure_url ?? "");
    setWebhookUrl(config?.webhook_url ?? "");
  }, [config?.success_url, config?.failure_url, config?.webhook_url]);

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    try {
      await saveMerchantConfig({ successUrl, failureUrl, webhookUrl });
      await queryClient.invalidateQueries({ queryKey: ["merchant-config"] });
      void Swal.fire({ icon: "success", title: "Config saved", text: "Your redirect and webhook URLs are live now.", draggable: true });
    } catch (error) {
      void Swal.fire({ icon: "error", title: "Could not save", text: friendly(error) });
    } finally {
      setSaving(false);
    }
  }

  return (
    <ConsoleLayout title="Config" user={user} userName={name}>
      <section className="console-page-head" data-reveal>
        <h2>Config</h2>
        <p>Set where your customers return after paying and where we send payment events. These settings apply only to your own payment links.</p>
      </section>

      <section className="console-connect-grid">
        <div className="console-card reveal-delay-1" data-reveal>
          <form className="console-form" onSubmit={save}>
            <div className="console-settings-heading">
              <Globe />
              <div><strong>Redirect URLs</strong><small>Where the payer lands after the payment page</small></div>
            </div>

            <label className="console-field">
              Success redirect URL
              <Input value={successUrl} onChange={(event) => setSuccessUrl(event.target.value)} placeholder="https://yoursite.com/payment-success" />
              <small>Opened after a successful payment, with <code>?order_id=…&amp;status=paid</code> added.</small>
            </label>

            <label className="console-field">
              Failed redirect URL
              <Input value={failureUrl} onChange={(event) => setFailureUrl(event.target.value)} placeholder="https://yoursite.com/payment-failed" />
              <small>Opened when the payment link expires without payment, with <code>?order_id=…&amp;status=failed</code> added.</small>
            </label>

            <div className="console-settings-heading">
              <Webhook />
              <div><strong>Webhook URL</strong><small>Signed <code>payment.paid</code> events, server to server</small></div>
            </div>

            <label className="console-field">
              Webhook URL
              <Input value={webhookUrl} onChange={(event) => setWebhookUrl(event.target.value)} placeholder="https://yoursite.com/autoupi-webhook.php" />
              <small>Must be HTTPS. Used for every order unless you send a <code>webhook_url</code> in the create order API.</small>
            </label>

            <Button type="submit" disabled={saving}>{saving ? "Saving…" : "Save config"}</Button>
          </form>
        </div>

        <div className="console-card reveal-delay-2" data-reveal>
          <div className="console-card-head"><h3>Current settings</h3><small>Only your account</small></div>
          <div className="console-conn-list">
            <div className="console-conn-row">
              <span className="console-conn-name"><CheckCircle2 />Success</span>
              <span className="console-conn-upi">{config?.success_url || "Not set — payer stays on the result page"}</span>
            </div>
            <div className="console-conn-row">
              <span className="console-conn-name"><CheckCircle2 />Failed</span>
              <span className="console-conn-upi">{config?.failure_url || "Not set — payer stays on the result page"}</span>
            </div>
            <div className="console-conn-row">
              <span className="console-conn-name"><CheckCircle2 />Webhook</span>
              <span className="console-conn-upi">{config?.webhook_url || "Not set — no webhook is sent"}</span>
            </div>
          </div>
        </div>
      </section>
    </ConsoleLayout>
  );
}
