import { createFileRoute } from "@tanstack/react-router";

// Public detection trigger used by the payment page. It only ever polls the
// mailbox of the merchant who owns the given payment link.
export const Route = createFileRoute("/api/public/payments/poll")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        let slug = "";
        try {
          const body = (await request.json()) as { slug?: string };
          slug = (body.slug ?? "").trim();
        } catch {
          slug = "";
        }
        if (!slug || slug.length > 64) return Response.json({ ok: false, error: "bad_request" }, { status: 400 });

        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const { data: link } = await (supabaseAdmin.from("payment_links") as any)
          .select("user_id")
          .eq("slug", slug)
          .maybeSingle();

        if (!link?.user_id) return Response.json({ ok: false, error: "not_found" }, { status: 404 });

        const { pollPaymentsForUser } = await import("@/lib/mail-poll.server");
        const result = await pollPaymentsForUser(link.user_id);
        return Response.json({ ok: result.ok, matched: result.matched, connected: result.connected });
      },
    },
  },
});
