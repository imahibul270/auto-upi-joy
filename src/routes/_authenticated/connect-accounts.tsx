import { createFileRoute } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useState, type FormEvent } from "react";
import { CheckCircle2, ChevronDown, Link2Off, Mail, Plug, RefreshCw, ShieldCheck, Wallet } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ConsoleLayout } from "@/components/console/ConsoleLayout";
import { useConsoleName } from "@/components/console/useConsoleName";
import { Swal } from "@/lib/swal";
import {
  PROVIDERS,
  saveMerchantAccount,
  useMerchantAccounts,
  type Provider,
} from "@/lib/gateway";
import {
  disconnectGmail,
  getGmailStatus,
  saveGmailCredentials,
  startGmailConnect,
} from "@/lib/gmail.functions";
import { useServerFn } from "@tanstack/react-start";
import { useQuery } from "@tanstack/react-query";

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
  const [saving, setSaving] = useState(false);

  const current = accounts.find((item) => item.provider === provider);
  const providerLabel = PROVIDERS.find((item) => item.value === provider)?.label ?? "";

  useEffect(() => {
    setUpiId(current?.upi_id ?? "");
    setPayeeName(current?.payee_name ?? "");
  }, [provider, current?.upi_id, current?.payee_name]);

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

        <GmailCard />
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
                <span className="console-conn-mail">{account?.upi_id ? "UPI saved" : "—"}</span>
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

function GmailCard() {
  const fetchStatus = useServerFn(getGmailStatus);
  const saveCreds = useServerFn(saveGmailCredentials);
  const beginConnect = useServerFn(startGmailConnect);
  const disconnect = useServerFn(disconnectGmail);

  const [clientId, setClientId] = useState("");
  const [clientSecret, setClientSecret] = useState("");
  const [busy, setBusy] = useState(false);

  const status = useQuery({
    queryKey: ["gmail-status"],
    queryFn: () => fetchStatus({ data: undefined as never }),
    refetchInterval: 8000,
    refetchOnWindowFocus: true,
  });

  const connected = status.data?.connected ?? false;
  const redirectUri = typeof window === "undefined" ? "" : `${window.location.origin}/api/public/gmail/callback`;

  useEffect(() => {
    if (typeof window === "undefined") return;
    const params = new URLSearchParams(window.location.search);
    if (params.get("gmail") === "connected") {
      void Swal.fire({ icon: "success", title: "Mailbox connected", text: "Payments will now be detected automatically.", draggable: true });
      window.history.replaceState({}, "", window.location.pathname);
      void status.refetch();
    } else if (params.get("error")) {
      void Swal.fire({ icon: "error", title: "Could not connect", text: params.get("error") ?? "" });
      window.history.replaceState({}, "", window.location.pathname);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    try {
      await saveCreds({ data: { clientId, clientSecret } });
      setClientSecret("");
      await status.refetch();
      void Swal.fire({ icon: "success", title: "Saved", text: "Now click Connect mailbox.", draggable: true });
    } catch (error) {
      void Swal.fire({ icon: "error", title: "Could not save", text: error instanceof Error ? error.message : String(error) });
    } finally {
      setBusy(false);
    }
  }

  async function connectNow() {
    setBusy(true);
    try {
      const { url } = await beginConnect({ data: { origin: window.location.origin } });
      window.location.href = url;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      void Swal.fire({
        icon: "error",
        title: "Could not start",
        text: message.includes("SAVE_CREDENTIALS_FIRST") ? "Save your Google client ID and secret first." : message,
      });
      setBusy(false);
    }
  }

  function removeConnection() {
    void Swal.fire({
      icon: "warning",
      title: "Disconnect mailbox?",
      text: "Automatic payment detection will stop.",
      showCancelButton: true,
      confirmButtonText: "Yes, disconnect",
      cancelButtonText: "Cancel",
    }).then(async (result) => {
      if (!result.isConfirmed) return;
      await disconnect({ data: undefined as never });
      await status.refetch();
      void Swal.fire({ icon: "success", title: "Disconnected", draggable: true });
    });
  }

  return (
    <div className="console-card reveal-delay-2" data-reveal>
      <form className="console-form" onSubmit={save}>
        <div className="console-settings-heading">
          <Mail />
          <div>
            <strong>Payment alert mailbox</strong>
            <small>Connect the Gmail inbox that receives PhonePe / Paytm payment alerts</small>
          </div>
        </div>

        <span className={`console-conn-badge${connected ? " is-on" : ""}`}>
          <i />{connected ? `Connected — ${status.data?.email ?? "Gmail"}` : status.data?.needsReconnect ? "Reconnect needed" : "Not connected"}
        </span>

        <label className="console-field">
          Google client ID
          <Input value={clientId} onChange={(event) => setClientId(event.target.value)} placeholder="xxxx.apps.googleusercontent.com" required />
        </label>

        <label className="console-field">
          Google client secret
          <Input
            type="password"
            value={clientSecret}
            onChange={(event) => setClientSecret(event.target.value)}
            placeholder={status.data?.hasCredentials ? "Saved — enter again to replace" : "GOCSPX-…"}
            autoComplete="off"
            required
          />
          <small>Authorised redirect URI: {redirectUri}</small>
        </label>

        <div className="console-form-actions">
          <Button type="submit" disabled={busy}>{busy ? "Saving…" : "Save credentials"}</Button>
          <Button type="button" variant="outline" onClick={() => void connectNow()} disabled={busy || !status.data?.hasCredentials}>
            <Plug />{connected ? "Reconnect mailbox" : "Connect mailbox"}
          </Button>
          {connected ? (
            <Button type="button" variant="outline" onClick={removeConnection}><Link2Off />Disconnect</Button>
          ) : null}
        </div>

        <p className="console-note">
          <RefreshCw />Payments are checked every few seconds; a payment is normally captured within 5–15 seconds of the alert email.
        </p>
        <p className="console-note"><ShieldCheck />Credentials stay on the server and are never sent back to the browser.</p>
      </form>
    </div>
  );
}
