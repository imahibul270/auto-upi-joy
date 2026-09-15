import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

/** Runs the detection engine for the signed-in merchant (dashboard / lists). */
export const pollMyPayments = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { pollPaymentsForUser } = await import("@/lib/mail-poll.server");
    return pollPaymentsForUser(context.userId);
  });
