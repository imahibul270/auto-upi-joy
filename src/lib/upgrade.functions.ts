import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

export const PRO_PRICE = 299;

/** Reads the live Pro price set from the admin panel. */
async function proPrice(): Promise<number> {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data } = await (supabaseAdmin as any).rpc("get_pro_price");
  const price = Number(data);
  return Number.isFinite(price) && price > 0 ? price : PRO_PRICE;
}

function safeOrigin(origin: string): string | null {
  try {
    const url = new URL(origin);
    const host = url.hostname;
    const ok =
      host === "localhost" ||
      host === "127.0.0.1" ||
      host.endsWith(".lovable.app") ||
      host.endsWith("autoupi.in") ||
      host.endsWith("autoupi.shop");
    return ok ? url.origin : null;
  } catch {
    return null;
  }
}

/** Creates a real Auto Upi payment link for the ₹299 Pro plan. */
export const startProUpgrade = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data) => z.object({ origin: z.string().min(1) }).parse(data))
  .handler(async ({ data, context }) => {
    const origin = safeOrigin(data.origin);
    if (!origin) throw new Error("Invalid origin");

    const apiKey = process.env["AUTOUPI_PLATFORM_API_KEY"];
    if (!apiKey) throw new Error("Payment gateway is not configured yet.");

    const response = await fetch(`${origin}/api/public/v1/create-order`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-api-key": apiKey },
      body: JSON.stringify({
        amount: PRO_PRICE,
        customer_name: (context.claims as { email?: string } | null)?.email ?? "Auto Upi user",
        link_type: "one_time",
        webhook_url: `${origin}/api/public/plan-webhook`,
      }),
    });
    const body = (await response.json()) as {
      ok?: boolean;
      error?: string;
      order_id?: string;
      slug?: string;
      payable_amount?: number;
      payment_url?: string;
    };
    if (!body.ok || !body.order_id || !body.slug) {
      throw new Error(body.error === "QUOTA_EXCEEDED" ? "Gateway account limit reached." : (body.error ?? "Could not start payment"));
    }

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    await (supabaseAdmin.from("plan_orders") as any).insert({
      user_id: context.userId,
      order_id: body.order_id,
      slug: body.slug,
      amount: PRO_PRICE,
    });

    return {
      order_id: body.order_id,
      slug: body.slug,
      payable_amount: Number(body.payable_amount ?? PRO_PRICE),
      payment_url: body.payment_url ?? `${origin}/pay/${body.slug}`,
    };
  });

/** Polls the upgrade order; activates Pro the moment the payment is settled. */
export const checkProUpgrade = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data) => z.object({ order_id: z.string().min(1).max(64) }).parse(data))
  .handler(async ({ data, context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const admin = supabaseAdmin as any;

    const { data: order } = await admin
      .from("plan_orders")
      .select("order_id,status,user_id")
      .eq("order_id", data.order_id)
      .eq("user_id", context.userId)
      .maybeSingle();
    if (!order) return { status: "not_found" as const };
    if (order.status === "paid") return { status: "paid" as const };

    const { data: link } = await admin
      .from("payment_links")
      .select("status")
      .eq("order_id", data.order_id)
      .maybeSingle();

    if (link?.status === "paid") {
      await admin.rpc("complete_plan_order", { _order_id: data.order_id });
      return { status: "paid" as const };
    }
    return { status: link?.status === "expired" ? ("expired" as const) : ("pending" as const) };
  });
