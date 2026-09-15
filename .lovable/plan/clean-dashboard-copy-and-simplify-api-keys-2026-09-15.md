# Clean dashboard copy and simplify API keys

## Changes
- Remove the requested explanatory sentences from Transactions, Payment Links, and Connect Accounts.
- Show mailbox status only as Connected or Disconnected, without displaying the email address.
- Simplify API Keys to one active key flow: first use generates a key; later use regenerates it and replaces the active key.
- Keep the newly generated key visible once with its copy action, while retaining the existing secure storage behavior.

## Verification
- Check the affected pages at desktop and mobile widths.
- Confirm the project builds cleanly and no unrelated content changes.
