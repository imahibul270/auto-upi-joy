import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

/** Runs the detection engine for the signed-in merchant (dashboard / lists). */
export const pollMyPayments = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { pollPaymentsForUser } = await import("@/lib/mail-poll.server");
    return pollPaymentsForUser(context.userId);
  });

/**
 * Connects the alert mailbox only after a real IMAP sign in succeeds, so a wrong
 * or expired app password can never look "Connected" while detection is dead.
 */
export const connectMailbox = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data) =>
    z
      .object({
        provider: z.enum(["phonepe", "paytm"]),
        email: z.string().trim().email(),
        appPassword: z.string().trim().min(8),
      })
      .parse(data),
  )
  .handler(async ({ data, context }) => {
    const email = data.email.trim().toLowerCase();
    const password = data.appPassword.replace(/\s+/g, "");

    const { fetchRecentMessages } = await import("@/lib/imap.server");
    const { mailboxProblem } = await import("@/lib/mail-poll.server");
    try {
      await fetchRecentMessages({
        host: mailHost(email),
        user: email,
        password,
        sinceDays: 1,
        limit: 1,
        fromFilter: "phonepe",
        timeoutMs: 20_000,
      });
    } catch (error) {
      throw new Error(mailboxProblem(error instanceof Error ? error.message : "failed"));
    }

    const { error } = await context.supabase.rpc("connect_merchant_account", {
      _provider: data.provider,
      _email: email,
      _app_password: password,
    });
    if (error) throw new Error(error.message);

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    await (supabaseAdmin.from("merchant_accounts") as any)
      .update({ mail_error: null, mail_error_at: null, mail_ok_at: new Date().toISOString() })
      .eq("user_id", context.userId)
      .eq("provider", data.provider);

    return { connected: true, email };
  });

function mailHost(email: string): string {
  const domain = email.split("@")[1]?.toLowerCase() ?? "";
  if (domain.includes("outlook") || domain.includes("hotmail") || domain.includes("live")) return "outlook.office365.com";
  if (domain.includes("yahoo")) return "imap.mail.yahoo.com";
  if (domain.includes("zoho")) return "imap.zoho.in";
  return "imap.gmail.com";
}
