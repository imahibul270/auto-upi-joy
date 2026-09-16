import { createFileRoute } from "@tanstack/react-router";
import { createHmac, timingSafeEqual } from "crypto";

/**
 * Auto Upi's own gateway calls this endpoint after a Pro plan payment is
 * settled. The signature is verified before the subscription is activated.
 */
export const Route = createFileRoute("/api/public/plan-webhook")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const secret = process.env["AUTOUPI_PLATFORM_WEBHOOK_SECRET"];
        if (!secret) return new Response("not configured", { status: 500 });

        const header = request.headers.get("x-autoupi-signature") ?? "";
        const body = await request.text();

        const timestamp = /t=(\d+)/.exec(header)?.[1] ?? "";
        const provided = /v1=([a-f0-9]+)/i.exec(header)?.[1] ?? "";
        if (!timestamp || !provided) return new Response("missing signature", { status: 401 });

        // Reject replays older than 5 minutes.
        if (Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) {
          return new Response("stale signature", { status: 401 });
        }

        const expected = createHmac("sha256", secret).update(`${timestamp}.${body}`).digest("hex");
        const a = Buffer.from(provided.toLowerCase());
        const b = Buffer.from(expected);
        if (a.length !== b.length || !timingSafeEqual(a, b)) {
          return new Response("invalid signature", { status: 401 });
        }

        let payload: { event?: string; order_id?: string; status?: string } = {};
        try {
          payload = JSON.parse(body) as typeof payload;
        } catch {
          return new Response("invalid json", { status: 400 });
        }
        if (payload.event !== "payment.paid" || !payload.order_id) {
          return new Response("ignored", { status: 200 });
        }

        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        await (supabaseAdmin as any).rpc("complete_plan_order", { _order_id: payload.order_id });
        return Response.json({ ok: true });
      },
    },
  },
});
