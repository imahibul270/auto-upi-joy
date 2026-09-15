// Payment detection engine: reads PhonePe / Paytm alert emails over IMAP with
// the merchant's email + app password and settles the matching payment link.
// Server only — never import this from client code.
import { supabaseAdmin } from "@/integrations/supabase/client.server";
import { fetchRecentMessages, parseMessage } from "@/lib/imap.server";

// Only credit alerts from this exact PhonePe address may settle a payment.
const MONITOR_SENDERS = ["noreply@phonepe.com"];
const PAYTM_AMOUNT_RE = /Rs\.?\s*([0-9]+(?:\.[0-9]{1,2})?)\s+(?:paid|received|credited)/i;
const PHONEPE_AMOUNT_RE = /(?:Received|Payment of)\s*(?:₹|Rs\.?|INR)?\s*([0-9]+(?:\.[0-9]{1,2})?)/i;
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

function imapHostFor(email: string): string {
  const domain = email.split("@")[1]?.toLowerCase() ?? "";
  if (domain.includes("outlook") || domain.includes("hotmail") || domain.includes("live")) return "outlook.office365.com";
  if (domain.includes("yahoo")) return "imap.mail.yahoo.com";
  if (domain.includes("zoho")) return "imap.zoho.in";
  return "imap.gmail.com";
}

function extractAmount(text: string): number | null {
  const m = text.match(PAYTM_AMOUNT_RE) ?? text.match(PHONEPE_AMOUNT_RE) ?? text.match(GENERIC_AMOUNT_RE);
  return m?.[1] ? Number.parseFloat(m[1]) : null;
}

function extractName(text: string): string | null {
  for (const re of NAME_PATTERNS) {
    const found = text.match(re)?.[1]?.trim().replace(/\s+/g, " ");
    if (found && found.length >= 2 && found.length <= 60) return found;
  }
  return null;
}

function senderMatches(from: string): boolean {
  // Take the real address inside <> when present, else the whole header.
  const address = (from.match(/<([^>]+)>/)?.[1] ?? from).trim().toLowerCase();
  return MONITOR_SENDERS.includes(address);
}

/** Scan the merchant's mailbox and settle any matching pending payment link. */
export async function pollPaymentsForUser(userId: string): Promise<PollResult> {
  const admin = supabaseAdmin as any;

  const { data: expiredCount } = await admin.rpc("expire_stale_payment_links", { _user: userId });
  const expired = Number(expiredCount ?? 0);

  const { data: accounts } = await admin
    .from("merchant_accounts")
    .select("email,app_password,connected")
    .eq("user_id", userId)
    .eq("connected", true);

  const mailboxes = new Map<string, string>();
  for (const row of accounts ?? []) {
    if (row.email && row.app_password) mailboxes.set(String(row.email).toLowerCase(), String(row.app_password));
  }
  if (mailboxes.size === 0) return { ok: true, connected: false, scanned: 0, matched: 0, expired };

  let scanned = 0;
  let matched = 0;
  let lastError: string | undefined;

  for (const [email, password] of mailboxes) {
    try {
      const messages = await fetchRecentMessages({
        host: imapHostFor(email),
        user: email,
        password,
        sinceDays: 1,
        limit: 12,
      });

      for (const message of messages) {
        const { headers, text } = parseMessage(message.raw);
        const from = headers["from"] ?? "";
        if (!senderMatches(from)) continue;

        const messageId = (headers["message-id"] ?? `${email}:${message.uid}`).slice(0, 250);

        // Claim first: a unique violation means this email is already handled.
        const { error: claimError } = await admin
          .from("processed_emails")
          .insert({ message_id: messageId, user_id: userId });
        if (claimError) continue;

        scanned++;

        const haystack = `${headers["subject"] ?? ""} ${text}`.slice(0, 4000);
        const amount = extractAmount(haystack);
        if (amount === null) continue;

        const emailTime = new Date(headers["date"] ? Date.parse(headers["date"]) || Date.now() : Date.now()).toISOString();
        const payerName = extractName(haystack);

        const { data: alreadyUsed } = await admin
          .from("payment_links")
          .select("id")
          .eq("paid_email_id", messageId)
          .maybeSingle();
        if (alreadyUsed) continue;

        // Exactly one pending link may claim an amount — every active link of a
        // merchant carries a unique paise marker, so a plain/random payment of
        // the same rupee value can never settle an order.
        const exact = Number(amount.toFixed(2));
        // The alert email must be newer than the link (60s clock skew allowed).
        const createdBefore = new Date(Date.parse(emailTime) + 60_000).toISOString();
        const { data: candidates } = await admin
          .from("payment_links")
          .select("id,order_id,payable_amount")
          .eq("user_id", userId)
          .eq("status", "active")
          .eq("payable_amount", exact)
          .lte("created_at", createdBefore);

        if (!candidates || candidates.length !== 1) continue;
        if (Number(candidates[0].payable_amount) !== exact) continue;

        const link = candidates[0];
        const { data: updated } = await admin
          .from("payment_links")
          .update({
            status: "paid",
            paid_at: emailTime,
            detected_at: new Date().toISOString(),
            payer_name: payerName,
            payer_email: from,
            paid_email_id: messageId,
            paid_count: 1,
          })
          .eq("id", link.id)
          .eq("status", "active")
          .is("paid_email_id", null)
          .select("id")
          .maybeSingle();

        if (!updated) continue;

        await admin.from("processed_emails").update({ link_id: link.id, amount }).eq("message_id", messageId);
        matched++;
      }
    } catch (error) {
      lastError = error instanceof Error ? error.message : "poll_failed";
    }
  }

  return { ok: !lastError, connected: true, scanned, matched, expired, ...(lastError ? { error: lastError } : {}) };
}
