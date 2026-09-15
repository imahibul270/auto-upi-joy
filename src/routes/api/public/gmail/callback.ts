import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/gmail/callback")({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const url = new URL(request.url);
        const origin = `${url.protocol}//${url.host}`;
        const code = url.searchParams.get("code");
        const state = url.searchParams.get("state");
        const errParam = url.searchParams.get("error");

        if (errParam) return back(origin, `error=${encodeURIComponent(errParam)}`);
        if (!code || !state) return back(origin, "error=missing_code");

        const { verifyState } = await import("@/lib/gmail-state.server");
        const verified = await verifyState(state);
        if (!verified) return back(origin, "error=invalid_state");

        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const admin = supabaseAdmin as any;
        const { data: row } = await admin
          .from("gmail_connections")
          .select("oauth_client_id,oauth_client_secret")
          .eq("user_id", verified.userId)
          .maybeSingle();

        if (!row?.oauth_client_id || !row?.oauth_client_secret) return back(origin, "error=no_credentials");

        const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            code,
            client_id: row.oauth_client_id,
            client_secret: row.oauth_client_secret,
            redirect_uri: `${origin}/api/public/gmail/callback`,
            grant_type: "authorization_code",
          }),
        });
        if (!tokenRes.ok) return back(origin, "error=token_exchange_failed");

        const tok = (await tokenRes.json()) as {
          access_token: string;
          refresh_token?: string;
          expires_in: number;
          scope: string;
        };

        let email: string | null = null;
        try {
          const userInfo = await fetch("https://www.googleapis.com/oauth2/v2/userinfo", {
            headers: { Authorization: `Bearer ${tok.access_token}` },
          });
          if (userInfo.ok) email = ((await userInfo.json()) as { email?: string }).email ?? null;
        } catch {
          // non-fatal
        }

        const { error } = await admin
          .from("gmail_connections")
          .update({
            access_token: tok.access_token,
            ...(tok.refresh_token ? { refresh_token: tok.refresh_token } : {}),
            token_expires_at: new Date(Date.now() + (tok.expires_in - 60) * 1000).toISOString(),
            scope: tok.scope,
            email,
            status: "connected",
            connected_at: new Date().toISOString(),
          })
          .eq("user_id", verified.userId);

        if (error) return back(origin, "error=db_update_failed");
        return back(origin, "gmail=connected");
      },
    },
  },
});

function back(origin: string, query: string) {
  return new Response(null, { status: 302, headers: { Location: `${origin}/connect-accounts?${query}` } });
}
