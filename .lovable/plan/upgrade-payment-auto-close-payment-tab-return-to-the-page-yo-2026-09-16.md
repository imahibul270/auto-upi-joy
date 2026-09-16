# Upgrade payment: auto-close payment tab, return to the page you started from

## What changes

- Jab payment wale naye tab me payment success hota hai, wo tab apne aap band ho jayega (success tick dikhane ke chhote se pause ke baad).
- Purana tab (jahan se Upgrade pe click kiya tha — dashboard ka Plan page) khud hi refresh hokar naya Pro plan dikha dega, countdown ke saath.
- Payment fail ya link expire hone par bhi payment tab band hoga aur purane tab par saaf message aayega.
- Agar browser tab ko band na karne de (kuch browsers block karte hain), tab par "Aap ye window band kar sakte hain" message dikhega — purana tab phir bhi apne aap update hoga.

## Technical details

- `src/routes/pay.$slug.tsx`: success state par, agar `window.opener` maujood hai, `opener.postMessage({ type: "autoupi:paid", order_id }, origin)` bhejo, phir ~2s baad `window.close()`. Close block hone par ek chhota "You can close this window" note render karo. Only for tabs opened by the app (opener check), normal merchant pay pages unaffected.
- `src/routes/_authenticated/plan.tsx`: upgrade flow me `window.addEventListener("message", ...)` add karo — same-origin + matching `order_id` par turant `checkProUpgrade` chala kar polling short-circuit karo. Existing 3s polling fallback rahega (agar message block ho).
- Success/expired par existing `resultThenRedirect` countdown chalta rahega aur `/plan` par wapas le jayega; cleanup me listener aur interval dono clear honge.
- Koi backend, webhook ya pricing logic change nahi.
