import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const emailSchema = z.string().trim().toLowerCase().email();

async function hashCode(email: string, code: string): Promise<string> {
  const bytes = new TextEncoder().encode(`${email}:${code}`);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Creates a fresh code for the address and mails it through the admin mailbox. */
async function issueOtp(email: string): Promise<void> {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { sendMail } = await import("@/lib/smtp.server");
  const admin = supabaseAdmin as any;

  const { data: source } = await admin.from("email_source").select("*").eq("id", "smtp").maybeSingle();
  if (!source) throw new Error("Email verification is not configured yet. Please contact support.");

  // Rate limit: one code per 45 seconds, 6 per hour for the same address.
  const hourAgo = new Date(Date.now() - 3_600_000).toISOString();
  const { data: recent } = await admin
    .from("signup_otps")
    .select("created_at")
    .eq("email", email)
    .gte("created_at", hourAgo)
    .order("created_at", { ascending: false });
  const list = (recent ?? []) as { created_at: string }[];
  if (list.length >= 6) throw new Error("Too many codes requested. Please try again later.");
  if (list[0] && Date.now() - Date.parse(list[0].created_at) < 45_000) {
    throw new Error("Please wait a few seconds before asking for a new code.");
  }

  const code = String(Math.floor(100000 + Math.random() * 900000));
  await admin.from("signup_otps").update({ consumed: true }).eq("email", email).eq("consumed", false);
  const { error } = await admin.from("signup_otps").insert({
    email,
    code_hash: await hashCode(email, code),
    expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
  });
  if (error) throw new Error("Could not start verification. Please try again.");

  await sendMail({
    host: source.host,
    port: source.port,
    user: source.email,
    password: source.app_password,
    to: email,
    subject: "AUTO UPI",
    text: `Your one time password is "${code}"`,
  });
}

/** Validates the code for the address, consuming it when correct. */
async function consumeOtp(email: string, code: string): Promise<void> {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const admin = supabaseAdmin as any;

  const { data: row } = await admin
    .from("signup_otps")
    .select("*")
    .eq("email", email)
    .eq("consumed", false)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!row) throw new Error("This code is no longer valid. Please request a new one.");
  if (Date.parse(row.expires_at) < Date.now()) throw new Error("This code has expired. Please request a new one.");
  if (row.attempts >= 5) throw new Error("Too many wrong attempts. Please request a new code.");

  if ((await hashCode(email, code)) !== row.code_hash) {
    await admin.from("signup_otps").update({ attempts: row.attempts + 1 }).eq("id", row.id);
    throw new Error("Incorrect code. Please check and try again.");
  }

  await admin.from("signup_otps").update({ consumed: true }).eq("id", row.id);
}

/** Sends a 6-digit one time password to the email entered on the register form. */
export const sendSignupOtp = createServerFn({ method: "POST" })
  .inputValidator((data) => z.object({ email: emailSchema }).parse(data))
  .handler(async ({ data }) => {
    await issueOtp(data.email);
    return { sent: true };
  });

/** Checks the code and creates the merchant account only when it matches. */
export const verifySignupOtp = createServerFn({ method: "POST" })
  .inputValidator((data) =>
    z
      .object({
        email: emailSchema,
        code: z.string().trim().regex(/^\d{6}$/, "Enter the 6 digit code"),
        password: z.string().min(8),
        name: z.string().trim().min(1).max(80),
        mobile: z.string().trim().min(6).max(20),
      })
      .parse(data),
  )
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const admin = supabaseAdmin as any;

    // One account per mobile number.
    const digits = data.mobile.replace(/\D/g, "").slice(-10);
    if (digits.length !== 10) throw new Error("Please enter a valid 10 digit mobile number.");
    const { data: taken } = await admin
      .from("profiles")
      .select("id")
      .or(`mobile.eq.+91${digits},mobile.eq.${digits},mobile.eq.91${digits}`)
      .limit(1);
    if ((taken ?? []).length > 0) {
      throw new Error("This mobile number is already registered. Please sign in with that account.");
    }

    await consumeOtp(data.email, data.code);


    const { data: created, error } = await admin.auth.admin.createUser({
      email: data.email,
      password: data.password,
      email_confirm: true,
      user_metadata: { full_name: data.name, mobile: data.mobile },
    });
    if (error) {
      const message = /already/i.test(error.message)
        ? "An account with this email already exists. Please sign in."
        : error.message;
      throw new Error(message);
    }

    const userId = created?.user?.id;
    if (userId) {
      await admin
        .from("profiles")
        .upsert({ id: userId, full_name: data.name, mobile: data.mobile, updated_at: new Date().toISOString() });
      await admin.from("email_verifications").upsert({ user_id: userId, verified_at: new Date().toISOString() });
    }

    return { verified: true };
  });

/** Tells the console whether the signed-in account has passed email verification. */
export const getVerificationState = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const admin = supabaseAdmin as any;
    const { data: row } = await admin
      .from("email_verifications")
      .select("user_id")
      .eq("user_id", context.userId)
      .maybeSingle();
    const { data: userData } = await admin.auth.admin.getUserById(context.userId);
    return { verified: Boolean(row), email: (userData?.user?.email ?? "") as string };
  });

/** Sends a one time password to the signed-in account's own email address. */
export const sendAccountOtp = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const admin = supabaseAdmin as any;
    const { data: userData } = await admin.auth.admin.getUserById(context.userId);
    const email = (userData?.user?.email ?? "").trim().toLowerCase();
    if (!email) throw new Error("No email address is linked to this account.");
    await issueOtp(email);
    return { sent: true, email };
  });

/** Marks the signed-in account verified once the emailed code matches. */
export const verifyAccountOtp = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data) => z.object({ code: z.string().trim().regex(/^\d{6}$/, "Enter the 6 digit code") }).parse(data))
  .handler(async ({ data, context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const admin = supabaseAdmin as any;
    const { data: userData } = await admin.auth.admin.getUserById(context.userId);
    const email = (userData?.user?.email ?? "").trim().toLowerCase();
    if (!email) throw new Error("No email address is linked to this account.");

    await consumeOtp(email, data.code);
    await admin
      .from("email_verifications")
      .upsert({ user_id: context.userId, verified_at: new Date().toISOString() });
    return { verified: true };
  });
