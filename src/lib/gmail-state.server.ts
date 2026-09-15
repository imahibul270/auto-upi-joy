// Signed OAuth state for the Gmail connect flow (server only).

function stateSecret(): string {
  const secret = process.env['SUPABASE_SERVICE_ROLE_KEY'] ?? process.env['GMAIL_STATE_SECRET'];
  if (!secret) throw new Error("Missing server secret for Gmail state signing");
  return secret;
}

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]!);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromB64url(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

async function hmac(message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(stateSecret()),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return b64url(new Uint8Array(sig));
}

export async function signState(userId: string): Promise<string> {
  const nonce = b64url(crypto.getRandomValues(new Uint8Array(12)));
  const payload = `${userId}.${Date.now()}.${nonce}`;
  const sig = await hmac(payload);
  return `${b64url(new TextEncoder().encode(payload))}.${sig}`;
}

export async function verifyState(state: string): Promise<{ userId: string } | null> {
  try {
    const [payloadB64, sig] = state.split(".");
    if (!payloadB64 || !sig) return null;
    const payload = new TextDecoder().decode(fromB64url(payloadB64));
    if ((await hmac(payload)) !== sig) return null;
    const [userId, ts] = payload.split(".");
    if (!userId || !ts) return null;
    if (Date.now() - Number(ts) > 15 * 60 * 1000) return null;
    return { userId };
  } catch {
    return null;
  }
}
