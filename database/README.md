# Auto Upi — Backend Setup

Everything the app needs on the database side lives in this folder.

```
database/
  setup.sql    <- run this once, that's it
  reset.sql    <- optional: wipes app tables (destructive)
```

## 1. Create a Supabase project

Works with both **supabase.com** and a **self-hosted** Supabase instance.

## 2. Run the SQL

Open **SQL Editor → New query**, paste the whole content of `setup.sql`, press **Run**.

It creates:

- `public.profiles` table (id, full_name, mobile, business logo, created_at, updated_at)
- Grants for `authenticated` and `service_role`
- Row Level Security so a user can only read/write their own profile
- `updated_at` auto-update trigger
- `on_auth_user_created` trigger → a profile row is created automatically at sign-up

The script is safe to re-run (idempotent).

## 3. Enable Email/Password auth

Dashboard → **Authentication → Providers → Email** → enable.
If you don't want users to verify email first, turn off "Confirm email".

Add your site URLs under **Authentication → URL Configuration**:

- Site URL: `https://your-domain.com`
- Redirect URLs: `https://your-domain.com/auth`, `https://your-domain.com/reset-password`

## 4. Point the app at your backend

### Option A — Self-host / sell the app

Copy `.env.example` to `.env` and fill in your own project values:

```
VITE_SUPABASE_URL=https://xxxxxxxx.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-anon-or-publishable-key
VITE_SUPABASE_PROJECT_ID=xxxxxxxx

SUPABASE_URL=https://xxxxxxxx.supabase.co
SUPABASE_PUBLISHABLE_KEY=your-anon-or-publishable-key
SUPABASE_PROJECT_ID=xxxxxxxx
```

Both `VITE_` and non-`VITE_` copies are needed: the first is used in the browser,
the second during server-side rendering. The anon/publishable key is safe to ship.
Never put the service role key in a `VITE_` variable.

Restart the dev server (or rebuild) after changing `.env`.

### Option B — Use your own backend inside Lovable Cloud

Your credentials are already saved as runtime secrets:

- `CUSTOM_SUPABASE_URL`
- `CUSTOM_SUPABASE_ANON_KEY`
- `CUSTOM_SUPABASE_SERVICE_ROLE_KEY`

To make the live preview/published app use your backend, update the managed
environment variables in your Lovable project settings:

```
VITE_SUPABASE_URL=<your Supabase URL>
VITE_SUPABASE_PUBLISHABLE_KEY=<your anon key>
VITE_SUPABASE_PROJECT_ID=<your project ref>

SUPABASE_URL=<your Supabase URL>
SUPABASE_PUBLISHABLE_KEY=<your anon key>
SUPABASE_PROJECT_ID=<your project ref>
```

These variables are managed by the Lovable Cloud integration, so they must be
changed from the project settings UI, not from code.

## 5. Verify

1. Open `/register`, create an account.
2. Check **Table Editor → profiles** — a row should appear automatically.
3. Sign in at `/auth`, you should land on `/dashboard`.

## Reset (danger)

`reset.sql` drops the app's tables, functions and triggers so you can run
`setup.sql` from a clean state. It deletes data — only use on a test project.
