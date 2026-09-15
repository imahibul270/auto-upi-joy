// Payment detection engine: reads PhonePe / Paytm alert emails through the
// Gmail API for one merchant and marks the matching payment link as paid.
// Server only — never import this from client code.
import { supabaseAdmin } from "@/integrations/supabase/client.server";

const MONITOR_SENDERS = ["no-reply@paytm.com", "noreply@phonepe.com", "noreply@phonepe.com"];
const PAYTM_AMOUNT_RE = /Rs\.?\s*([0-9]+(?:\.[0-9]{1,2})?)\s+paid/i;
const PHONEPE_AMOUNT_RE = /Received\s*(?:₹|Rs\.?|INR)?\s*([0-9]+(?:\.[0-9]{1,2})?)\s+from/i;
const GENERIC_AMOUNT_RE = /(?:₹|Rs\.?|INR)\s*([0-9]+(?:\.[0-9]{1,2})?)/i;
const NAME_PATTERNS: RegExp[] = [
  /paid\s+by\s+([A-Za-z][A-Za-z .'\-]{1,60}?)(?=\s+(?:on|via|to|using|at|through|-|–|—|$))/i,
  /from\s+([A-Za-z][A-Za-z .'\-]{1,60}?)(?=\s+(?:on|via|to|using|at|through|-|–|—|$))/i,
  /by\s+([A-Za-z][A-Za-z .'\-]{1,60}?)(?=\s+(?:on|via|to|using|at|through|-|–|—|$))/i,
];

export type PollResult = {
  ok: boolean;
  connected: boolean;
  scanned: number;
  matched: number;
  expired: number;
  error?: string;
};

type GmailHeader = { name: string; value: string };

function extractAmount(subject: string): number | null {
  const m = subject.match(PAYTM_AMOUNT_RE) ?? subject.match(PHONEPE_AMOUNT_RE) ?? subject.match(GENERIC_AMOUNT_RE);
  return m?.[1] ? Number.parseFloat(m[1]) : null;
}

function extractName(subject: string): string | null {
  for (const re of NAME_PATTERNS) {
    const m = subject.match(re);
    const found = m?.[1]?.trim().replace(/\s+/g, " ");
    if (found && found.length >= 2 && found.length <= 60) return found;
  }
  return null;
}

function senderMatches(from: string): boolean {
  const f = from.toLowerCase();
  return MONITOR_SENDERS.some((s) => f.includes(s));
}

/** Returns a usable access token, refreshing it when it is close to expiry. */
async function accessTokenFor(row: any): Promise<string | null> {
  const fresh = row.token_expires_at ? Date.parse(row.token_expires_at) > Date.now() + 30_000 : false;
  if (fresh && row.access_token) return row.access_token as string;
  if (!row.refresh_token || !row.oauth_client_id || !row.oauth_client_secret) return null;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: row.oauth_client_id,
      client_secret: row.oauth_client_secret,
      refresh_token: row.refresh_token,
      grant_type: "refresh_token",
    }),
  });
  if (!res.ok) {
    await (supabaseAdmin.from("gmail_connections") as any)
      .update({ status: "needs_reconnect" })
      .eq("user_id", row.user_id);
    return null;
  }
  const tok = (await res.json()) as { access_token: string; expires_in: number };
  await (supabaseAdmin.from("gmail_connections") as any)
    .update({
      access_token: tok.access_token,
      token_expires_at: new Date(Date.now() + (tok.expires_in - 60) * 1000).toISOString(),
      status: "connected",
    })
    .eq("user_id", row.user_id);
  return tok.access_token;
}

async function gmailGet(token: string, path: string): Promise<any> {
  const res = await fetch(`https://gmail.googleapis.com/gmail/v1${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`Gmail ${path}: ${res.status}`);
  return res.json();
}

/** Scan the merchant's inbox and settle any matching pending payment link. */
export async function pollPaymentsForUser(userId: string): Promise<PollResult> {
  const admin = supabaseAdmin as any;

  const { data: expiredCount } = await admin.rpc("expire_stale_payment_links", { _user: userId });
  const expired = Number(expiredCount ?? 0);

  const { data: conn } = await admin
    .from("gmail_connections")
    .select("*")
    .eq("user_id", userId)
    .maybeSingle();

  if (!conn || conn.status === "credentials_only" || !conn.refresh_token) {
    return { ok: true, connected: false, scanned: 0, matched: 0, expired };
  }

  const token = await accessTokenFor(conn);
  if (!token) return { ok: false, connected: false, scanned: 0, matched: 0, expired, error: "needs_reconnect" };

  try {
    const query = `(${MONITOR_SENDERS.map((s) => `from:${s}`).join(" OR ")}) newer_than:1d`;
    const list = await gmailGet(token, `/users/me/messages?maxResults=15&q=${encodeURIComponent(query)}`);
    const messages: { id: string }[] = list.messages ?? [];
    await admin.from("gmail_connections").update({ last_polled_at: new Date().toISOString() }).eq("user_id", userId);
    if (messages.length === 0) return { ok: true, connected: true, scanned: 0, matched: 0, expired };

    const ids = messages.map((m) => m.id);
    const { data: seenRows } = await admin.from("processed_emails").select("message_id").in("message_id", ids);
    const seen = new Set((seenRows ?? []).map((r: any) => r.message_id));
    const fresh = messages.filter((m) => !seen.has(m.id));
    if (fresh.length === 0) return { ok: true, connected: true, scanned: 0, matched: 0, expired };

    const metaList = await Promise.all(
      fresh.map(({ id }) =>
        gmailGet(token, `/users/me/messages/${id}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date`)
          .then((msg: any) => ({ id, msg, error: null as Error | null }))
          .catch((error: Error) => ({ id, msg: null, error })),
      ),
    );

    let matched = 0;

    for (const { id, msg, error } of metaList) {
      if (error || !msg) continue;

      // Claim first: a unique violation means another worker already took it.
      const { error: claimError } = await admin.from("processed_emails").insert({ message_id: id, user_id: userId });
      if (claimError) continue;

      const headers: GmailHeader[] = msg.payload?.headers ?? [];
      const header = (name: string) =>
        headers.find((h) => h.name.toLowerCase() === name)?.value ?? "";
      const subject = header("subject");
      const from = header("from");
      if (!senderMatches(from)) continue;

      const amount = extractAmount(subject);
      if (amount === null) continue;

      const emailTimeMs = msg.internalDate
        ? Number(msg.internalDate)
        : header("date")
          ? Date.parse(header("date"))
          : Date.now();
      const emailTime = new Date(emailTimeMs).toISOString();
      const payerName = extractName(subject);

      const { data: alreadyUsed } = await admin
        .from("payment_links")
        .select("id")
        .eq("paid_email_id", id)
        .maybeSingle();
      if (alreadyUsed) continue;

      const { data: candidates } = await admin
        .from("payment_links")
        .select("id,order_id,payable_amount")
        .eq("user_id", userId)
        .eq("status", "active")
        .eq("payable_amount", amount)
        .lte("created_at", emailTime);

      if (!candidates || candidates.length !== 1) continue;

      const link = candidates[0];
      const { data: updated } = await admin
        .from("payment_links")
        .update({
          status: "paid",
          paid_at: emailTime,
          detected_at: new Date().toISOString(),
          payer_name: payerName,
          payer_email: from,
          paid_email_id: id,
          paid_count: 1,
        })
        .eq("id", link.id)
        .eq("status", "active")
        .is("paid_email_id", null)
        .select("id")
        .maybeSingle();

      if (!updated) continue;

      await admin.from("processed_emails").update({ link_id: link.id, amount }).eq("message_id", id);
      matched++;
    }

    return { ok: true, connected: true, scanned: fresh.length, matched, expired };
  } catch (e) {
    return {
      ok: false,
      connected: true,
      scanned: 0,
      matched: 0,
      expired,
      error: e instanceof Error ? e.message : "poll_failed",
    };
  }
}
