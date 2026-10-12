# Sign in with Apple (1.1.7 — iOS first)

Owner decision, 2026-10-09: Sign in with Apple on **iOS only** first; Google later. App Store
guideline 4.8 asks for it as soon as an app offers a third-party login on iOS, and it gives people
a private-relay address if they do not want to share their email.

> **OFF in 1.1.7 (owner rule, 2026-10-12): it does not ship until the console setup below is
> done.** The code and tests are in place, but the API answers `POST /auth/apple` with 404 unless
> `APPLE_SIGN_IN_ENABLED` is set, the app hides the button unless `EXPO_PUBLIC_APPLE_SIGN_IN=on`,
> and `app.json` carries no Sign in with Apple config, so a build succeeds without the App ID
> capability. See "Turning it on" at the end.

## How it works

1. **App** (`hatiwal-mobile`, `src/components/auth/AppleSignInButton.tsx`). Apple's own button, on
   Login ("Sign in") and Register ("Sign up"). It shows only when `Platform.OS === "ios"` and
   `AppleAuthentication.isAvailableAsync()` is true.
   - It makes a random **raw nonce** and sends only its **SHA-256** to Apple (`signInAsync`).
   - Apple returns an identity token (a JWT it signs, carrying that hash), a one-time
     authorization code, and on the **first** sign-in only the person's name.
2. **API** `POST /api/v1/auth/apple` (`Api::V1::Auth::AppleAuthController`), with `identity_token`,
   the raw `nonce`, `authorization_code`, and `given_name` / `family_name` (first time only).
   - `Apple::IdentityToken.verify` checks:
     - the RS256 signature against Apple's keys (`https://appleid.apple.com/auth/keys`, cached
       12 h, re-fetched when Apple rotates);
     - `iss` = `https://appleid.apple.com`;
     - `aud` = our bundle id(s);
     - `exp`;
     - `nonce` = SHA-256(raw nonce). This stops a token taken from one sign-in being replayed.
   - The person is found by the Apple id (`users.apple_uid`, the token's `sub`).
   - Otherwise an existing account is **linked**, but **only if Apple says the email is verified**
     (`email_verified`). An unverified match gets `409 apple_email_unverified` and nothing is
     linked or created.
   - Otherwise a new account is created: provider `apple`, the token's email, which may be a
     `…@privaterelay.appleid.com` address, confirmed because Apple verified it, and the
     first-sign-in name. If Apple sent no name, the account is named "User .".
   - The response is the same session as email sign-in: devise_token_auth headers **and** the
     tokens in the body, like `/auth/google`. Blocked or deleted accounts get the same 403 as
     email login.
   - Error codes: `apple_token_missing` (422), `apple_token_invalid` (401),
     `apple_email_unverified` (409), `apple_email_missing` (422). The app translates them in
     en, ps, fa and ur (`auth.apple.*`).
3. **Account deletion revokes Apple's authorization** (guideline 5.1.1(v)).
   - At sign-in, the authorization code is exchanged for a **refresh token**
     (`Apple::Tokens.exchange`), stored **encrypted** in `users.apple_refresh_token`.
   - `User#anonymize_account!` forgets `apple_uid` and the token, then queues `AppleRevokeJob`.
     The token travels encrypted in the job arguments. The job calls
     `POST https://appleid.apple.com/auth/revoke`.
   - Both calls authenticate with a 5-minute ES256 **client secret** signed by the
     Sign-in-with-Apple key.
   - **Without that key, both are logged no-ops** (`[apple] Sign in with Apple key not
     configured …`). Sign-in itself needs no secret and works either way.

## The owner's one-time setup (Apple Developer → Certificates, Identifiers & Profiles)

1. **App ID** `com.hatiwal.app` → Capabilities → tick **Sign In with Apple** → Save. EAS uses it
   at the next build, once `app.json` has `ios.usesAppleSignIn: true` and the
   `expo-apple-authentication` plugin again (see "Turning it on").
2. **Keys** → **+** → name it "Hatiwal Sign in with Apple" → tick **Sign in with Apple** →
   Configure → primary App ID `com.hatiwal.app` → Continue → Register → **Download** the `.p8`.
   Apple lets you download it **once**. Note the **Key ID** shown on that page.
3. The **Team ID** is at the top right of the developer site (Membership).
4. A **Services ID** is needed only for Sign in with Apple **on the web**, which is not part of
   1.1.7. Skip it for now.

## Configuration (API)

The API reads these from **credentials** (`bin/rails credentials:edit`) or from **ENV**; credentials
win when both are set.

| credentials `apple:` | ENV | What |
|---|---|---|
| `team_id` | `APPLE_TEAM_ID` | the Team ID (10 characters) |
| `key_id` | `APPLE_KEY_ID` | the Sign in with Apple key's ID |
| `private_key` | `APPLE_PRIVATE_KEY` | the `.p8` contents (PEM; `\n` escapes are accepted in ENV) |
| `client_id` | `APPLE_CLIENT_ID` | the iOS bundle id, `com.hatiwal.app` |
| `bundle_ids` | `APPLE_BUNDLE_IDS` | optional: accepted token audiences (comma-separated in ENV); default `com.hatiwal.app` |

```yaml
# bin/rails credentials:edit  (production)
apple:
  team_id: XXXXXXXXXX
  key_id: XXXXXXXXXX
  client_id: com.hatiwal.app
  private_key: |
    -----BEGIN PRIVATE KEY-----
    …
    -----END PRIVATE KEY-----
```

The `.p8` is a secret: it goes in credentials or in `.env.production` and its Kamal secret, never in
git. With nothing configured, verification still works and revocation is a logged no-op.

## Deploying it

- **API**: migration `20261009220000_add_apple_sign_in_to_users` (`users.apple_uid` unique,
  `users.apple_refresh_token` encrypted). Additive; run `db:migrate` with the deploy as usual.
- **App**: needs a **native build** (EAS, 1.1.7); there is no Expo Go path. The button only
  appears on iOS. Android is unchanged.
- **Testing**: only possible on a real 1.1.7 TestFlight build signed with the App ID that has the
  capability, so no device test has been done yet. The behaviour is covered by
  `spec/requests/api/v1/auth/apple_auth_spec.rb`, `spec/services/apple/tokens_spec.rb`, and in
  the app by `AppleSignInButton.test.tsx`, `auth.apple.test.ts` and `authErrors.test.ts`.

## Turning it on

In this order. Until every step is done, leave it off: a build that asks for the entitlement
without the App ID capability fails to sign.

1. **Console**: the owner's one-time setup above (App ID capability, key, Team ID).
2. **API**: put the `apple:` credentials (or the ENV) in production, and set
   `APPLE_SIGN_IN_ENABLED=true` in the API's env (`.env.production` + Kamal env). Deploy.
   `POST /api/v1/auth/apple` then answers instead of 404.
3. **App config**: in `hatiwal-mobile/app.json`, add back `"usesAppleSignIn": true` under `ios`
   and `"expo-apple-authentication"` to `plugins` (both were removed on 2026-10-12, so the commit
   that removed them shows the exact lines).
4. **App flag**: set `EXPO_PUBLIC_APPLE_SIGN_IN=on` in the EAS env of the build profile.
5. **Build** a new iOS build (EAS) and check on TestFlight before release.
