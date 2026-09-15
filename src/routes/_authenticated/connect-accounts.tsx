import { createFileRoute } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useState, type FormEvent } from "react";
import { CheckCircle2, ChevronDown, Link2Off, Mail, Plug, ShieldCheck, Wallet } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";
import { Swal } from "@/lib/swal";
import {
  PROVIDERS,
  connectMerchantAccount,
  disconnectMerchantAccount,
  saveMerchantAccount,
  useMerchantAccounts,
  type Provider,
} from "@/lib/gateway";

export const Route = createFileRoute("/_authenticated/connect-accounts")({
  head: () => ({ meta: [
    { title: "Connect Accounts — Auto Upi" },
    { name: "description", content: "Connect your PhonePe or Paytm UPI ID and payment alert mailbox so Auto Upi detects payments automatically." },
    { property: "og:title", content: "Connect Accounts — Auto Upi" },
    { property: "og:description", content: "Link UPI IDs and payment alert mailboxes for automatic payment detection." },
  ]}),
  component: ConnectAccountsPage,
});

const FRIENDLY: Record<string, string> = {
  INVALID_UPI_ID: "Enter a valid UPI ID, for example name@okhdfcbank.",
  INVALID_EMAIL: "Enter the email address that receives your payment alerts.",
  INVALID_APP_PASSWORD: "Enter the 16-character app password from your mail account.",
  UPI_NOT_SAVED: "Save your UPI ID first, then connect the mailbox.",
  ACCOUNT_NOT_FOUND: "Nothing to disconnect for this app.",
};

function friendly(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  const key = Object.keys(FRIENDLY).find((code) => message.includes(code));
  return key ? FRIENDLY[key] : message;
}

