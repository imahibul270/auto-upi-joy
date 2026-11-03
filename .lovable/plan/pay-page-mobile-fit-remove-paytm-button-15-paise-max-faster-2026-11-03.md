# Pay page: mobile fit, remove Paytm button, 15 paise max, faster detection

## 1. Full mobile fit (pay page only)
- Tune the phone layout so everything fits a small screen with no side scroll: purple header on top, QR card stacked (QR centered, "Scan and pay with" + app logos below), Card / Net Banking rows full width, readable text and tap sizes.
- Check at 360px, 390px and 430px wide, plus tablet. Desktop look stays the same.

## 2. Remove the Paytm button completely
- Remove the Paytm logo button under the QR, its shine/lighting effect, and its share code.

## 3. Extra paise: max 15 paise
- New links get a random extra of ₹0.01 to ₹0.15 only (before: up to ₹0.99). Credit still shows the base amount; uniqueness per merchant, exact-match and all other rules stay the same.
- Note: with only 15 choices, one merchant can have at most 15 open links of the same amount at the same time (5 minutes each). The 16th would show the existing "try again" error.

## 4. Faster payment detection
- First step: measure the real delay from recent paid links (payment email time vs detected time) to confirm where the time goes.
- Then fix the slow points found, expected:
  - Start a mailbox check immediately when the pay page opens, and never send a new check while the last one is still running (overlapping checks currently get skipped by the 3s limit and waste a turn).
  - As soon as a check finds the payment, refresh the page status right away instead of waiting for the next status tick.
  - Look only at the newest alert emails first so each check finishes faster.
- Matching rules (exact paise, one email one use, own mailbox only, 5 minute expiry) do not change.

## Not changing
Design colours, success/failed animation, redirect countdown, upgrade auto-close, plans, QR limits, webhooks, admin, docs.

## Technical details
- `src/routes/pay.$slug.tsx`: drop `paytmLogo` import, `openPaytm`, button JSX; poll kicker uses an in-flight guard, fires on mount, and calls `load()` when the response has `matched > 0`.
- `src/styles.css`: delete `.pay-paytm*` rules/keyframes; expand the 760px media block (plus a 420px block) for `.chk-*`.
- Migration: replace `generate_series(1, 99)` with `(1, 15)` and the `base + 0.99` window with `base + 0.15` in `create_payment_link` and `api_create_payment_link` (current definitions from 0032), no other edits. Mirror in `database/setup.sql`.
- `src/routes/api/public/payments/poll.ts` returns `matched`; `mail-poll.server.ts` IMAP fetch narrowed (sinceDays/limit) only if the timing check shows the scan is the bottleneck.
