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

Gmail allows about **500 recipients a day**, and bulk mail from a personal
Gmail account is filtered as spam far more often. That is fine for
transactional mail and one-to-one admin emails. It rules out broadcasts.

## Broadcast email: designed, deliberately NOT built

A broadcast needs a real sender first (above). It is a provider decision before
it is a code task. When that exists, this is what it requires:

- **Audience:** the admin user filter bar (`Admin::Filterable`: status,
  language, city, joined…) defines the segment. Show the exact recipient count
  before anything is sent.
- **Consent:** confirmed addresses only, and exclude `users.email_opt_out_at`
  (a new column).
- **Unsubscribe:** a signed one-click link in every message, plus
  `List-Unsubscribe` and `List-Unsubscribe-Post` headers (required by Gmail and
  Yahoo for bulk senders). It lands on a public page that needs no login.
- **Language:** optional body per locale (en/ps/fa/ur), falling back to en.
- **Can't unsend:** preview, send-test-to-me, then a confirm that makes the
  admin type the recipient count. Send in rate-limited batches from a job, with
  live sent/failed counts and a Stop button.
- **Record:** one row per broadcast and per recipient, so a failure is visible
  and nobody is mailed twice by a retry.
- **Off by default:** behind a flag until the sender exists.
