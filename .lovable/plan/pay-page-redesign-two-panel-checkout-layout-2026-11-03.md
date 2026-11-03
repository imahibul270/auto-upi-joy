# Pay page redesign: two-panel checkout layout

## What changes (only the payment page `/pay/<link>`)

- New two-panel checkout layout, like the reference screenshot:
  - **Left panel (purple):** back arrow, your Auto Upi logo, merchant/payee name, and an amount box (₹ amount with arrow). Light lavender area below.
  - **Right panel:** heading "Payment Options for **<Order ID>**" (order ID instead of the phone number), with a demo "Change" link.
  - **QR card:** QR code on the left (your logo stays in the middle), "Expires in 04:50 mins" countdown below in orange; on the right "Scan and pay with", the UPI app logos from your 2nd image, and "or other UPI apps".
  - **Other Payment Options:** "Card" (Visa/Mastercard/RuPay badges) and "Net Banking" rows — demo only, they don't do anything.
- The 2nd image (PhonePe, GPay, Paytm, etc. row) is saved as an image and shown neatly in the "Scan and pay with" spot.
- On phones the two panels stack (purple header on top, options below).
- Kept exactly as before: loading skeleton, 2-second blur + "Processing payment…", green success / black-and-white failed screen with animation, 3-2-1 redirect countdown, upgrade-tab auto close, Paytm share button, live expiry from the server, payment detection.

## Technical details

- `src/routes/pay.$slug.tsx`: replace only the active-state JSX (header / total / code-area / footer) with the new `.chk-*` structure; all hooks, polling, redirect and success/failed screens untouched. Paytm share button kept under the QR card.
- Upload `upi-apps-real.jpg` with lovable-assets → `src/assets/upi-apps-real.jpg.asset.json`.
- Card brand badges as small inline text chips (no external logos); bank/card icons from lucide.
- `src/styles.css`: new `.chk-*` classes with purple tokens scoped to the pay page (oklch), responsive breakpoint at 760px; skeleton reuses `.pay-skeleton`.
