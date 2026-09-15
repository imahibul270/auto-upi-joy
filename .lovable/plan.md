# Auto Upi login and registration

## Build
- Add separate `/auth` and `/register` pages matching the supplied two-column QR-payment reference, with Auto Upi wording and branding.
- Keep both pages fully usable on phones and desktops; stack the illustration and form cleanly on small screens.
- Use email and password for sign-in. Registration will collect name, mobile number, email, password, and password confirmation, with no captcha.
- Connect “Create new account” to registration and “Login” back to sign-in; successful authentication will continue to a protected dashboard page.
- Include forgot-password and reset-password screens so users can safely recover access.

## Account data
- Enable Lovable Cloud authentication and persistent storage.
- Store each user’s name and mobile number in a private profile linked to their account.
- Create profiles automatically after registration, with access rules allowing users to read and update only their own profile.
- Add email confirmation handling and clear success/error states.

## Technical details
- Keep the existing public landing page intact, changing its sign-in/create-account links to the new screens.
- Add the managed protected-area gate, authenticated dashboard route, and required session-aware sign-out flow.
- Add unique search and sharing metadata to every new page.
- Verify registration/login navigation, responsive layouts, and the production build.
