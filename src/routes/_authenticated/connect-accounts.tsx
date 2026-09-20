import { createFileRoute } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useState, type FormEvent } from "react";
import { CheckCircle2, ChevronDown, Link2Off, Mail, Plug, PlayCircle, Wallet } from "lucide-react";
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
    { title: "autoupi | Connect Accounts" },
    { name: "description", content: "Connect your PhonePe or Paytm UPI ID and payment alert mailbox so Auto Upi detects payments automatically." },
    { property: "og:title", content: "autoupi | Connect Accounts" },
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
  const [saving, setSaving] = useState(false);

  const [email, setEmail] = useState("");
  const [appPassword, setAppPassword] = useState("");
  const [connecting, setConnecting] = useState(false);

  const current = accounts.find((item) => item.provider === provider);
  const providerLabel = PROVIDERS.find((item) => item.value === provider)?.label ?? "";
  const connected = Boolean(current?.connected);

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
      void Swal.fire({
        icon: "success",
        title: "Mailbox connected",
        text: "Payments will now be detected automatically from your alert emails.",
        draggable: true,
      });
    } catch (error) {
      void Swal.fire({ icon: "error", title: "Could not connect", text: friendly(error) });
    } finally {
      setConnecting(false);
    }
  }

  function removeConnection() {
    void Swal.fire({
      icon: "warning",
      title: "Disconnect mailbox?",
      text: "Automatic payment detection will stop for this app.",
      showCancelButton: true,
      confirmButtonText: "Yes, disconnect",
      cancelButtonText: "Cancel",
    }).then(async (result) => {
      if (!result.isConfirmed) return;
      try {
        await disconnectMerchantAccount(provider);
        await refresh();
        void Swal.fire({ icon: "success", title: "Disconnected", draggable: true });
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
              <div>
                <strong>Payment alert mailbox</strong>
                <small>The inbox that receives your {providerLabel} payment alerts</small>
              </div>
            </div>

            <span className={`console-conn-badge${connected && !current?.mail_error ? " is-on" : ""}`}>
              <i />{connected ? (current?.mail_error ? "Needs attention" : "Connected") : "Disconnected"}
            </span>

            {current?.mail_error ? (
              <p className="console-mail-warn" role="alert"><AlertTriangle />{current.mail_error}</p>
            ) : null}

            <label className="console-field">
              Email address
              <Input
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                placeholder="you@gmail.com"
                autoComplete="off"
                required
              />
            </label>

            <label className="console-field">
              App password
              <Input
                type="password"
                value={appPassword}
                onChange={(event) => setAppPassword(event.target.value)}
                placeholder={connected ? "Saved — enter again to replace" : "abcd efgh ijkl mnop"}
                autoComplete="off"
                required
              />
              <small>16-character app password from your mail account (not your login password).</small>
            </label>

            <div className="console-form-actions">
              <Button type="submit" disabled={connecting}>
                <Plug />{connecting ? "Connecting…" : connected ? "Reconnect mailbox" : "Connect mailbox"}
              </Button>
              {connected ? (
                <Button type="button" variant="outline" onClick={removeConnection}><Link2Off />Disconnect</Button>
              ) : null}
              <Button
                type="button"
                variant="outline"
                onClick={() => window.open("https://youtu.be/PkpJO2-bS98", "_blank", "noopener,noreferrer")}
              >
                <PlayCircle />Watch
              </Button>
            </div>

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
                <span className="console-conn-mail">{account?.connected ? "Connected" : "Disconnected"}</span>
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
