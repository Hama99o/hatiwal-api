# Google sign-in (1.1.7: Android, iOS and the web)

Google sign-in is live on **hatiwal.com** (checked 2026-10-11). In the app it was hidden, because
the old browser-redirect flow (`expo-auth-session`) never completed for testers: Android was given
the WEB client id, and the iOS redirect scheme was used on every platform. 1.1.7 replaces that flow
with the native library and shows the button on Android and iOS. On iOS it sits beside Sign in with
Apple (App Store guideline 4.8).

> **OFF in the 1.1.7 app (owner rule, 2026-10-12): it does not ship until the console setup below
> is done.** The app code and tests are in place, but the button is hidden unless
> `EXPO_PUBLIC_GOOGLE_SIGN_IN=on`, and `app.json` carries no google-signin plugin, so a build
> succeeds without the Google clients. The web keeps its 1.1.6 Google sign-in unchanged (web
> fb10810 was reverted by fcbf9b7), and `/auth/google` stays on for it. See "Turning it on" at the
> end.

## How it works

1. **App** (`hatiwal-mobile`, `src/components/auth/GoogleSignInButton.tsx`) uses
   `@react-native-google-signin/google-signin` (MIT, the free "Original" API). That gives Android's
   native account picker and Google's iOS sheet.
   - It is configured with `{ webClientId, iosClientId }`. Because of `webClientId`, Google issues
     the **ID token for the web client** (that is its `aud`), on both platforms.
   - It is shown on Login and Register by `src/lib/googleSignIn.ts`:
     - **One flag, OFF by default.** `EXPO_PUBLIC_GOOGLE_SIGN_IN=on` shows it.
     - Even then it is hidden with no web client id, and on iOS with no iOS client id.
   - A cancelled sheet is silent.
2. **Web** (`hatiwal-web`, `src/components/auth/login-form.tsx`) uses Google Identity Services with
   `NEXT_PUBLIC_GOOGLE_CLIENT_ID`. Its token also carries the web client's `aud`.
3. **API**: `POST /api/v1/auth/google` with `{ id_token }`
   (`Api::V1::Auth::GoogleAuthController`).
   - The token is checked with Google's `tokeninfo` endpoint.
     - `aud` must be `google_client_id` (web) or `google_ios_client_id` from credentials.
     - In production, with neither set, **every** token is refused (fail closed).
   - The address must be verified by Google (`email_verified`).
   - The person is found by email, otherwise a new, confirmed account is created (provider `google`).
     - An existing **unconfirmed** account with that email may be a squatter's, so it is claimed:
       it is confirmed, given a new random password, and every other session is ended (1.1.6
       378b1dc, 1.1.7 eda6487).
     - A confirmed account is signed in untouched.
   - The response is the same session as email sign-in: the tokens in the body. Blocked or
     deleted accounts get the same 403 as email login.
   - Error codes (1.1.7), translated in en, ps, fa and ur:

     | Code | Status | Meaning |
     |---|---|---|
     | `google_token_missing` | 422 | no `id_token` was sent |
     | `google_token_invalid` | 401 | the token is bad, expired, or for another app |
     | `google_email_unverified` | 401 | Google has not verified the address; nothing is linked or created |
     | `google_email_missing` | 422 | Google shared no email address |

     The app also reports a phone without (or with outdated) Google Play services.

## The owner's one-time setup (Google Cloud console → APIs & Services → Credentials)

All three OAuth clients live in **the same Google Cloud project** as the existing web client
(`1090253359225-…`).

1. **Web client** (exists; used by hatiwal.com and, as `webClientId`, by the app).
   - Authorized JavaScript origins: `https://hatiwal.com`, `https://www.hatiwal.com`. Add
     `http://localhost:3011` for local web dev.
   - No redirect URIs are needed: GIS and the native SDKs return the token directly.
