# Versa Quick Game — accounts and setup checklist

Prepared September 23, 2026. Start with the demos; complete the live setup before inviting friends.

## 1. Accounts to create or reuse

| Account | Create or reuse? | What it does | What you need from it |
|---|---|---|---|
| **GitHub** | Reuse `cindyisip` | Stores source and connects to hosting/build checks | New repository for Versa Quick Game; access to existing `VersaGalDigitalWebsite` |
| **Apple Developer / App Store Connect** | Reuse your membership if active | App signing, TestFlight, App Store | Apple Team ID; a registered bundle ID; signing through Xcode |
| **Supabase** | Create an account or reuse one; create a **new project** | User accounts, authentication, PostgreSQL game data | Project URL and **publishable** API key; securely stored database password |
| **Cloudflare** | Create or reuse | Hosts the separate invitation website | A Pages project connected to the new GitHub repository |
| **Email delivery provider** | Reuse a compatible SMTP sender, or create one such as Resend | Delivers sign-in codes through Supabase | Verified sending domain/address; SMTP host, port, username, password/API key |
| **Domain registrar** | Optional initially | A memorable invitation domain | A domain you own and DNS access; a `pages.dev` address works for initial testing |

You do not need a separate account for the logo, direct SMS, raw Bluetooth, DUPR, OpenAI API, or Sign in with Apple for this implementation. Native sharing uses the device’s share sheet; it does not send messages automatically.

A Mac with **Xcode 16.3+** is needed to build the iPhone source. The deployment target is **iOS 17+**. The initial Swift SDK version is pinned to Supabase Swift 2.55.2, which uses Swift tools 6.1. Use an Xcode version Apple accepts at the time you submit to the App Store.

## 2. Keys and identifiers: where each belongs

| Item | Secret? | Where to put it |
|---|---|---|
| Supabase project URL | No | Cloudflare build variable `VITE_SUPABASE_URL`; iOS `SUPABASE_URL` |
| Supabase **publishable key** (`sb_publishable_…`) | No | Cloudflare `VITE_SUPABASE_PUBLISHABLE_KEY`; iOS `SUPABASE_PUBLISHABLE_KEY` |
| Supabase secret/service-role key | **Yes** | Not needed by this source. Never place in an app, browser variable, repository, or screenshot |
| Database password / direct connection string | **Yes** | Password manager; administrative migration/backup tools only |
| SMTP password or sending API key | **Yes** | Supabase Authentication → custom SMTP settings only |
| Apple Team ID | No | iOS `DEVELOPMENT_TEAM`; Cloudflare `APPLE_TEAM_ID` |
| App bundle identifier | No | iOS `PRODUCT_BUNDLE_IDENTIFIER`; Cloudflare `APPLE_BUNDLE_ID` |
| Invitation hostname | No | iOS `INVITE_HOST`; Cloudflare Pages/custom-domain settings |
| GitHub personal access token | **Yes**, if used | Not needed in application configuration. Use GitHub’s normal Git authentication or connected tools |
| Supabase CLI access token | **Yes**, optional | Only required if you later choose CLI automation; not required for the SQL-editor setup below |
| Cloudflare API token | **Yes**, optional | Not needed for the Git-connected Pages workflow below |
| Apple `.p8` key / App Store Connect API key | **Yes**, optional | Not required for manual Xcode signing/upload; no Sign in with Apple implementation is included |

Public keys identify the project; the database functions enforce access. Do not paste private credentials into chat. The example configuration files contain placeholders only. Local live configuration files are ignored by Git.

## 3. Create the backend

