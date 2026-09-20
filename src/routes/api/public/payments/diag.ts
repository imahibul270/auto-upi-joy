import { createFileRoute } from "@tanstack/react-router";

// TEMPORARY diagnostic endpoint (removed after debugging).
export const Route = createFileRoute("/api/public/payments/diag")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const body = (await request.json()) as { user_id?: string };
        const userId = (body.user_id ?? "").trim();
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const { fetchRecentMessages, parseMessage } = await import("@/lib/imap.server");
        const { data: acc } = await (supabaseAdmin.from("merchant_accounts") as any)
          .select("email,app_password")
          .eq("user_id", userId)
          .eq("connected", true)
          .maybeSingle();
        if (!acc) return Response.json({ ok: false, error: "no_account" });
        try {
          const messages = await fetchRecentMessages({
            host: "imap.gmail.com",
            user: acc.email,
            password: acc.app_password,
            sinceDays: 2,
            limit: 25,
          });
          const list = messages.map((m) => {
            const { headers } = parseMessage(m.raw);
            return { uid: m.uid, from: headers["from"] ?? "", subject: headers["subject"] ?? "", date: headers["date"] ?? "" };
          });
          return Response.json({ ok: true, count: list.length, list });
        } catch (error) {
          return Response.json({ ok: false, error: error instanceof Error ? error.message : "failed" });
        }
      },
    },
  },
});
