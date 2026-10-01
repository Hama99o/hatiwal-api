# Push notifications

Chat pushes (messages, offers, meetups, Support replies) are sent by
`SendMessagePushJob` through Expo (`Notifications::ExpoPushService`) to the
recipient's `users.push_token`. The title is the sender's name, or for a
Support reply `push.support.title` in the recipient's language. The body is
the message text, or a localized label for non-text kinds.

## Finding (2026-10-01): Android has never received a push

The mobile app was never set up with Firebase for Android:

- `hatiwal-mobile/app.json` has no `android.googleServicesFile`, and the repo
  has never contained a `google-services.json`.
- The live Play build (v1.0.4, versionCode 16) has no `google_app_id` or
  `gcm_defaultSenderId` resources (checked with `aapt2 dump`). The Firebase SDK
  is bundled but never initialized.
- On a device, `getExpoPushTokenAsync` throws "Default FirebaseApp is not
  initialized in this process com.hatiwal.app".

So no Android user ever gets a `push_token`, and every Android chat push since
launch has not happened. iOS is unaffected (APNs via EAS).

**Fix (owner's accounts):** create a Firebase project for `com.hatiwal.app`,
wire its `google-services.json` in through `app.json`, upload FCM V1
credentials to EAS, then ship a new build. Nothing on the server changes.

## The lesson: the silence was doubled

Neither component was broken. The system was.

1. **The client** calls `getExpoPushTokenAsync`, it throws, and
   `registerPushToken()` catches the error and returns null without reporting
   anything. That's reasonable on its own: push permission is optional and the
   app must keep working without it.
2. **The server** sees a blank `push_token` and `SendMessagePushJob` returns
   early, logging nothing. That's also reasonable on its own: plenty of users
   have no token.

Each layer quietly did the right thing locally. Together they hid a platform
that could never receive a notification, for months, with no error anywhere.

What closes it now:

- **The admin dashboard** shows "Push notifications — can they reach people?":
  for each platform, users seen in the last 30 days and how many hold a token
  (`User.push_reach_since`). Every platform is listed, zeros included. A zero
  next to real users is shown in red. A count nobody has to remember to run is
  the point.
- **A Support reply** to a user with no token logs a warning
  (`[push] Support reply … not pushed`), and the admin's thread page tells them
  before they write that the user won't get a notification.
- **Still open (mobile):** `registerPushToken()` should report its failure
  somewhere a person sees it. Swallowing it is what made the client half silent.

When a failure is expected and tolerated at one layer, check that some other
layer still counts it. Otherwise "tolerated" turns into "invisible".