- [ ] Create a new Supabase project under an organization you control. Choose a suitable region and store the database password securely.
- [ ] In the SQL editor, run **`backend/migrations/202609230001_initial.sql` once**. It is an initial migration, not a reset/re-run script. Do not run it against an existing unrelated database.
- [ ] Then run **`backend/migrations/202609230002_opponent_periods.sql`**. It adds the opponent date range query without changing existing games.
- [ ] Then run **`backend/migrations/202609230003_teammate_periods.sql`**. It adds the teammate date range query. If the previous checklist led you to run migrations 001 and 002 already, run only 003 now. Run each migration only once and in filename order.
- [ ] Confirm the project exposes the `public` API schema and **does not expose `private`**. Do not grant direct table access or create blanket “allow all” policies. These tables deliberately have no direct client-access policies; the app calls checked functions.
- [ ] Copy the project URL and **publishable** key from the project’s API settings.
- [ ] Enable email authentication, email confirmation, and new-user signup. Use email codes, not passwords or a magic-link-only template. Leave phone/social/anonymous sign-in off unless added later.
- [ ] Configure custom SMTP using your verified sending domain. For example, use a dedicated sending subdomain of a domain you control. Add the provider’s requested DNS records and verify them; preserve existing mail records.
- [ ] Set a sender name such as **Versa Quick Game** and a verified From address. Ensure support and privacy addresses can receive messages.
- [ ] In Supabase email templates, use **`backend/email-templates/sign-in-code.html`** for the sign-in/Magic Link email and the signup confirmation template if that flow uses it. Preserve `{{ .Token }}`. Both clients verify `type: email`.
- [ ] Choose a code lifetime and rate limits suitable for your beta. Test that resending a code and code expiry behave as expected. The interfaces wait at least a minute before resending.
- [ ] Set the Auth Site URL to the eventual invitation-site HTTPS URL. Codes are entered in the same app/browser flow, so the implementation does not rely on an OAuth callback or auth token in the invitation fragment.
- [ ] Test delivery to a non-team Gmail/Outlook address before inviting the group.

