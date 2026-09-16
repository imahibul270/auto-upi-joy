import { createClient } from "@supabase/supabase-js";
import type { Database } from "./types";

/**
 * A completely separate Supabase auth session for the /admin panel.
 * It uses its own storage key, so the admin login and a normal merchant login
 * can live side by side in the same browser without overwriting each other.
 */
function createAdminClient() {
  const url = import.meta.env["VITE_SUPABASE_URL"] as string;
  const key = import.meta.env["VITE_SUPABASE_PUBLISHABLE_KEY"] as string;

  return createClient<Database>(url, key, {
    global: {
      fetch: (input, init) => {
        const headers = new Headers(
          typeof Request !== "undefined" && input instanceof Request ? input.headers : undefined,
        );
        if (init?.headers) new Headers(init.headers).forEach((v, k) => headers.set(k, v));
        if ((key.startsWith("sb_publishable_") || key.startsWith("sb_secret_")) &&
            headers.get("Authorization") === `Bearer ${key}`) {
          headers.delete("Authorization");
        }
        headers.set("apikey", key);
        return fetch(input, { ...init, headers });
      },
    },
    auth: {
      storageKey: "autoupi-admin-auth",
      storage: typeof window === "undefined" ? undefined : window.localStorage,
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: false,
    },
  });
}

let _client: ReturnType<typeof createAdminClient> | undefined;

export const supabaseAdminAuth = new Proxy({} as ReturnType<typeof createAdminClient>, {
  get(_, prop, receiver) {
    if (!_client) _client = createAdminClient();
    return Reflect.get(_client, prop, receiver);
  },
});
