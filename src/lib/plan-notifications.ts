import type { QrQuota } from "@/lib/quota";
import { RENEW_WINDOW_DAYS, planTimeLeft } from "@/lib/quota";

/** Reminder slots: 8:00, 12:00 and 17:00 local time. */
export const NOTIFY_HOURS = [8, 12, 17];

export type PlanNotification = {
  id: string;
  kind: "renew" | "expired";
  title: string;
  body: string;
  action: string;
  at: Date;
};

function dayKey(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function formatDate(value: string | null) {
  if (!value) return "soon";
  return new Date(value).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

/**
 * Builds the reminder list for the signed-in user from their live plan.
 * Only slots that have already passed (today and the previous 2 days) appear.
 */
export function buildPlanNotifications(quota: QrQuota | undefined | null, now = new Date()): PlanNotification[] {
  if (!quota) return [];

  const left = planTimeLeft(quota);
  const isPro = quota.plan === "pro";
  const expired = isPro ? left.seconds <= 0 : Boolean(quota.period_end) && new Date(quota.period_end ?? 0).getTime() <= now.getTime();
  const expiringSoon = isPro && left.seconds > 0 && left.days <= RENEW_WINDOW_DAYS;
  if (!expired && !expiringSoon) return [];

  const kind: PlanNotification["kind"] = expired ? "expired" : "renew";
  const title = expired ? "Your plan has expired" : "Your plan is expiring soon";
  const body = expired
    ? "Your Pro plan has expired. Upgrade to Pro to keep generating QR codes and payment links."
    : `Your Pro plan expires on ${formatDate(quota.period_end)}. Renew now so your payment links never stop.`;
  const action = expired ? "Upgrade" : "Renew";

  const items: PlanNotification[] = [];
  for (let back = 0; back < 3; back += 1) {
    const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() - back);
    for (const hour of NOTIFY_HOURS) {
      const at = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, 0, 0, 0);
      if (at.getTime() > now.getTime()) continue;
      items.push({
        id: `${kind}-${dayKey(day)}-${String(hour).padStart(2, "0")}`,
        kind,
        title,
        body,
        action,
        at,
      });
    }
  }

  return items.sort((a, b) => b.at.getTime() - a.at.getTime()).slice(0, 10);
}

export function relativeTime(at: Date, now = new Date()) {
  const mins = Math.max(Math.floor((now.getTime() - at.getTime()) / 60000), 0);
  if (mins < 60) return `${mins} min ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours} hr ago`;
  const days = Math.floor(hours / 24);
  return `${days} ${days === 1 ? "day" : "days"} ago`;
}
