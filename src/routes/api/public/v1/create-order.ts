import { createFileRoute } from "@tanstack/react-router";
import { createHash } from "crypto";

function json(body: unknown, status = 200) {
  return Response.json(body, {
    status,
    headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "*" },
  });
}

export const Route = createFileRoute("/api/public/v1/create-order")({
  server: {
    handlers: {
      OPTIONS: async () =>
        new Response(null, {
          status: 204,
          headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "*",
          },
        }),
      POST: async ({ request }) => {
        const apiKey = (request.headers.get("x-api-key") ?? "").trim();
        if (!apiKey.startsWith("aupi_live_")) return json({ ok: false, error: "invalid_api_key" }, 401);

        let body: { amount?: number | string; customer_name?: string; link_type?: string; webhook_url?: string } = {};
        try {
          body = (await request.json()) as typeof body;
        } catch {
          return json({ ok: false, error: "invalid_json" }, 400);
        }

        const amount = Number(body.amount);
        if (!Number.isFinite(amount) || amount <= 0) return json({ ok: false, error: "invalid_amount" }, 400);

        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const hash = createHash("sha256").update(apiKey).digest("hex");
        const { data: key } = await (supabaseAdmin.from("api_keys") as any)
          .select("id,user_id,active")
          .eq("key_hash", hash)
          .eq("active", true)
          .maybeSingle();
        if (!key?.user_id) return json({ ok: false, error: "invalid_api_key" }, 401);

        const { data, error } = await (supabaseAdmin as any).rpc("api_create_payment_link", {
          _user: key.user_id,
          _amount: amount,
          _customer_name: (body.customer_name ?? "").toString().slice(0, 120),
          _link_type: body.link_type === "reusable" ? "reusable" : "one_time",
        });
        if (error) return json({ ok: false, error: error.message }, 400);

        await (supabaseAdmin.from("api_keys") as any)
          .update({ last_used_at: new Date().toISOString() })
          .eq("id", key.id);

        const origin = new URL(request.url).origin;
        const link = data as { slug: string; order_id: string; amount: number; payable_amount: number };

        const webhookUrl = (body.webhook_url ?? "").toString().trim();
        if (/^https:\/\//i.test(webhookUrl)) {
          await (supabaseAdmin.from("payment_links") as any)
            .update({ webhook_url: webhookUrl.slice(0, 500) })
            .eq("order_id", link.order_id)
            .eq("user_id", key.user_id);
        }
        return json({ ok: true, ...link, payment_url: `${origin}/pay/${link.slug}` });
      },
    },
  },
});