function ConnectAccountsPage() {
  const { user } = Route.useRouteContext();
  const name = useConsoleName(user);
  const queryClient = useQueryClient();
  const { data: accounts = [] } = useMerchantAccounts();

  const [provider, setProvider] = useState<Provider>("phonepe");
  const [upiId, setUpiId] = useState("");
  const [payeeName, setPayeeName] = useState("");
  const [email, setEmail] = useState("");
  const [appPassword, setAppPassword] = useState("");
  const [saving, setSaving] = useState(false);
  const [connecting, setConnecting] = useState(false);

  const current = accounts.find((item) => item.provider === provider);
  const providerLabel = PROVIDERS.find((item) => item.value === provider)?.label ?? "";

  useEffect(() => {
    setUpiId(current?.upi_id ?? "");
    setPayeeName(current?.payee_name ?? "");
    setEmail(current?.email ?? "");
    setAppPassword("");
  }, [provider, current?.upi_id, current?.payee_name, current?.email]);

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["merchant-accounts"] });

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    try {
      await saveMerchantAccount({ provider, upiId, payeeName });
      await refresh();
      void Swal.fire({ icon: "success", title: "UPI ID saved", text: `${providerLabel} UPI ID saved successfully.`, draggable: true });
    } catch (error) {
      void Swal.fire({ icon: "error", title: "Could not save", text: friendly(error) });
    } finally {
      setSaving(false);
    }
  }

  async function connect(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setConnecting(true);
    try {
      await connectMerchantAccount({ provider, email, appPassword });
      setAppPassword("");
      await refresh();
      void Swal.fire({ icon: "success", title: "Connected", text: `${providerLabel} mailbox connected successfully.`, draggable: true });
    } catch (error) {
      void Swal.fire({ icon: "error", title: "Could not connect", text: friendly(error) });
    } finally {
      setConnecting(false);
    }
  }

  function disconnect() {
    void Swal.fire({
      icon: "warning",
      title: "Disconnect mailbox?",
      text: `Payment detection for ${providerLabel} will stop.`,
      showCancelButton: true,
      confirmButtonText: "Yes, disconnect",
      cancelButtonText: "Cancel",
    }).then(async (result) => {
      if (!result.isConfirmed) return;
      try {
        await disconnectMerchantAccount(provider);
        await refresh();
        void Swal.fire({ icon: "success", title: "Disconnected", text: `${providerLabel} mailbox disconnected.`, draggable: true });
      } catch (error) {
        void Swal.fire({ icon: "error", title: "Could not disconnect", text: friendly(error) });
      }
    });
  }

  return (
    <ConsoleLayout title="Connect Accounts" user={user} userName={name}>
      <section className="console-page-head" data-reveal>
        <h2>Connect Accounts</h2>
        <p>Choose your payment app, save the UPI ID, then connect the mailbox that receives payment alerts.</p>
      </section>

      <section className="console-connect-grid">
        <div className="console-card reveal-delay-1" data-reveal>
          <form className="console-form" onSubmit={save}>
            <div className="console-settings-heading">
              <Wallet />
              <div><strong>Payment app & UPI ID</strong><small>Money settles straight into this UPI ID</small></div>
            </div>

            <label className="console-field">
              Payment app
              <span className="console-select">
                <select value={provider} onChange={(event) => setProvider(event.target.value as Provider)}>
                  {PROVIDERS.map((item) => (
                    <option key={item.value} value={item.value}>{item.label}</option>
                  ))}
                </select>
                <ChevronDown />
              </span>
              <small>{PROVIDERS.find((item) => item.value === provider)?.hint}</small>
            </label>

            <label className="console-field">
              UPI ID
              <Input value={upiId} onChange={(event) => setUpiId(event.target.value)} placeholder="yourname@okhdfcbank" required />
            </label>

            <label className="console-field">
              Payee name <em>(optional)</em>
              <Input value={payeeName} onChange={(event) => setPayeeName(event.target.value)} placeholder="Auto Upi Store" />
            </label>

            <Button type="submit" disabled={saving}>{saving ? "Saving…" : "Save"}</Button>
          </form>
        </div>

        <div className="console-card reveal-delay-2" data-reveal>
          <form className="console-form" onSubmit={connect}>
            <div className="console-settings-heading">
              <Mail />
              <div><strong>Payment alert mailbox</strong><small>Email and app password of the inbox that gets {providerLabel} alerts</small></div>
            </div>

            <span className={`console-conn-badge${current?.connected ? " is-on" : ""}`}>
              <i />{current?.connected ? "Connected" : "Not connected"}
            </span>

            <label className="console-field">
              Email
              <Input type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="alerts@gmail.com" required />
            </label>

            <label className="console-field">
              App password
              <Input
                type="password"
                value={appPassword}
                onChange={(event) => setAppPassword(event.target.value)}
                placeholder={current?.connected ? "Enter again to reconnect" : "abcd efgh ijkl mnop"}
                autoComplete="off"
                required
              />
              <small>Use your mail provider's app password, never your login password.</small>
            </label>

            <div className="console-form-actions">
              <Button type="submit" disabled={connecting}>
                <Plug />{connecting ? "Connecting…" : current?.connected ? "Reconnect" : "Connect"}
              </Button>
              {current?.connected ? (
                <Button type="button" variant="outline" onClick={disconnect}><Link2Off />Disconnect</Button>
              ) : null}
            </div>

            <p className="console-note"><ShieldCheck />Credentials are stored server side and are never sent back to the browser.</p>
          </form>
        </div>
      </section>

      <section className="console-card reveal-delay-3" data-reveal>
        <div className="console-card-head"><h3>Connection status</h3><small>Updates live</small></div>
        <div className="console-conn-list">
          {PROVIDERS.map((item) => {
            const account = accounts.find((row) => row.provider === item.value);
            return (
              <div key={item.value} className="console-conn-row">
                <span className="console-conn-name"><CheckCircle2 />{item.label}</span>
                <span className="console-conn-upi">{account?.upi_id || "No UPI ID saved"}</span>
                <span className="console-conn-mail">{account?.email || "—"}</span>
                <span className={`console-conn-badge${account?.connected ? " is-on" : ""}`}>
                  <i />{account?.connected ? "Connected" : "Disconnected"}
                </span>
              </div>
            );
          })}
        </div>
      </section>
    </ConsoleLayout>
  );
}
