# Smooth page and section animations

## Changes
- Add a shared reveal system that smoothly fades and lifts page content into view.
- Animate landing-page headings, feature cards, workflow steps, pricing cards, checkout, code example, call-to-action, and footer as users scroll.
- Add tasteful staggered timing so grouped cards appear in sequence rather than all at once.
- Animate login, registration, password recovery, and dashboard content when each page opens.
- Keep the fixed top bar stable and avoid replaying animations unnecessarily.
- Respect reduced-motion settings and keep effects lightweight on mobile.

## Technical details
- Use one reusable intersection observer wrapper for scroll-triggered reveals.
- Use CSS transforms and opacity for smooth performance, with semantic timing variables for staggered items.
- Verify landing, account pages, and phone/desktop layouts after implementation.
