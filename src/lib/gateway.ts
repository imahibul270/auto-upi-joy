import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export type Provider = "phonepe" | "paytm";

export const PROVIDERS: { value: Provider; label: string; hint: string }[] = [
  { value: "phonepe", label: "PhonePe", hint: "Business alerts from noreply@phonepe.com" },
  { value: "paytm", label: "Paytm", hint: "Business alerts from no-reply@paytm.com" },
];

export type MerchantAccount = {
  provider: Provider;
  upi_id: string;
  payee_name: string;
  email: string;
  connected: boolean;
  connected_at: string | null;
};

export async function fetchMerchantAccounts(): Promise<MerchantAccount[]> {
  const { data, error } = await supabase.rpc("list_merchant_accounts");
  if (error) throw error;
  return (data as unknown as MerchantAccount[]) ?? [];
}

/** Live connect-account state, refreshed so the badge stays real time. */
export function useMerchantAccounts() {
  return useQuery({
    queryKey: ["merchant-accounts"],
    queryFn: fetchMerchantAccounts,
    refetchInterval: 8000,
    refetchOnWindowFocus: true,
  });
}

export async function saveMerchantAccount(input: { provider: Provider; upiId: string; payeeName?: string }) {
  const { data, error } = await supabase.rpc("save_merchant_account", {
    _provider: input.provider,
    _upi_id: input.upiId,
    _payee_name: input.payeeName ?? "",
  });
  if (error) throw error;
  return data as unknown as MerchantAccount;
}

export async function connectMerchantAccount(input: { provider: Provider; email: string; appPassword: string }) {
  const { data, error } = await supabase.rpc("connect_merchant_account", {
    _provider: input.provider,
    _email: input.email,
    _app_password: input.appPassword,
  });
  if (error) throw error;
  return data as unknown as MerchantAccount;
}

export async function disconnectMerchantAccount(provider: Provider) {
  const { error } = await supabase.rpc("disconnect_merchant_account", { _provider: provider });
  if (error) throw error;
}

export type ApiKeyRow = {
  id: string;
  label: string;
  key_prefix: string;
  webhook_secret: string;
  active: boolean;
  last_used_at: string | null;
  created_at: string;
};

export async function fetchApiKeys(): Promise<ApiKeyRow[]> {
  const { data, error } = await supabase
    .from("api_keys")
    .select("id,label,key_prefix,webhook_secret,active,last_used_at,created_at")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as ApiKeyRow[];
}

export function useApiKeys() {
  return useQuery({ queryKey: ["api-keys"], queryFn: fetchApiKeys });
}

export async function issueApiKey(label: string) {
  const { data, error } = await supabase.rpc("issue_api_key", { _label: label });
  if (error) throw error;
  return data as unknown as { id: string; api_key: string; key_prefix: string; webhook_secret: string };
}

export async function revokeApiKey(id: string) {
  const { error } = await supabase.rpc("revoke_api_key", { _id: id });
  if (error) throw error;
}

export type PaymentLinkRow = {
  id: string;
  order_id: string;
  slug: string;
  customer_name: string;
  amount: number;
  payable_amount: number;
  link_type: string;
  status: "active" | "paid" | "expired";
  clicks: number;
  paid_count: number;
  paid_at: string | null;
  detected_at: string | null;
  expires_at: string;
  payer_name: string | null;
  payer_email: string | null;
  created_at: string;
};

export async function fetchPaymentLinks(): Promise<PaymentLinkRow[]> {
  const { data, error } = await supabase
    .from("payment_links")
    .select("id,order_id,slug,customer_name,amount,payable_amount,link_type,status,clicks,paid_count,paid_at,detected_at,expires_at,payer_name,payer_email,created_at")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as PaymentLinkRow[];
}

/** Links refresh on an interval so a detected payment flips to Paid live. */
export function usePaymentLinks() {
  return useQuery({
    queryKey: ["payment-links"],
    queryFn: fetchPaymentLinks,
    refetchInterval: 3000,
    refetchOnWindowFocus: true,
  });
}

/** Only links that can still be paid. */
export function useActiveLinks() {
  const query = usePaymentLinks();
  return { ...query, rows: (query.data ?? []).filter((row) => row.status === "active") };
}

/** Settled links — these are the transactions. */
export function useTransactions() {
  const query = usePaymentLinks();
  return { ...query, rows: (query.data ?? []).filter((row) => row.status !== "active") };
}

/** How long detection took, in seconds. */
export function detectionSeconds(row: PaymentLinkRow): number | null {
  if (!row.paid_at || !row.detected_at) return null;
  const seconds = Math.round((Date.parse(row.detected_at) - Date.parse(row.paid_at)) / 1000);
  return seconds >= 0 ? seconds : null;
}

export function formatTime(value: string) {
  return new Date(value).toLocaleString("en-IN", {
    day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit",
  });
}

export async function createPaymentLink(input: { amount: number; customerName: string }) {
  const { data, error } = await supabase.rpc("create_payment_link", {
    _amount: input.amount,
    _customer_name: input.customerName,
  });
  if (error) throw error;
  return data as unknown as { order_id: string; slug: string; amount: number; payable_amount: number };
}

export async function expirePaymentLink(id: string) {
  const { error } = await supabase.rpc("expire_payment_link", { _id: id });
  if (error) throw error;
}

export function paymentLinkUrl(slug: string) {
  const origin = typeof window === "undefined" ? "" : window.location.origin;
  return `${origin}/pay/${slug}`;
}

export function formatInr(value: number) {
  return `₹${Number(value).toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export function formatDate(value: string) {
  return new Date(value).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}
