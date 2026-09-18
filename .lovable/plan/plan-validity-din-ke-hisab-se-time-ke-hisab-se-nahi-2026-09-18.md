# Plan validity: din ke hisab se (time ke hisab se nahi)

## Abhi kaise chal raha hai (verified)

Abhi validity **exact time** se chalti hai. Database me plan lene ke waqt ka time + 30 din store hota hai.
Example (aaj ka real data): ek user ne 18 Sep 10:49 AM (IST) par liya, to uska plan **18 Oct 10:49 AM** par khatam hoga — poore 30×24 ghante.
"Days left" bache hue ghanton ko 24 se divide karke neeche wala pura number dikhata hai, isliye lene ke baad kuch ghante me hi 30 se 29 ho jata hai.

## Aap kya chahte hain

Din ke hisab se ginti: din raat 12 baje khatam hota hai, ghadi ke time se nahi.
Naya niyam: aaj 10 baje plan liya to plan **30 din baad wali raat 12 baje** khatam hoga.

```text
Kharida: 18 Sep, 10:00 AM
Khatam:  18 Oct, 12:00 AM (raat 12, yani 17 Oct ki raat ke baad)
18 Sep bhar   -> 30 days left
19 Sep bhar   -> 29 days left
17 Oct bhar   -> 1 day left
18 Oct 12 AM  -> Expired
```

Poore din ka fayda milta hai — jis din liya wo din poora count hota hai, aur aakhri din bhi raat 12 tak chalta hai.

## Kya-kya badlega

- Plan activate hone par khatam hone ka waqt hamesha **raat 12 baje (India time)** set hoga.
- Pehle se renew karne par bhi nayi 30 din current khatam hone wali raat 12 se aage judegi — beech me rukawat nahi.
- Admin panel se manual plan dene par bhi yahi niyam (N din = N poore din, raat 12 par khatam).
- "Days left" ab calendar dinon se gina jayega, isliye poore din ke liye number same rahega aur raat 12 baje 1 kam hoga. Aakhri din par abhi ki tarah ghante/minute dikhega.
- Jo purane Pro users abhi chal rahe hain, unka khatam hone ka waqt uske apne din ki raat 12 tak badha diya jayega (kisi ka time kam nahi hoga, thoda badhega).

## Technical details

- Nayi migration:
  - `activate_pro_subscription`: `expires_at = (date_trunc('day', GREATEST(expires_at, now()) AT TIME ZONE 'Asia/Kolkata') + interval '30 days' + interval '1 day') AT TIME ZONE 'Asia/Kolkata'` (renew ke liye GREATEST base bana rahega, aur ek hi din par do baar renew na gine iske liye base ka din pehle round hoga).
  - `admin_set_plan`: pro path me wahi IST-midnight rounding `_days` ke saath.
  - `get_qr_quota`: `days_left` ab `(expires_at IST ka date) - (now IST ka date)` se, `seconds_left` waisa hi (aakhri din ke ghante/minute label ke liye).
  - Backfill: `UPDATE subscriptions ... expires_at = IST midnight after current expiry date` sabhi active pro rows ke liye.
- Client (`src/lib/quota.ts`): server ka `days_left` pehle se hi prefer hota hai; sirf fallback ko calendar-day ginti par laya jayega taaki server value na aane par bhi same dikhe. `planTimeLeft` labels waise hi rahenge.
- Baaki kuch nahi badla: payments, detection, webhooks, QR limits, notifications, admin ke doosre parts, docs.
