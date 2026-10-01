# Support messaging

A user can message **Hatiwal Support** from the app, and admins answer from
`/admin/support_conversations`. A support thread is an ordinary `Conversation`
with `kind: :support`: the user is `buyer`, the single Support account
(`users.support_account = true`) is `seller`, and there is no listing. Messages,
read receipts, the inbox, ActionCable and push all reuse the existing paths.

## Client contract (additive only)

Both `ConversationSerializer` views gain one key. Nothing is removed, and no
existing field changes type for any conversation that existed before this.

| Field | Listing thread | Support thread |
|---|---|---|
| `kind` *(new)* | `"listing"` | `"support"` |
| `viewer_role` | `"buyer"` / `"seller"` (unchanged) | `null` |
| `listing` | object (unchanged) | `null` |
| `listing_deleted` | unchanged | **`true`**, deliberately (see below) |
| `other_participant` / `seller` | unchanged | the Support account, same keys: `{id, name: "Hatiwal Support", city: null, verified: true, avatar_url}` |
| `blocked_with_participant` / `blocked_by_me` | unchanged | always `false` (blocking Support is refused) |

**Clients must branch on `kind` first, before `listing_deleted`.** A support
thread reports `listing_deleted: true` because an app built before support
messaging handles `true` + `listing: null` as "this listing was removed" (a
wrong banner), while `false` + `listing: null` would reach `listing.title` on
null (a crash). A wrong banner beats a crash.

- `GET /api/v1/conversations` pins the support thread first, then the usual
  order. `role=buying` / `role=selling` exclude it. `search=` matches it by the
  Support account's name (first or last name, like any user).
- `POST /api/v1/support_conversation` returns the caller's thread, creating it
  on first call (idempotent; one per user, enforced by a partial unique index).
- Messages use `POST /api/v1/conversations/:id/messages`. A support thread
  accepts `text`, `image_message` and `document`; deal kinds (offers, meetups)
  get a 422.
- Blocking or reporting the Support account is a 403.
- A push from Support has its **title localized to the recipient**
  (`push.support.title`), because the account's stored name is English and the
  OS shows the title verbatim.

`spec/requests/api/v1/api_contract_v1_0_4_spec.rb` measures all of this against
a recording taken on the code before support messaging. It found one real
break during development: the inbox pin as a `CASE` expression made every
`?search=` a 500 (`SELECT DISTINCT` rejects it). See that spec before touching
these serializers.

## Why this cannot break v1.0.4

v1.0.4 is live, can only talk to production, and sends no version header, so
the API serves it exactly what it serves a new app. The only thing that could
reach it is a support thread, and that is controlled by **who creates one**:

- **Created by the user — safe by construction.** Only an app with support
  messaging has a "Contact support" button, so every user-created thread
  belongs to someone already on the new app. This ships live.
- **Created by an admin — NOT safe yet.** That would land in the inbox of
  someone who may still be on v1.0.4, where it shows as a removed-listing chat
  with Block and Report pointed at Support. It is built but **off** behind
  `SUPPORT_ADMIN_INITIATE`. Admins can always reply in a thread the user opened.
- No migration, seed or backfill creates a support conversation, and none may.
  The Support account is created on first use; an account alone is invisible.

**Known limit, not solved:** a user who updates, opens support, and then also
uses v1.0.4 on a second device sees that thread there as a removed-listing chat.

### Turning on admin-initiated threads

Only once most users are on the new app. The mobile app sends `X-App-Version` /
`X-App-Platform` from `658b9c6` on; a request without them is v1.0.4 or older.
Recording those on the user (`users.last_app_version`) turns "most users have
updated" from a guess into a number. That server half is not built yet.

To turn it on, the variable has to reach the container:
1. `SUPPORT_ADMIN_INITIATE=true` in `.env.production`
2. a matching line in `.kamal/secrets`
3. `SUPPORT_ADMIN_INITIATE` under `env.secret` in `config/deploy.yml`
4. deploy.

Without steps 1–3 it stays off. That is the safe default.

## Deploy findings (not specific to this feature)

- **Migrations run at boot only because of a string comparison.**
  `.kamal/hooks/` has only `.sample` files, and `bin/kms migrate` is a manual
  alias. The only automatic migration is `bin/docker-entrypoint`, which runs
  `db:prepare` when the last two CMD words are `./bin/rails server`. The
  Dockerfile's `CMD ["./bin/thrust", "./bin/rails", "server"]` satisfies it.
  Change that CMD (for example to `bundle exec puma`) and migrations silently
  stop running.
- **Code that depends on a new column breaks hard if it boots first.** Rails
  raises at class load for an `enum` with no column. So `Conversation#kind` and
  `User#support_account` are declared with `attribute`: without the column,
  the app still boots and reads defaults. Do the same for any future
  migration-dependent enum or flag read on a hot path.

## Admin

- `/admin/support_conversations`: the inbox, threads awaiting a reply first
  (ordered in SQL, so it holds across pages).
- A thread page with a reply box, plus Close and Reopen. Opening a thread marks
  the user's messages read.
- Replies are posted as the Support account. `messages.admin_user_id` records
  which admin wrote each one; it is never serialized. Every reply, close, reopen
  and start is in the audit log.
- The user's admin page links to their thread, and offers "Start" only when the
  flag is on.
- The navigation shows **Support N** on every admin page, where N counts
  threads waiting on a reply (threads, not messages, so one chatty user can't
  swamp it).
- The inbox and an open thread poll by reload every 30 s, with no websockets
  in the admin. The thread page skips the reload while the reply box has text,
  so a draft is never lost. The inbox paginates (25 a page).
- The support views use inline styles, like `admin/users/show` and the
  dashboard. That's expedience for an internal tool, not the house pattern to
  copy.

Verified end to end on the dev server (2026-10-01):
1. A user signed in through the API and opened support.
2. They sent a message; an offer was refused (422).
3. The thread appeared first in the admin inbox, bold, with the badge on every
   page.
4. The admin replied in Chrome.
5. The reply came back on the user's side, sent by the Support account (id 605),
   with the user's message now marked read.
6. A typed draft survived a refresh tick.
7. The user's admin page opened the same thread.

Not exercised: delivery of the push to a real device (the test user had no push
token). The localized title is covered by a spec.
