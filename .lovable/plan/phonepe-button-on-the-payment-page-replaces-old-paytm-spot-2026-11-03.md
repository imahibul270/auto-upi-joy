# PhonePe button on the payment page (replaces old Paytm spot)

## What a UPI app needs from the phone (summary of Razorpay / PayU / NPCI intent docs)

A UPI intent is just a link the phone opens in a UPI app. The app gets these details:

| Field | Meaning | We send |
| --- | --- | --- |
| `pa` | UPI ID to receive money | merchant's routed UPI ID |
| `pn` | Payee name | merchant payee name |
| `am` | Exact amount (2 decimals) | payable amount, e.g. 100.07 |
| `cu` | Currency | INR |
| `tn` | Note shown to payer | order ID |
| `tr` | Transaction reference (unique per order) | order ID |
| `mc` | Merchant category code | only if merchant has one (business UPI) |

- Generic link: `upi://pay?...` (phone shows app chooser).
- PhonePe-only link: `phonepe://pay?...` (opens PhonePe directly), same fields.
- Works only on a phone with the app installed; on a computer the button is hidden and the QR is used.

## Important honest limit

- Razorpay/PayU intents work 100% because they use **verified merchant (business) UPI IDs** with a bank-signed intent. That signing is only given to licensed payment gateways.
- With a **personal UPI ID** (like xyz@ybl), PhonePe/GPay may show "risk policy", "limit exceeded" or block payments above ~₹2,000 when opened from a link. This is a UPI app rule, not something code can bypass.
- Best result: use a **PhonePe Business / merchant UPI ID**. Then the intent works smoothly.
- QR scanning keeps working as today in every case.

## What changes

- On the pay page, under the QR card (where the Paytm button was), a small rounded **PhonePe** button with the PhonePe logo (no lighting effect).
- Shown only on phones while the link is active; hidden on desktop and after paid/expired.
- Tap: opens PhonePe directly with amount, UPI ID and order ID filled in. If PhonePe isn't installed (page still visible after ~1.5s), it falls back to the normal `upi://pay` chooser.
- Payment detection, amount, expiry, animations, redirect, design — no change.

## Technical details

- `src/routes/pay.$slug.tsx`: add `tr=<order_id>` to the shared `upiParams` (QR and intent stay identical); add button rendering `phonepe://pay?${upiParams}` via `window.location.href`, visibility+timeout fallback to `upi://pay?${upiParams}`; mobile check via user agent (Android/iPhone).
- PhonePe logo via lovable-assets pointer `src/assets/phonepe-logo.png.asset.json`.
- `src/styles.css`: `.chk-intent` button styles (white, rounded, logo 22px), no animation.
