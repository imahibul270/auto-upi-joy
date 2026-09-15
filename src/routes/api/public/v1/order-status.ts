import { createFileRoute } from "@tanstack/react-router";
import { createHash } from "crypto";

function json(body: unknown, status = 200) {
  return Response.json(body, {
    status,
    headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "*" },
  });
}

export const Route = createFileRoute("/api/public/v1/order-status")({
  server: {
    handlers: {
      OPTIONS: async () =>
        new Response(null, {
          status: 204,
          headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Access-Control-Allow-Headers": "*",
          },
        }),
      GET: async ({ request }) => {
        const apiKey = (request.headers.get("x-api-key") ?? "").trim();
        if (!apiKey.startsWith("aupi_live_")) return json({ ok: false, error: "invalid_api_key" }, 401);

        const url = new URL(request.url);
        const orderId = (url.searchParams.get("order_id") ?? "").trim();
        if (!orderId) return json({ ok: false, error: "order_id_required" }, 400);

        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const hash = createHash("sha256").update(apiKey).digest("hex");
        const { data: key } = await (supabaseAdmin.from("api_keys") as any)
          .select("user_id")
          .eq("key_hash", hash)
          .eq("active", true)
          .maybeSingle();
        if (!key?.user_id) return json({ ok: false, error: "invalid_api_key" }, 401);

        const { data: row } = await (supabaseAdmin.from("payment_links") as any)
          .select("order_id,slug,customer_name,amount,payable_amount,status,paid_at,detected_at,payer_name,expires_at,created_at")
          .eq("user_id", key.user_id)
          .eq("order_id", orderId)
          .maybeSingle();
        if (!row) return json({ ok: false, error: "not_found" }, 404);

        return json({ ok: true, order: row });
      },
    },
  },
});
