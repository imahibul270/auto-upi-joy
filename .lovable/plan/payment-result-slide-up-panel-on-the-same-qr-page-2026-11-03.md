# Payment result: slide-up panel on the same QR page

## What changes (only the payment page)

- The separate full result page (black/green card shown in your screenshot) is removed.
- When a payment is detected or the link expires, a white panel **slides up from the bottom of the right side**. It covers the QR card and Card / Net Banking options up to the "Payment Options for ..." heading. The purple left side stays visible.
- Panel animation steps, smooth and lag-free (CSS only):
  1. **Processing:** a soft spinning ring with "Processing payment…" (replaces the current blur pill), about 2 seconds.
  2. **Success:** a green circle pops in, a gold coin flips and drops into it, then a tick draws itself. Text: "Payment successful", amount, order ID with copy button.
  3. **Failed:** a red circle pops with a small shake and a cross draws itself. Text: "Payment failed", amount, order ID.
- The "Redirecting back to merchant's website... 3s" countdown shows inside the panel when a redirect URL is set. Upgrade tabs still auto close.
- On phones the panel slides up over the options area the same way.
- Nothing else changes: the QR, timer, detection, amount, redirect logic and design colours.

## Technical details

- `src/routes/pay.$slug.tsx`: delete the early-return `pay-done` screen. The checkout layout always renders. Inside `.chk-right`, add a `.chk-sheet` overlay (absolute, inset from below the heading). It is visible when `processing || status is paid/expired` and has a stage class `is-processing | is-success | is-failed`. All hooks, polling, redirect and autoclose code stays the same.
- `src/styles.css`: add `.chk-sheet` (translateY(100%) → 0, 0.45s cubic-bezier), `.chk-coin` (rotateY flip + drop keyframes, gold gradient), `.chk-ring` spinner, stroke-dash draw for the tick and cross SVGs, a shake keyframe, and `prefers-reduced-motion` fallbacks. `.chk-right` gets `position:relative; overflow:hidden`.
- Testing: Playwright, viewing an expired link on desktop and mobile widths, with screenshots of the failed panel. Success is checked by forcing the state locally in the script.
