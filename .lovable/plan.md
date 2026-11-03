# Pay page: smaller result panel, slow spinning coin, faster PhonePe-only detection

## 1. Smaller result panel
- The slide-up panel now covers only the "Card / Net Banking" box at the bottom, not the QR area.
- The QR, timer and "Payment Options for …" heading stay visible above it.
- On mobile it is the same: it covers only the bottom options box.
- Content is made more compact (smaller badge, amount, order ID row, redirect line) so it fits inside that box.

## 2. New success animation (Razorpay-style feel, our own design)
- No more falling coin. A gold ₹ coin appears in the centre and slowly spins on its axis (about 1.6s per turn, 2 turns, smooth ease).
- Once it finishes spinning, the coin turns into a green circle and the tick draws in.
- A soft green ring pulses outward once.
- The failed state stays as it is now (red cross with a small shake), only resized to the smaller panel.
- The animation is drawn by us; no Razorpay files are copied.

## 3. Faster detection, PhonePe only
- Only emails from exactly `noreply@phonepe.com` are accepted. Paytm emails will no longer be detected (as you asked).
- The mailbox search asks the server only for PhonePe emails from the last 30 minutes, instead of the whole day.
- Only the newest 5 emails are read, newest first, so each scan is much shorter.
- Mailbox checks run every 2 seconds while the pay page is open (now 3 seconds), with the shared limit lowered to 2 seconds per merchant so the mailbox is not overloaded.
- The page refreshes the status immediately when a match is found (already in place).

Note: the biggest delay is how long PhonePe takes to send the email and Gmail takes to deliver it. That part we cannot speed up; these changes remove our own delay.

## Nothing else changes
QR, timer, amount/paise logic, webhooks, redirects, plans and dashboard stay as they are.

## Technical details
- `src/styles.css`: `.chk-sheet` anchored to the `.chk-options` card (position the sheet relative to a wrapper around the "Other Payment Options" card; top = card top). New `chk-coin-spin` keyframes (rotateY 0 to 720deg, 3.2s) then badge colour fade + tick stroke; remove the drop keyframes.
- `src/routes/pay.$slug.tsx`: render the sheet inside a relative wrapper around the options card; poller interval 2000ms.
- `src/lib/mail-poll.server.ts`: `MONITOR_SENDERS` only, drop Paytm domains; `fromFilter: ["noreply@phonepe.com"]`, `limit: 5`; skip emails whose Date is older than 30 minutes; throttle `_min_gap_seconds: 2`.
- `src/lib/imap.server.ts`: fetch newest UIDs first (already limited by `limit`).
