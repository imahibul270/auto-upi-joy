import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const GMAIL_SCOPE = "https://www.googleapis.com/auth/gmail.readonly";

export const getGmailStatus = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data } = await (supabaseAdmin.from("gmail_connections") as any)
      .select("email,status,connected_at,last_polled_at,oauth_client_id,refresh_token")
      .eq("user_id", context.userId)
      .maybeSingle();

    return {
      hasCredentials: Boolean(data?.oauth_client_id),
      connected: data?.status === "connected" && Boolean(data?.refresh_token),
      needsReconnect: data?.status === "needs_reconnect",
      email: (data?.email as string | null) ?? null,
      connectedAt: (data?.connected_at as string | null) ?? null,
      lastPolledAt: (data?.last_polled_at as string | null) ?? null,
    };
  });

export const saveGmailCredentials = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { clientId: string; clientSecret: string }) =>
    z
      .object({
        clientId: z.string().trim().min(10).max(300),
        clientSecret: z.string().trim().min(5).max(300),
      })
      .parse(d),
  )
  .handler(async ({ data, context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const admin = supabaseAdmin as any;
    const { data: existing } = await admin
      .from("gmail_connections")
      .select("user_id,refresh_token")
      .eq("user_id", context.userId)
      .maybeSingle();

    const payload = {
      oauth_client_id: data.clientId,
      oauth_client_secret: data.clientSecret,
      status: existing?.refresh_token ? "connected" : "credentials_only",
    };

    const { error } = existing
      ? await admin.from("gmail_connections").update(payload).eq("user_id", context.userId)
      : await admin.from("gmail_connections").insert({ user_id: context.userId, ...payload });
    if (error) throw new Error(error.message);
    return { ok: true };
  });

export const startGmailConnect = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: { origin: string }) => z.object({ origin: z.string().url() }).parse(d))
  .handler(async ({ data, context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { signState } = await import("@/lib/gmail-state.server");
    const { data: row } = await (supabaseAdmin.from("gmail_connections") as any)
      .select("oauth_client_id")
      .eq("user_id", context.userId)
      .maybeSingle();

    const clientId = row?.oauth_client_id as string | undefined;
    if (!clientId) throw new Error("SAVE_CREDENTIALS_FIRST");

    const params = new URLSearchParams({
      client_id: clientId,
      redirect_uri: `${data.origin.replace(/\/$/, "")}/api/public/gmail/callback`,
      response_type: "code",
      scope: `${GMAIL_SCOPE} https://www.googleapis.com/auth/userinfo.email`,
      access_type: "offline",
      prompt: "consent",
      include_granted_scopes: "true",
      state: await signState(context.userId),
    });

    return { url: `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}` };
  });

export const disconnectGmail = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await (supabaseAdmin.from("gmail_connections") as any)
      .update({
        access_token: null,
        refresh_token: null,
        token_expires_at: null,
        email: null,
        connected_at: null,
        status: "credentials_only",
      })
      .eq("user_id", context.userId);
    if (error) throw new Error(error.message);
    return { ok: true };
  });

/** Runs the detection engine for the signed-in merchant (dashboard / lists). */
export const pollMyPayments = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { pollPaymentsForUser } = await import("@/lib/gmail-poll.server");
    return pollPaymentsForUser(context.userId);
  });
