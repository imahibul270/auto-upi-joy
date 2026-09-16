# Auto Upi — Self-Hosting Guide

Everything needed to run Auto Upi on your own Supabase project and your own
server. Follow the steps in order; nothing else is required.

```
database/
  setup.sql    <- run once in the SQL editor (safe to re-run)
  reset.sql    <- wipes app tables (destructive, test projects only)
  GUIDE.md     <- this file
  README.md    <- short version
```

---

## 1. Create the database

1. Create a project on **supabase.com** or start a **self-hosted** Supabase stack.
2. Open **SQL Editor → New query**.
3. Before running, open `setup.sql` and change the admin email in
   `is_platform_admin()` to your own email.
4. Paste the whole file and press **Run**.

`setup.sql` creates every table, grant, RLS policy, trigger and function the app
uses:

| Object | Purpose |
| --- | --- |
| `profiles` | name, mobile, business logo |
| `merchant_accounts` | UPI ID, payee name, mailbox email + app password |
| `payment_links` | orders, unique payable amount, status, webhook state |
| `qr_codes` | one row per generated link — this is the plan usage counter |
| `subscriptions` | plan (free/pro), validity window, custom `qr_limit` |
| `api_keys` | one active key per user + webhook secret |
| `processed_emails` | de-duplication of detected payment emails |

All data is protected by Row Level Security: a user can only ever read their own
rows. Every write goes through a `SECURITY DEFINER` function, so limits cannot be
bypassed from the browser.

---

## 2. Enable authentication

**Authentication → Providers → Email** → enable. Turn off "Confirm email" only if
you want instant sign-in.

**Authentication → URL Configuration**

- Site URL: `https://your-domain.com`
- Redirect URLs: `https://your-domain.com/auth`, `https://your-domain.com/reset-password`

---

## 3. Point the app at your database

Copy `.env.example` to `.env` and fill in:

```
VITE_SUPABASE_URL=https://xxxxxxxx.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-anon-or-publishable-key
VITE_SUPABASE_PROJECT_ID=xxxxxxxx

SUPABASE_URL=https://xxxxxxxx.supabase.co
SUPABASE_PUBLISHABLE_KEY=your-anon-or-publishable-key
SUPABASE_PROJECT_ID=xxxxxxxx
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

The `VITE_` copies are used in the browser, the others on the server. The service
role key is **server only** — never prefix it with `VITE_`.

Build and run:

```
bun install
bun run build
bun run start
```

---

## 4. Payment detection (PhonePe)

1. In the merchant's Gmail account, create an **app password** (16 characters).
2. In the app: **Connect Accounts** → choose PhonePe → enter the UPI ID → Save →
   enter the mailbox email + app password → Connect.
3. The server polls that mailbox (max one scan every 6 seconds per merchant) and
   only trusts mail from `noreply@phonepe.com`.

How a payment is matched safely:

- Every link gets a unique payable amount inside that merchant (base amount +
  1–299 paise). The plain base amount is never accepted.
- A link is only matched against its **own merchant's** mailbox, so one user's
  payment can never settle another user's link.
- Each email ID can be claimed once, so double credit is impossible.
- The email must be newer than the link, and the link expires in 5 minutes.
- The merchant is always credited the **base amount**; the extra paise are only
  an identifier.

---

## 5. Plans and limits

| Plan | Price | QR / payment links | Validity |
| --- | --- | --- | --- |
| Free | ₹0 | 3 lifetime | — |
| Pro | ₹299 | 3,000 | 30 days |

The limit is enforced inside `consume_qr_quota()` in the database, which runs
before every link insert. There are no insert grants on `qr_codes` or
`payment_links`, so the limit cannot be bypassed from the browser, from the API,
or by calling the functions directly.

Admins can override the limit per user (`subscriptions.qr_limit`).

---

## 6. Admin panel

- URL: `https://your-domain.com/admin`
- Only one email can ever be admin. It is hardcoded in two places and must match:
  1. `is_platform_admin()` in `database/setup.sql`
  2. `ADMIN_EMAIL` in `src/routes/admin.tsx`
- There is no role table and no way to grant admin to another account.
- The first sign-in with that email and a password of your choice creates the
  admin account automatically.

Inside the panel:

- **Overview** — users, active Pro, QR generated, payments, collected volume,
  subscription revenue.
- **Users** — search, see plan, QR used/limit, validity, payments, volume.
- **Subscriptions** — Pro users only.
- **Logs** — live payment activity for every merchant.
- **Manage** on any user — set Free/Pro, validity days, QR limit, paid amount and
  optionally reset their QR usage to zero. Changes apply instantly.

---

## 7. Public API

Endpoints (documented in full at `/docs`):

- `POST /api/public/v1/create-order` — create a payment link, optional
  `webhook_url`.
- `GET /api/public/v1/order-status` — check an order.
- Webhooks are signed with HMAC-SHA256 in `x-autoupi-signature`
  (`t=<unix>,v1=<hex>`) using the merchant's webhook secret. Always verify the
  signature before crediting a customer.

API keys are created from **API Keys** in the dashboard; one active key per user,
regenerating replaces the old one.

---

## 8. Verify the install

1. Register at `/register` — a `profiles` row appears automatically.
2. Connect a UPI ID and mailbox.
3. Generate a link — the Plan page usage counter increases by 1.
4. Use up the free limit — link generation stops with an upgrade message.
5. Open `/admin` with the admin email and set a user to Pro.

---

## Reset (danger)

`reset.sql` drops the app's tables, functions and triggers so `setup.sql` can be
run from a clean state. It deletes data — test projects only.
