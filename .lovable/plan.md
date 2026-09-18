# Plan renewal reminders + notification bell

## What the user gets

**Renew before expiry**
- Jab Pro plan ke 3 din ya usse kam bache ho, Plan page par usi jagah (Pro card) par **Renew Pro** button dikhega — abhi wahan sirf "Upgrade" tab dikhta hai jab plan free ho.
- Plan expire ho jane ke baad wahi jagah "Upgrade to Pro" dikhati rahegi (jaisa abhi hai).
- Pehle se renew karne par naya 30-din ka time current plan ke **khatam hone ke baad** se juड़ta hai (yeh database me already aise hi hai — GREATEST(expires_at, now()) + 30 days), isliye beech me koi rukavat nahi hogi.

**Notification bell (top right)**
- Bell par unread count (1, 2, 3…) dikhega aur bell par halka pulse animation chalega jab unread ho.
- Click karne par right side se ek panel smooth animation ke saath khulega; dubara click / close / bahar click par smooth band hoga.
- Message English me:
  - Expiry se 3 din pehle: "Your Pro plan expires on 21 Sep 2026. Renew now so your payment links never stop." + **Renew** button → Plan page.
  - Expiry ke baad: "Your Pro plan has expired. Upgrade to Pro to keep generating QR codes." + **Upgrade** button → Plan page.
- Har din 3 baar aati hai: subah **8:00**, dopahar **12:00**, shaam **5:00** (device time). Slot ka time nikalte hi notification apne aap add ho jati hai, page reload ka intezaar nahi.
- Panel khol lene par woh notifications read ho jati hain aur count 0 ho jata hai; agla slot aane par phir se count badhega.
- Renew/upgrade ho jane par (plan pro + 3 din se zyada bacha) reminders aana band ho jati hain.
- Free plan users ko ye reminders nahi aate.

## Technical details

- `src/lib/quota.ts`: add `RENEW_WINDOW_DAYS = 3` and a helper `planNeedsRenewal(quota)` returning `{ expiringSoon, expired }` from the existing server-side `seconds_left` / `days_left` (no DB change).
- New `src/lib/plan-notifications.ts`: pure helpers that turn `quota` + current time into notification items with stable ids (`renew-<YYYY-MM-DD>-<08|12|17>` / `expired-<YYYY-MM-DD>-<slot>`), only for slots already passed today plus the last 2 days, capped at ~10 items.
- New `src/components/console/NotificationBell.tsx`: bell button + count badge + slide-in panel. Read state stored in `localStorage` under `autoupi:notif-read:<user.id>` (a set of ids), so it is per user and per browser; a `useQrQuota()` subscription plus a 60s ticker keeps it live. No table, no server function.
- `src/components/console/ConsoleLayout.tsx`: replace the existing static bell button with `<NotificationBell user={user} />`. Nothing else in the layout changes.
- `src/routes/_authenticated/plan.tsx`: Pro card CTA condition changes from `!isPro` to `!isPro || expiringSoon` with label "Renew Pro for ₹X" when already Pro; the same existing `upgrade()` flow (create order → new tab → poll/message → activate) is reused unchanged.
- `src/styles.css`: add classes for the badge, pulse animation, slide-in panel/overlay and notification rows, in the existing dark-green/lime token style.
- No changes to payments, detection, webhooks, admin, docs, pricing or the database.
