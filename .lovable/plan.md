# Moving Auto Upi off Lovable (no changes to the live app)

## What is and isn't possible here
- I can't build a Cloudflare hosting/deploy setup for this project from here. That isn't supported, and the current site must keep running untouched.
- Moving the database to Cloudflare (D1) would mean rewriting every login, plan limit, quota, double-payment check and admin rule. That is a big risk of new payment bugs, so I won't do it.
- What already works without Lovable: the code is standard. You can take it through GitHub (Project settings → Git → connect, or Download codebase), run it on your own server, and use your own database with the ready-made `database/setup.sql` (empty, with no users or data).

## What I will do (documentation only, no app code changes)
1. Update `database/GUIDE.md` with one clear "Exit Lovable" checklist in simple Hinglish:
   - Export the code (GitHub sync or Download codebase).
   - Create your own empty database (supabase.com or self-hosted) and run `setup.sql`. Payment detection, polling, mailbox connect, success handling and double-payment protection all come along with it.
   - Fill in the `.env` values and the admin email.
   - Host it on any Node host (Hostinger guide is already there). The domain autoupi.in moves to the new host only after testing.
   - Test checklist: register, connect mailbox, ₹1 payment, check for duplicate credit, webhook, admin.
2. List what does NOT come with the export: Lovable AI/connector keys and the payment gateway secrets, which you add again yourself.

## Not touched
The current live site, payments, database and all logic.
