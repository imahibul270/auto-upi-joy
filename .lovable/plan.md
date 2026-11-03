# Popup checkout on the merchant's own website

Yes, this is possible. The customer stays on the merchant's website, and our same payment page opens on top of it as a popup. The payment page design stays exactly as it is.

## How it works for the merchant
1. The merchant adds one line to their website to load our small "Auto Upi Checkout" script from autoupi.in.
2. Their server creates an order through our API, same as today, and gets the payment link.
3. On their "Pay" button they call `AutoUpi.open(...)` with that link.
4. A dark overlay covers their page and our payment page opens in the middle (full screen on phones), with the same QR, timer, processing, success and failed animations.
5. When the payment succeeds or fails, the popup closes by itself after the result animation and tells the merchant's page the result (order ID + paid/failed). The merchant decides what to show next.
6. The customer can close the popup with a × button. The merchant's page is then told "closed", and the order stays pending until it expires.
7. Server-to-server webhooks keep working exactly as today. They are still the only trusted proof of payment. The popup message is only for updating the screen.

## What stays the same
- Payment page design, QR, timer, detection, paise logic, webhooks, plans and dashboard.
- Normal links and redirects keep working for merchants who don't use the popup.
- Inside the popup, the saved success/failure redirect is skipped. The merchant's page gets the result instead.

## Docs
A new "Popup checkout" section in Docs with a copy-paste HTML/JS example and a PHP example.

## Technical details
- `public/checkout.js` (new, plain JS): `AutoUpi.open({ url, onSuccess, onFailure, onClose })`. It creates a fixed overlay and an iframe pointing to `/pay/<slug>?embed=1`, and adds a close button. It listens for `message` events only from the autoupi origin and only for the matching order_id, and removes the iframe after the result arrives.
- `src/routes/pay.$slug.tsx`: when `embed=1`, it posts `{type:"autoupi:paid"|"autoupi:failed", order_id}` to `window.parent` and skips the redirect. Background is transparent around the card. Nothing else changes.
- The page can be embedded in an iframe: there is currently no frame-blocking header, so this already works. Only `/pay/*` will be allowed to embed; dashboard and admin pages get `frame-ancestors 'none'` so they can't be loaded inside other sites (clickjacking protection).
- `src/routes/docs.tsx`: new section.
- Test: a local HTML test page opens the popup on an expired link and checks that the failed message reaches the parent page.
