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
- **Welcome on sign-up (2026-10-02, owner's request).** A new account gets one
  welcome from Support in its language (`support.welcome`), from
  `WelcomeSupportMessageJob`. It is queued by the two sign-up doors only
  (email registration, new Google account), never by a model callback, so
  seeds and backfills still create no thread. It goes through
  `admin_support_thread_for`, so it obeys `SUPPORT_ADMIN_INITIATE`, and it is
  skipped if the thread already has any message.
- **ON in production since 2026-10-03** (mobile 1.1.4 went live on iOS and Android that day). It was off until then
  (owner, 2026-10-02): older apps draw the Support thread poorly. Switch:
  `WELCOME_SUPPORT_MESSAGE=true`. It is deliberately absent from
  `config/deploy.yml` env, so a deploy cannot turn it on; enabling it for 1.1.4
  means adding it there and to `.env.production` / `.kamal/secrets`.
  The Support account is created on first use; an account alone is invisible.

**Known limit, not solved:** a user who updates, opens support, and then also
uses v1.0.4 on a second device sees that thread there as a removed-listing chat.

### Admin-initiated threads: ON (owner's decision, 2026-10-01)

The owner turned it on: "we dont care if they have app or not its a message …
we should able to send message". A message is not a notification — it waits in
the chat until they next open the app. A v1.0.4 user still receives it; their
Support chat may look like a removed-listing chat, and the admin compose screen
says so ("hasn't used the new app yet") without blocking. The gate
(`Conversation.admin_can_message?`), its structural guard spec and the
per-recipient re-check all stay: the flag is one of the gate's conditions, not
a reason to remove it. It is wired in `.env.production`, `.kamal/secrets` and
`config/deploy.yml` `env.secret`.

### Turning on admin-initiated threads (how it was done)

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

## Archived threads

A user can archive or delete their support thread. Neither affects the admin:
both are per side (`buyer_*` columns, and the user is always the buyer), and
the admin inbox filters on neither. **Any new message in the thread, from
either side, brings it back** into the user's inbox, still unread. So does
tapping "Contact support" again (`Conversation#resurface_support_thread!`).

### Finding: the same gap exists for every conversation, live today

Listing threads do **not** do this. Nothing un-archives a conversation except
the explicit `PUT /conversations/:id/unarchive`. In the shipped app today:

1. a buyer archives a thread;
2. the seller replies;
3. the inbox still hides it (`not_archived_for` needs `buyer_archived_at IS NULL`);
4. **but `SendMessagePushJob` does not check archive state, so the buyer still
   gets a push for a message they then cannot find** in the inbox.

A notification that points at a thread not in the inbox is worse than none. On
a marketplace, a buyer can miss a seller's answer and neither side knows why.

**Owner's decision, not made here.** Extending resurfacing to listing threads
is additive to the API, but it is a visible behaviour change for every user,
v1.0.4 included: threads they archived would start reappearing when the other
side writes. The options are support only (as now), or all conversations. A
spec pins listing threads to today's behaviour, so the change can't happen by
accident.

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
