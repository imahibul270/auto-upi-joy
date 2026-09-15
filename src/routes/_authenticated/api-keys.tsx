import { createFileRoute } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Copy, KeyRound, Plus, RefreshCw, ShieldCheck, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";
import { Swal } from "@/lib/swal";
import { formatDate, issueApiKey, revokeApiKey, useApiKeys } from "@/lib/gateway";

export const Route = createFileRoute("/_authenticated/api-keys")({
  head: () => ({ meta: [
    { title: "API Keys — Auto Upi" },
    { name: "description", content: "Create, copy and revoke the API keys and webhook secrets your apps use with Auto Upi." },
    { property: "og:title", content: "API Keys — Auto Upi" },
    { property: "og:description", content: "Create and rotate keys for your Auto Upi integrations." },
  ]}),
  component: ApiKeysPage,
});

async function copy(value: string, title: string) {
  try {
    await navigator.clipboard.writeText(value);
    void Swal.fire({ icon: "success", title, timer: 1400, showConfirmButton: false });
  } catch {
    void Swal.fire({ icon: "error", title: "Could not copy", text: "Copy the value manually." });
  }
}

function ApiKeysPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);
  const queryClient = useQueryClient();
  const { data: keys = [] } = useApiKeys();
  const [creating, setCreating] = useState(false);
  const [freshKey, setFreshKey] = useState<string | null>(null);
  const hasActiveKey = keys.some((key) => key.active);

  async function create() {
    setCreating(true);
    try {
      const issued = await issueApiKey("Default key");
      setFreshKey(issued.api_key);
      await queryClient.invalidateQueries({ queryKey: ["api-keys"] });
      void Swal.fire({
        icon: "success",
        title: hasActiveKey ? "API key regenerated" : "API key generated",
        text: "Copy it now — it is shown only once.",
        draggable: true,
      });
    } catch (error) {
      void Swal.fire({ icon: "error", title: "Could not create key", text: error instanceof Error ? error.message : String(error) });
    } finally {
      setCreating(false);
    }
  }

  function revoke(id: string) {
    void Swal.fire({
      icon: "warning",
      title: "Revoke this key?",
      text: "Any app using it will stop working immediately.",
      showCancelButton: true,
      confirmButtonText: "Yes, revoke",
      cancelButtonText: "Cancel",
    }).then(async (result) => {
      if (!result.isConfirmed) return;
      await revokeApiKey(id);
      await queryClient.invalidateQueries({ queryKey: ["api-keys"] });
      void Swal.fire({ icon: "success", title: "Key revoked", draggable: true });
    });
  }

  return (
    <ConsoleLayout title="API Keys" user={user} userName={name}>
      <section className="console-page-head" data-reveal>
        <h2>API Keys</h2>
        <p>Keys let your website or app create payments through Auto Upi.</p>
      </section>

      <section className="console-card reveal-delay-1" data-reveal>
        <div className="console-card-head"><h3>API key</h3><small>Only the newest key stays active</small></div>
        <div className="console-key-create">
          <Button type="button" onClick={() => void create()} disabled={creating}>
            {hasActiveKey ? <RefreshCw /> : <Plus />}
            {creating ? (hasActiveKey ? "Regenerating…" : "Generating…") : (hasActiveKey ? "Regenerate key" : "Generate key")}
          </Button>
        </div>

        {freshKey ? (
          <div className="console-key-fresh">
            <strong>Copy your key now</strong>
            <code>{freshKey}</code>
            <Button type="button" variant="outline" onClick={() => void copy(freshKey, "API key copied")}><Copy />Copy</Button>
          </div>
        ) : null}
      </section>

      <section className="console-card reveal-delay-2" data-reveal>
        <div className="console-card-head"><h3>Your keys</h3><small>{keys.length} total</small></div>
        {keys.length === 0 ? (
          <div className="console-empty console-empty-row">
            <KeyRound />
            <p>No API keys yet</p>
            <small>Create a key above to start integrating Auto Upi.</small>
          </div>
        ) : (
          <div className="console-table-wrap">
            <table className="console-table">
              <thead>
                <tr><th>NAME</th><th>KEY</th><th>WEBHOOK SECRET</th><th>STATUS</th><th>CREATED</th><th /></tr>
              </thead>
              <tbody>
                {keys.map((row) => (
                  <tr key={row.id}>
                    <td><strong>{row.label}</strong></td>
                    <td><code>{row.key_prefix}••••••••</code></td>
                    <td>
                      <span className="console-secret">
                        <code>{`${row.webhook_secret.slice(0, 12)}••••`}</code>
                        <button type="button" aria-label="Copy webhook secret" onClick={() => void copy(row.webhook_secret, "Webhook secret copied")}><Copy /></button>
                      </span>
                    </td>
                    <td><span className={`console-pill${row.active ? " is-active" : " is-muted"}`}>{row.active ? "Active" : "Revoked"}</span></td>
                    <td>{formatDate(row.created_at)}</td>
                    <td>{row.active ? <button type="button" className="console-row-action" onClick={() => revoke(row.id)} aria-label="Revoke key"><Trash2 /></button> : null}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="console-note"><ShieldCheck />Full keys are stored hashed — we can never show an old key again.</p>
      </section>
    </ConsoleLayout>
  );
}
