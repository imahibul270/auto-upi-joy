# PhonePe "payment through a link is not allowed" error

## Why it happens

- Your UPI ID `Q168071078@ybl` is a **PhonePe Business QR merchant ID** (IDs starting with `Q` are merchant QR stickers).
- NPCI rules say these merchant IDs can be paid by **QR scan only**. Opening them from a link (UPI intent) is blocked inside PhonePe/GPay itself. Search results say the same thing: PhonePe and GPay refuse browser-opened links for some merchant account types.
- Razorpay/PayU get past this because they are licensed gateways. Their intents are **signed by the bank** with a secret merchant key. We cannot create that signature, and no code trick can get around it. Trying to bypass it would break UPI rules and could get the merchant ID frozen.

## Real fixes (legal ones)

1. **Official PhonePe Payment Gateway** (business.phonepe.com → PG): PhonePe gives you an API key. Their "UPI Intent" / "Pay Page" opens PhonePe directly, and it works 100%. This needs KYC approval and a separate integration later.
2. **Use a personal UPI ID** (for example `name@ybl`) for intent. Links work, but there are personal-limit / risk-policy warnings, and it is not suitable for business volume.

## What I will change now

- On the payment page, change what the PhonePe button does:
  - If the UPI ID is a merchant QR ID (it starts with `Q`, or the app blocks the link), the button **saves/shares the QR image** and shows the hint "Open PhonePe → Scan → choose from gallery". Paying from the gallery is allowed for merchant IDs.
  - If the UPI ID is personal, the button keeps opening PhonePe directly, like now.
- Add a small **"Copy UPI ID"** link under the QR as a backup.
- Nothing else changes: detection, amount, expiry, animations and redirect stay the same.

## Technical details

- `src/routes/pay.$slug.tsx`: `isMerchantVpa = /^q\d+@/i.test(upi_id)`. When it is true, `openPhonePe` builds a PNG from the QR data URL. It uses `navigator.share({files})` if the phone allows it, otherwise it downloads the file. It then shows an inline hint text. A copy button uses `navigator.clipboard`.
- `src/styles.css`: a `.chk-hint` text style.
- Test: Playwright on a mobile viewport with a merchant ID link. Check that the button shows, the hint appears and the copy works. A real PhonePe test has to be done on your phone.
