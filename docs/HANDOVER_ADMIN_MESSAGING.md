# Handover: support messaging, admin Messages, bulk email

These are the non-obvious things about this area, the ones that would take a
fresh session an hour to rediscover. Each was learned the hard way on
2026-10-01. Full contracts are in `SUPPORT_MESSAGING.md`, `EMAIL.md` and
`PUSH_NOTIFICATIONS.md`.

## State (2026-10-01)

- **Production** runs `2e6235d`: support backend, admin filters/email/charts,
  version + push tracking. Deployed by Kamal; a pre-deploy DB dump is in
  `backups/hatiwal_api_20261001_142023.sql`.
- **Committed, NOT pushed or deployed:** `9f8147a` (gate refactor), `ae5d1e5`
  (Messages one-to-one), `25a7167` (bulk). There are 2 additive migrations.
  Push and deploy are the owner's call.
- **Nobody can open a support thread yet.** `SUPPORT_ADMIN_INITIATE` is off,
  and the mobile "Contact support" row is still being built by the mobile
  session. "Support (0)" in the admin is correct, not a fault.

## The one rule: v1.0.4 must keep working

The app in the stores sends no version header and can only talk to
production, so the API cannot tell it apart from a new app. Any response
change reaches it.

- `spec/requests/api/v1/api_contract_v1_0_4_spec.rb` replays a fixed scenario
  and compares it to `spec/fixtures/api_contract/v1_0_4.json`. If it fails,
  the change is a break. New keys must be added to `ALLOWED_ADDITIONS` on
  purpose.
- **Re-recording** (only once v1.0.4 is gone): use a `git worktree` of the
  old commit **with its own test DB**. Change the db name in the worktree's
  `config/database.yml`. If you skip this, `maintain_test_schema!` resets the
  shared `hatiwal_test` under other sessions. Files the container writes are
  root-owned, so read them out with `docker compose exec … cat`.
- On a support thread, `listing_deleted: true` is deliberate. An old client
  shows a "removed listing" banner instead of crashing on `listing.title`.
  Clients branch on `kind` first. Don't "fix" it.
- The inbox pin is `ORDER BY kind DESC`, **not** a `CASE`. Inbox search is
  `SELECT DISTINCT`, and a CASE made every `?search=` a 500. A model spec
  pins support as the highest kind value.
- `Conversation#kind` and `User#support_account` are declared with
  `attribute`, so code that boots ahead of its migration still loads. An
  undeclared enum raises at class load and 500s listing detail for
  everyone. Migrations only run because `bin/docker-entrypoint`
  string-matches the CMD (`PUSH_NOTIFICATIONS.md`, `SUPPORT_MESSAGING.md`).

## The gate (in-app messages from an admin)

- `Conversation.admin_can_message?(user)` is the ONLY decision point. It is
  true only if the user already has a support thread (only the new app can
  create one) or `SUPPORT_ADMIN_INITIATE` is on.
- Admin code obtains a thread only via `Conversation.admin_support_thread_for`.
  `support_thread_for!` is ungated and is for the user's own API call only.
- **`spec/models/support_gate_spec.rb` greps** `app/{controllers/admin,jobs,
  mailers,services}` for `support_thread_for!` and fails on any hit, even in
  a comment (it caught one). It is a structural guard for code not written
  yet. Do not delete it as redundant.
- `Admin::SendMessage` is the only send path (Messages screen and Support
  thread replies). It validates **every** channel before writing anything,
  so one refused channel means nothing is sent on any channel.
- Turning admin-initiated threads on needs `SUPPORT_ADMIN_INITIATE` in
  `.env.production`, `.kamal/secrets` and `config/deploy.yml` `env.secret`.
  It is deliberately not wired into any of them, so it can't switch on by
  accident. Check the dashboard's "App versions" panel before enabling it.

## Email: things that will bite

- **Dev SMTP sends REAL mail.** `Admin::MailQuota.assert_dev_recipient_allowed!`
  makes development refuse every recipient except `config.x.mail_sender`,
  and it **raises** at confirm and again per row. Don't loosen it to get a
  test through; test against the owner's own address.
