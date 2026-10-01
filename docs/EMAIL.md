# Email

## Sender (decided by the owner, 2026-10-01)

Every email (account confirmation, password reset, admin emails) is sent
through Gmail SMTP as **`infohama99o@gmail.com`**. It is also the From and the
Reply-To. That is the owner's choice for now; a real sender comes later.

`config.x.mail_sender` (config/application.rb) is read from the SMTP
credentials (`smtp_username`), so the From always equals the account that
actually sends. Devise (`mailer_sender`) and `ApplicationMailer`
(`from` + `reply_to`) both use it. The website's contact address
(`hatiwal-web/src/lib/app-links.ts` `SUPPORT_EMAIL`) is the same inbox.

### Why not noreply@hatiwal.com

That was the old default, and it only "worked" because Gmail silently rewrote
it to the signed-in account. `hatiwal.com`'s DNS (checked 2026-10-01):

| Record | Value | Meaning |
|---|---|---|
| SPF | `v=spf1 -all` | no server may send as hatiwal.com |
| DMARC | `p=reject; sp=reject; adkim=s; aspf=s` | receivers must reject mail that fails |
| MX | none | nothing at hatiwal.com can receive mail |
| DKIM | none found | |

So a genuine `@hatiwal.com` From would be rejected, and a `@hatiwal.com`
Reply-To would bounce. `MAILER_FROM` was never set in production, so it is no
longer read anywhere.

### Moving to a hatiwal.com sender later

1. Pick a provider (Postmark is already in the Gemfile, unused). It needs DKIM
   and Return-Path records on hatiwal.com, and SPF changed from `-all` to
   include the provider.
2. Give hatiwal.com an MX (or keep Reply-To on an inbox that exists).
3. Change `config.x.mail_sender`, and `SUPPORT_EMAIL` in hatiwal-web.

## Limits of the current sender

Gmail allows ~**500 recipients a day** from a free account. `Admin::MailQuota`
caps admin email at **450 per rolling 24h** (headroom for account mail, which
is not counted) and is the one place to change when the sender changes.

## Admin → Messages (built 2026-10-01)

**One-to-one** (`/admin/messages/new`): pick a person (search by name, email or
phone), tick Email / In-app from Hatiwal Support / both, write once, preview,
test-to-me (email), confirm, send. `Admin::SendMessage` is the only send path
(Support-thread replies use it too) and validates every channel before writing
anything. In-app goes through the support gate (`Conversation.admin_can_message?`,
docs/SUPPORT_MESSAGING.md). One history (`AdminOutreach`) for everything.

**Bulk** (`/admin/bulk_emails/new`, or "Email these users" on the Users list),
email only:

- **Audience = the Users-list filters** (`Admin::UserFilterSet`, the same code),
  so the list shown is exactly who receives. Real members only, **confirmed**
  addresses only, **unsubscribed excluded automatically**; every exclusion is
  counted on screen ("58 match · 21 unconfirmed · 0 unsubscribed · … → 37 will
  receive").
- **All four languages at once** (en/ps/fa/ur), each box showing how many
  recipients read it and — when empty — "Empty: these N will receive the
  {fallback} version". The **fallback language is chosen** (default English) and
  must be written. Each user gets only their `preferred_language` version.
- **Can't-unsend safeguards:** preview of every written language, a test of each
  to the admin (with a dead unsubscribe link), and Send stays disabled until the
  admin types the recipient count — checked again server-side against a FRESH
  count, so a segment that changed since preview is refused.
- **Snapshot at confirm:** one `AdminEmail` per recipient with their version, so
  what was approved is what sends.
- **Sending** (`AdminBulkEmailJob`): batches of 10 a minute; each row claimed
  atomically (`queued → sending`) before SMTP, so a crashed or duplicated run
  never mails anyone twice; a row stuck `sending` is marked failed
  ("interrupted"), never re-sent; **Stop** cancels the rest; at the daily cap it
  **pauses** (resumable) instead of letting Gmail reject mid-run.
- **Unsubscribe:** every bulk email has a footer link and `List-Unsubscribe` +
  `List-Unsubscribe-Post` (RFC 8058) headers → a public no-login page in the
  user's language (`UnsubscribesController`, signed non-expiring token), with an
  **undo**. Opted-out users get a warning, not a block, on one-to-one email (it
  is about their account), and the admin's acknowledgement is recorded.
- **Development:** dev SMTP sends real mail, so in development admin email may
  only go to the mail account itself; anything else **raises** (`MailQuota.
  assert_dev_recipient_allowed!`) — at confirm and again per row.

### In-app bulk ("Bulk message", built 2026-10-01)

Tick **In-app** (alone or with Email) on the bulk screen: a message from
Hatiwal Support is posted into each recipient's support thread, in their
language. A Support thread has **no unsubscribe**, so the restraints are:

- **The gate, per recipient**: only users who already have a support thread
  (or everyone, once `SUPPORT_ADMIN_INITIATE` is on). Counted before sending
  ("3 can receive in-app · 37 can't") and **re-checked per delivery at send
  time** — a refused one is recorded `skipped`, never given a thread.
- **Archive = mute for broadcasts.** A broadcast is delivered into an archived
  thread quietly: it stays archived and gets no push. A *personal* reply still
  brings it back. (`Message#broadcast`; do not merge the two rules.)
- **Push off unless chosen**, each time, with "N of M can receive one" beside
  the box; "N of M can't receive a push" is always shown.
- **One broadcast per person per 7 days** (`AdminBulkEmail::IN_APP_COOLDOWN`);
  recent recipients are excluded and counted.
- **Plain text, ≤ 1000 chars** (a chat message).
- **The confirm says it**: "They can't unsubscribe from it — only archive
  Support."
- No Gmail quota (nothing goes through Gmail). In development a broadcast
  **push** is refused if any recipient holds a token.

One-to-one Messages is one box in the recipient's language; the four-language
system is bulk-only (owner: "for one user we dont need 4").

Not built: a per-user "mute announcements" toggle (needs mobile UI — archive
covers it), open/click tracking.
