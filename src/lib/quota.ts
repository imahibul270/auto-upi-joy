import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

/** Shown on the Plan page for custom / enterprise requests. */
export const SALES_CONTACT_PHONE = "+91 84720 28929";
export const SALES_WHATSAPP_URL =
  "https://wa.me/918472028929?text=" +
  encodeURIComponent("Hello Auto Upi, I want to know about a custom plan.");

export const PRO_PRICE_INR = 299;
export const FREE_QR_LIMIT = 3;
export const PRO_QR_LIMIT = 3000;

export type QrQuota = {
  plan: "free" | "pro";
  limit: number;
  used: number;
  remaining: number;
  period_start: string | null;
  period_end: string | null;
  price_inr: number;
  can_generate: boolean;
};

export async function fetchQrQuota(): Promise<QrQuota> {
  const { data, error } = await supabase.rpc("get_qr_quota");
  if (error) throw error;
  return data as unknown as QrQuota;
}

/** Live Pro plan price, controlled by the admin panel. */
export async function fetchProPrice(): Promise<number> {
  const { data, error } = await supabase.rpc("get_pro_price" as never);
  if (error) throw error;
  return Number(data ?? PRO_PRICE_INR);
}

export function useProPrice() {
  return useQuery({
    queryKey: ["pro-price"],
    queryFn: fetchProPrice,
    refetchInterval: 8000,
    refetchOnWindowFocus: true,
    initialData: PRO_PRICE_INR,
  });
}

/** Live plan + usage for the signed-in user. */
export function useQrQuota() {
  return useQuery({
    queryKey: ["qr-quota"],
    queryFn: fetchQrQuota,
    refetchInterval: 8000,
    refetchOnWindowFocus: true,
  });
}

/**
 * Creates a QR. The quota check lives inside the database function, so a
 * client cannot bypass it — there is no direct insert permission on qr_codes.
 */
export async function generateQr(input: { payload: string; label?: string; upiId?: string; amount?: number | null }) {
  const { data, error } = await supabase.rpc("generate_qr", {
    _payload: input.payload,
    _label: input.label ?? "",
    _upi_id: input.upiId ?? "",
    ...(typeof input.amount === "number" ? { _amount: input.amount } : {}),
  });
  if (error) {
    if (error.message.includes("QUOTA_EXCEEDED")) {
      throw new Error("QUOTA_EXCEEDED");
    }
    throw error;
  }
  return data as unknown as { id: string; payload: string; used: number; limit: number; remaining: number };
}

export function daysLeft(periodEnd: string | null) {
  if (!periodEnd) return 0;
  const ms = new Date(periodEnd).getTime() - Date.now();
  return Math.max(Math.ceil(ms / 86400000), 0);
}