- `config.x.mail_sender` (in `config/application.rb`) = the SMTP username =
  `infohama99o@gmail.com`. The owner chose this. hatiwal.com has SPF `-all`,
  DMARC reject and no MX, so don't reintroduce `noreply@hatiwal.com`.
- **Changes to `config/application.rb` need a container restart.** The dev
  server once ran with an empty `mail_sender` for hours (the allowlist
  showed `{}` and refused everyone, which is failing safe). New asset
  directories (Propshaft) also need a restart.
- `development.rb` has `raise_delivery_errors = false`. `AdminEmail#deliver!`
  forces it true per message, otherwise a rejected SMTP login is recorded
  as **sent**. Prove failure paths with a forced failure (a wrong SMTP
  password in a one-off runner), not a spec alone.
- An address that doesn't exist is accepted by Gmail and bounces later, so
  history shows `sent`. Nothing at SMTP time can catch that.

## Admin pages: things that will bite

- **There is no rails-ujs.** Nothing honoured `data-confirm` until the
  listener in `admin/application/_javascript.html.erb`, so Block, Take down
  and Warn fired on one click. Keep it.
- **Per-form CSRF + `formaction` = 422.** A per-form token is bound to the
  form's own action. Forms whose buttons post elsewhere pass
  `authenticity_token: form_authenticity_token`. The test env disables
  CSRF, so the specs that matter turn it back on.
- **Mail HTML is an html_safe SafeBuffer.** Inside `srcdoc="…"` it is not
  escaped and spills into the page, so convert it with `String.new(html)`
  first.
- `group(:status).count` keys by the enum **name** ("sent"), not the integer.

## Bulk email mechanics

- Recipients are **snapshot at confirm**: one `AdminEmail` per person, in
  their language. The typed count is re-checked against a fresh count, so a
  segment that changed since preview is refused.
- `AdminEmail#deliver!` claims each row atomically (`queued → sending`, with
  `updated_at` stamped), so a duplicate or retried job can't double-send.
  A row stuck in `sending` for more than 10 minutes is marked failed as
  "interrupted" and is **never** re-sent.
- `AdminBulkEmailJob` sends 10 a minute and re-enqueues itself. Stop
  cancels the rest. At `MailQuota::DAILY_LIMIT` (450 per rolling 24h) it
  pauses as `paused_daily_limit`, and Resume restarts it.
- The audience comes from the same `Admin::UserFilterSet` as the users
  index. Never build a second filter.
- Unsubscribe uses `user.signed_id(purpose: :email_unsubscribe)` (no
  expiry). The POST is CSRF-exempt because RFC 8058 one-click has no token.
  Undo is on the same token. Test and preview copies get the dummy token
  `test-copy`, so an admin can't opt out a real person by clicking one.

## Push

- **Android has never received a push:** Firebase was never configured in
  the app build. The FCM V1 key is now uploaded, and a new build is pending.
  The admin dashboard "Push notifications — can they reach people?" panel
  shows the count and the app-reported reason
  (`users.push_registration_error`).
- Support push titles are spelled exactly as the mobile app spells them
  (spec-pinned). The brand spelling (Pashto ټ/ت, Urdu ہتیوال/ہاٹیوال) is the
  owner's open decision. Change the app, web, push and `/download` together.

## Proven on dev vs. only specced

| Proven live on dev (Chrome, real Gmail/API) | Specced only |
|---|---|
| Support loop: user opens thread, admin inbox, reply, user receives, read receipt, draft-safe refresh | Push delivery to a real device (no Android token yet) |
| Archived/deleted support thread resurfaces on a new message | Bulk Stop and Resume against a real multi-batch run |
| Email-a-user: real send, forced 535 failure recorded | Bulk daily-cap pause |
| Messages screen: in-app send, greyed channel with reason, push warning | Messages screen: a real email send (same job as the proven one) |
| Bulk: dev guard refuses, segment from Users list, language warnings, typed count, 1 real send in Pashto | "Send a test to me" live (the dev admin's address has no MX) |
| Unsubscribe: page, one-click POST without CSRF, undo | |

## Working in this checkout

Several sessions share it. Commit **only your paths**: `git commit -- <paths>`,
and check `git diff --cached --name-only` first. A plain commit takes
another session's staged files too, and that has already happened here
twice. Never stash, reset or `checkout --`.
