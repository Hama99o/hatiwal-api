# Email Confirmation

## Why this exists

`User#issue_warning!` auto-suspends an account at 3 active warnings, and
`ReinstateDecayedUsersJob` lifts it as the strikes decay. That machinery is
sound — and it was **decorative**, because signup had no cost: nothing verified
an email address, so a suspended user was back inside twenty seconds with
`x@y.com`. Every downstream idea (trust tiers, risk scores, a smaller review
queue) rests on an account being worth something to keep.

## What is switched on

Devise's `:confirmable`, in its **non-blocking** form.

| Piece | Where |
|---|---|
| `:confirmable` on the model | `app/models/user.rb` |
| `allow_unconfirmed_access_for = nil` (unlimited) | `config/initializers/devise.rb` |
| `default_confirm_success_url` (`WEB_CONFIRM_URL`) | `config/initializers/devise_token_auth.rb` |
| Branded confirmation email | `app/views/devise/mailer/confirmation_instructions.*` |
| Backfill for every pre-existing account | `db/migrate/20260825000000_backfill_confirmed_at_for_existing_users.rb` |
| `confirmed_at` column + `confirmed` / `unconfirmed` filters in admin | `app/dashboards/user_dashboard.rb` |
| Google accounts created pre-confirmed | `app/controllers/api/v1/auth/google_auth_controller.rb` |
| Devise mail queued, never sent in-request | `User#send_devise_notification` |

So today: signup sends a confirmation email, `confirmed_at` records who acted on
it, and the admin can list every account that never did. **Nothing is gated on
it.** An unconfirmed user signs up, signs in and uses the app exactly as before.

## Why nothing is gated yet

The app is already shipped — Play Store internal testing and the App Store — and
neither client has a "confirm your email" screen or a resend button. Turning
`:confirmable` on the usual way breaks an installed client in three separate
places, all of which the specs in
`spec/requests/api/v1/auth/email_confirmation_spec.rb` now pin down:

1. **Signup returns no auth token.** DTA's `RegistrationsController#create`
   issues a token only `if active_for_authentication?`. With a finite grace
   period an unconfirmed user fails that check, so signup succeeds and the app
   is left holding no session.
2. **Signup 422s outright.** With `:confirmable` on and no
   `confirm_success_url` — which neither client sends — DTA answers
   `render_create_error_missing_confirm_success_url`.
3. **Login starts failing later.** With a finite window, users who never
   confirmed are locked out on day N+1. That is worse than an immediate break:
   it arrives as a random login failure, in the field, with no UI explaining it.

`allow_unconfirmed_access_for = nil` neutralises all three. The cost, stated
plainly: **the deterrent is not live.** A banned user can still return with a
fake address and simply never confirm it. What exists now is the plumbing and
the signal, not the gate.

## Turning the gate on

In rough order of cost:

1. **Clients first.** A "confirm your email" state plus a resend action. Without
   a resend button, every confirmation email that lands in spam is a lost user
   with no way out.
2. **Add a resend endpoint.** DTA mounts `POST /api/v1/auth/confirmation`
   already; it needs a rate limit (`throttle to: 5, within: 1.hour, by: :user`)
   for the same reason the password-reset endpoint has one.
3. **Then pick the gate.** Options, narrowest first:
   - require confirmation to **publish a listing** (`ListingPolicy#publish?`) —
     browsing and chat stay open, which keeps the loss small if it misfires;
   - require it to **start a conversation**;
   - require it to **sign in** — set `allow_unconfirmed_access_for` to a
     duration. Do this last and only with step 1 shipped.
4. Consider `DeviseTokenAuth.send_confirmation_email = true` at the same time.
   It only controls DTA's `ConfirmableSupport`, which re-enables devise's
   **reconfirmable** behaviour on email change: an email edit is then held in
   `unconfirmed_email` until a link is clicked. No client currently calls
   `PUT /api/v1/auth` with an email, so it is off and harmless — but it becomes
   relevant the moment one does.

## The better anchor, when there is budget

Email is the cheap proxy. In Afghanistan the identity that actually costs
something is a **phone number** — everyone has one, and a second one costs real
money. SMS verification needs a provider that reliably delivers to Afghan
networks plus a per-message budget, so it is a spike of its own, not a
configuration change. Everything above is designed so that swapping the proof
from email to phone changes what sets `confirmed_at`, not what reads it.