2. **Android client**: create it if it is missing (**Create credentials → OAuth client ID →
   Android**).
   - Package name: `com.hatiwal.app`.
   - SHA-1: the **Play app-signing key**. In Play Console → Hatiwal → *Test and release → App
     integrity → App signing*, copy the "App signing key certificate" **SHA-1** fingerprint
     (20 pairs). The same box also shows a **SHA-256**, the one starting `03:F6…` and used for
     Android App Links; that is the **wrong** one here, and Google's form rejects it. Every build
     installed from Play is signed with this key, so without its SHA-1 sign-in fails on every store
     install with `DEVELOPER_ERROR`.
   - Add a **second Android client** with the same package and the **upload key's** SHA-1. Builds
     installed straight from EAS (the QA APK, internal distribution) are signed with it. Run
     `eas credentials -p android` → production → it prints the keystore's SHA-1. No build is needed.
   - The app needs no Android client **id**: Google matches the client by package and signature.
3. **iOS client**: create it if it is missing (**OAuth client ID → iOS**).
   - Bundle ID: `com.hatiwal.app`.
   - Its **reversed client id** must be the `iosUrlScheme` in the app's `app.json` (the
     `@react-native-google-signin/google-signin` plugin), today
     `com.googleusercontent.apps.1090253359225-rkd9q458daerb2venp697gq7gelfcrhr`. If the console
     shows a different iOS client, change that line to match **before** the 1.1.7 build.
4. **OAuth consent screen**: publishing status **In production** (not Testing, which only lets
   listed test users in), with the app name, logo and privacy-policy URL. Scopes are only
   `openid`, `email` and `profile` (non-sensitive), so no sensitive-scope review is needed. Google may
   still ask for brand verification before it shows the logo on the consent screen.

## Configuration

| Where | Name | Value |
|---|---|---|
| EAS env (production) | `EXPO_PUBLIC_GOOGLE_CLIENT_ID` | the **web** client id |
| EAS env (production) | `EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID` | the **iOS** client id (matches `iosUrlScheme`) |
| EAS env | `EXPO_PUBLIC_GOOGLE_SIGN_IN` | `on` shows the button. Unset (the default) hides it |
| API credentials | `google_client_id` | the web client id |
| API credentials | `google_ios_client_id` | the iOS client id. Only needed if a token's `aud` is ever the iOS client (it is the web client with `webClientId` set) |
| web `.env.production` | `NEXT_PUBLIC_GOOGLE_CLIENT_ID` | the web client id (already set) |

Client ids are not secrets, but they still live in env and credentials, never in committed code.
When it is turned on, `app.json` carries the reversed iOS client id only because the native plugin
needs it at build time.

## Deploying it

- **API**: no migration. The coded errors are additive: older apps read only the status.
- **App**: needs a **native 1.1.7 build** (EAS), because a new native module was added. There is no
  Expo Go path. Do the console steps above **first**: a missing SHA-1 shows the button but fails
  sign-in.
- **Testing**: no device test has been done yet. The first check is on the 1.1.7 build from Play
  internal testing (app-signing SHA-1) and on the EAS-installed QA APK (upload SHA-1). The behaviour
  is covered by:
  - API: `spec/requests/api/v1/auth/google_auth_spec.rb`.
  - App: `GoogleSignInButton.test.tsx`, `googleSignIn.test.ts` and `authErrors.test.ts`.

## Turning it on (the app)

In this order:

1. **Console**: the owner's one-time setup above (Android clients with the app-signing SHA-1 and
   the upload-key SHA-1, the iOS client, the consent screen in production).
2. **App config**: in `hatiwal-mobile/app.json`, add back to `plugins`:
   `["@react-native-google-signin/google-signin", { "iosUrlScheme": "com.googleusercontent.apps.<the iOS client>" }]`
   (removed on 2026-10-12; the commit that removed it shows the exact lines).
3. **App env**: in the EAS env of the build profile, set `EXPO_PUBLIC_GOOGLE_CLIENT_ID`,
   `EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID` and `EXPO_PUBLIC_GOOGLE_SIGN_IN=on`.
4. **Web (optional)**: re-apply web fb10810 (reverted by fcbf9b7) for the unverified-address
   sentence on hatiwal.com.
5. **Build** new Android and iOS builds (EAS); check sign-in on the Play internal track
   (app-signing SHA-1) and the EAS-installed APK (upload SHA-1) before release.

The API needs nothing: `/auth/google` is already on for the web.