**Why SMTP is on the checklist:** Supabase’s default sender is restricted to project-team addresses and is intended for testing, with a low rate limit. A project that works for your own email may fail for friends until custom SMTP is configured. See [Supabase SMTP](https://supabase.com/docs/guides/auth/auth-smtp) and [email-code authentication](https://supabase.com/docs/guides/auth/auth-email-passwordless).

## 4. Put the new source in its own repository

- [ ] Create a repository such as **`VersaQuickGame`** under your GitHub account. A private repository is fine.
- [ ] Upload or commit this source, including hidden `.github` and `.gitignore` files, the package lockfile, and `web/.env.demo` / `web/.env.example`. Do not upload `node_modules`, build output, personal signing files, or live `.env` / `Local.xcconfig` files.
- [ ] Allow the included checks to run. The macOS job is the first compilation check of the iOS app; resolve any build findings before distributing it.
- [ ] Keep the existing marketing repository separate. Its update is in **VersaGalDigitalWebsite-QuickGame-Update.zip**.

## 5. Deploy the invitation website

Use a Cloudflare **Pages** project with Git integration, not a Worker-only project.

- [ ] Connect the new VersaQuickGame repository.
- [ ] Framework preset: **None**. Root directory: **leave blank / repository root**.
- [ ] Build command: **`npm ci && npm run build`**.
- [ ] Build output directory: **`web/dist`**.
- [ ] Set `NODE_VERSION` to **24** if the environment needs an explicit version.
- [ ] Set these build variables for the environment being deployed:

  ```text
  VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
  VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_PUBLIC_KEY
  APPLE_TEAM_ID=YOUR_10_CHARACTER_TEAM_ID
  APPLE_BUNDLE_ID=com.versagaldigital.versaquickgame
  ```

- [ ] Do **not** set `VITE_DEMO` for production or deploy using `build:demo`. The browser demo is explicitly a separate build mode.
- [ ] Choose the resulting `YOUR_PROJECT.pages.dev` hostname, or attach a separate custom invitation domain. Do not place this app under `versagaldigital.com/apps/…`; those paths are product information.
- [ ] Verify `/`, `/join/`, and `/account/` work when opened directly. A missing/invalid invitation should not show app features.
- [ ] Verify the response headers in `web/public/_headers` are active. If you later use a custom Supabase API hostname, update the CSP `connect-src` allowlist before deploying it.
- [ ] Verify `https://YOUR_INVITE_HOST/.well-known/apple-app-site-association` returns JSON over HTTPS without a redirect and lists the correct Team ID and bundle ID. The build generates this file from the Apple variables.

Without an Apple Team ID, the browser still builds with no universal-link association. Add the Team ID and rebuild when ready. Environment changes require a rebuild. See [Cloudflare Git integration](https://developers.cloudflare.com/pages/configuration/git-integration/) and [Pages headers](https://developers.cloudflare.com/pages/configuration/headers/).

## 6. Configure and build iOS

- [ ] Register an explicit Apple App ID, for example **`com.versagaldigital.versaquickgame`**, if available. Enable Associated Domains. Use your actual chosen identifier in both iOS and Cloudflare.
- [ ] Copy `ios/Config/Local.example.xcconfig` to `ios/Config/Local.xcconfig`.
- [ ] Fill in the public Supabase URL/key, Apple Team ID, and invitation hostname. Keep the special `https:/$()/…` spelling in xcconfig files; it prevents Xcode treating `//` as a comment.
- [ ] Open `ios/VersaQuickGame.xcodeproj`. Select the VersaQuickGame scheme, your signing team, and an iPhone simulator. Let Swift Package Manager resolve dependencies.
- [ ] Build and try the demo. Then run the live setup with your configured backend.
- [ ] Run the core tests in Terminal:

  ```sh
  swift test --package-path ios
  ```

- [ ] Test on a physical iPhone: create a game, scan QR from another phone, Share invitation through Messages, Copy link, and AirDrop where supported.
- [ ] Test HTTPS universal links from Messages with the app installed; also test the browser fallback with the app absent. After installing, reopen the original invitation. This implementation does not preserve an invitation automatically through an App Store installation.
- [ ] Verify a long nickname and large accessibility text sizes on device. Native UI accessibility and VoiceOver still need device review.

The link looks like `https://YOUR_INVITE_HOST/join/#RANDOM_TOKEN`. The fragment stays out of ordinary server request logs. The token still grants access to that game’s invitation, so do not publish it. The custom app scheme `versaquickgame://join?token=…` supports the explicit “Open this game” button.

## 7. Complete a two-account court test

- [ ] Host saves a club and makes it the default. New game shows concise defaults; Edit expands and Save collapses; Court remains editable.
- [ ] Create overlapping Tuesday/Monday/Pinoy pools. Choose saved players and type an outsider.
- [ ] Share a game with a second account. The guest stays `Guest - Nickname` while waiting; only the host can approve the claim.
- [ ] Record 11–8. Check the host’s and opponent’s win/loss perspectives. Claiming alone must not count as score confirmation.
- [ ] Confirm, correct the score, and check that confirmation clears. Try stale-score confirmation and refresh.
- [ ] Filter History by date/player. Confirm the overall summary stays all-time. For one selected player, apply a single date range to both WITH and AGAINST. Check this month versus the prior matching dates, last full month versus the previous full month, this year versus the matching prior-year dates, last full year versus the previous year, and a custom date range versus the preceding range of equal length. Confirm each side has its own win/loss and win-rate change.
- [ ] Verify browser pages never expose app feature screens, even after sign-in or when entering `/history/` directly.
- [ ] Close and renew an invitation. Check guest access and ask participants to use the replacement URL after rotation.
- [ ] In a disposable test account, test deletion in iOS and at the browser’s `/account/` page. Verify the host-game deletion and shared-game anonymization behavior.
- [ ] Briefly disconnect the network and retry without creating duplicate games. Keep the first beta small until live access and email delivery are confirmed.

## 8. Marketing and App Store release

- [ ] Apply the website update package to `cindyisip/VersaGalDigitalWebsite`, review the diff, then merge/publish through its existing GitHub Pages workflow.
- [ ] Confirm `support@versagaldigital.com` and `privacy@versagaldigital.com` receive mail.
- [ ] Keep **In development** labels until the app is available. Add the genuine App Store URL and invitation `/account/` URL when known.
- [ ] Finalize the policy pages for the actual deployed providers, log/back-up retention, intended age audience, and support process. See `docs/PRIVACY-RELEASE.md`.
- [ ] Create an App Store Connect app record with the same bundle ID. Prepare real device screenshots, description, age rating, support/privacy URLs, and review instructions.
- [ ] Review the built app’s privacy report, SDK disclosures, export-compliance answer, and App Store privacy questionnaire. The source privacy manifest is a starting inventory, not a completed submission.
- [ ] Upload through Xcode and test using TestFlight before public release. Decide a backup/export schedule and test a restore.

## Budget notes

Start with development plans and the free `pages.dev` hostname. Before choosing paid plans, check current [Supabase pricing](https://supabase.com/pricing), [Cloudflare Pages pricing](https://pages.cloudflare.com/), [Apple membership](https://developer.apple.com/programs/), and your SMTP provider’s limits. Hosting, email, domain registration, backup retention, and usage can affect cost. This source does not enroll you in paid services or make purchases.

Supabase hosts your own game data rather than supplying someone else’s ratings. Keep administrative exports and backups so you can move the database if your hosting needs change. See [API key guidance](https://supabase.com/docs/guides/getting-started/api-keys) and [database backups](https://supabase.com/docs/guides/platform/backups).
