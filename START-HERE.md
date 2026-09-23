# Versa Quick Game — first implementation

Prepared for Cindy · September 23, 2026 · Version 0.1.0

A native iPhone app, a separate mobile invitation website, and a shared Supabase database. This is an initial implementation for online use, with fictional demos. It is not a published app or a configured live service.

## Start here

1. Read **SETUP-CHECKLIST.md** for the accounts and settings you need.
2. On a Mac, open **ios/VersaQuickGame.xcodeproj** with Xcode 16.3 or newer. Choose an iPhone simulator and run **Try the demo**. No backend account is needed for the demo.
3. For the browser demo, install Node.js 24, open a terminal in this folder, and run:

   ```sh
   npm ci
   npm run dev:demo
   ```

   Open the local URL Vite prints. Use any valid-looking fictional email and code **123456**. The demo has separate controls to preview host approval and a final score. It sends no email and creates no real invitation.
4. Follow the checklist to create the Supabase project and deploy the invitation site. Then set the public configuration in iOS and test with two real accounts.

## What is included

| Area | Implemented in this source |
|---|---|
| iPhone Play | Concise saved place/time/format, expandable Edit, always-visible court field, four players in two teams, saved-player selection, game creation |
| Sharing | QR, native Share invitation, and Copy link in the iPhone app; Messages/AirDrop appear when supported by the device |
| Guest joining | Email code sign-in, choose a guest spot, host approval; unclaimed spots use `Guest - Nickname` |
| Results | Host-entered final score, corrections, version checks, separate participant confirmations |
| History | Game list, date range, player search, 30-game pagination |
| Summary | All-time overall wins/losses; search a player, then compare BOTH teammate and opponent results by month, year, or custom dates |
| Groups | Private, overlapping player pools; never an eligibility restriction |
| Settings | Profile, saved clubs, default club, add a club, support/privacy/terms, sign-out and account deletion |
| Browser | Only the invited game: view, sign in, claim, pending approval, result, confirmation, account deletion/sign-out |
| Backend | Private PostgreSQL tables, permission-checked RPCs, invite expiration/revocation/rotation, stable player IDs, score-change audit |
| Branding | Original forest-green, cream, and lime paddle/ball mark, iOS icon assets, website icons |
| Marketing | Separate update package for the existing VersaGal Digital repository; overview, support, privacy, terms, account deletion |

The browser intentionally has no Create Game, History, Summary, Groups, or club settings. Android players can use the invitation link without installing an app.

## Project map

- `ios/`: native SwiftUI source, Xcode project, core Swift tests, public configuration examples, privacy manifest.
- `web/`: TypeScript invitation application for Cloudflare Pages; separate from versagaldigital.com.
- `backend/migrations/`: three ordered Supabase SQL migrations, including date queries for both teammate and opponent results.
- `backend/tests/`: real PostgreSQL/PLpgSQL checks using PGlite.
- `backend/email-templates/`: sign-in code email template for Supabase.
- `brand/`: original generated logo and production-size assets.
- `docs/`: architecture, release details, and validation report.
- `.github/workflows/check.yml`: database/web/browser checks and a macOS iOS build job.

## Verified and still pending

The database suite and the browser integration flow passed locally. The website built with TypeScript checking and with configured test settings. Swift source was syntax-parsed, and plist/project structure was checked. The marketing pages were checked for local links and layouts at 320, 390, and 1440 pixels.

**Xcode compilation, simulator/device behavior, real email delivery, actual Supabase deployment, universal links, and TestFlight have not been run here.** The browser integration test simulates authentication delivery and PostgREST HTTP while executing the real database migration; it is not a live Supabase test.

The existing website updates are prepared on branch `feat/versa-quick-game`. GitHub write access was unavailable, so nothing has been pushed or published. The update package includes a Git patch and the changed files.

## First-version limits

- Live use requires internet. There is no offline save/sync queue, push notification service, live point-by-point scoreboard, tournament bracket, or rating calculation.
- Game setup supports singles and doubles, 11/15/21 points, side-out or rally, win by 1/2. The format is used to validate the final score; the app does not officiate rallies.
- Saved player pools belong to each account. Shared groups are private to invited account members; their game views and leaderboards recalculate from current memberships and approved game spots. Nicknames alone do not establish membership. There is no public club directory or group chat.
- Choose an existing saved player for repeat games to keep that person’s stats together. Typing a new nickname creates a new player record. Names are never automatically merged. The immediate next game reuses the just-created players’ IDs.
- Accounts are linked to individual game spots after host approval, not retroactively to every similarly named guest. Different hosts’ saved pools are not automatically reconciled. Personal overall totals include approved games across hosts; player-specific totals may have separate entries across those pools.
- The host cannot edit teams/participants after creating a game in this version. There is no individual-game deletion control yet. Account deletion removes the account’s hosted games, which also changes participants’ histories. Confirm setup before sharing.
- Game invitations do not expire. The host can revoke or rotate a link; approved participants can still open the game through History. Treat an active link as access to that game’s place, time, player names, and score.
- Shared groups use a copied invitation code for now. Members may invite other account holders; only the group creator changes the game eligibility rule. A partner without a verified account still counts in a member's individual doubles results but is excluded from the partner leaderboard until claimed.
- Apple distribution settings, email sender, domain, backups, public policy details, and launch availability need the checklist completed.

No runtime DUPR, OpenAI, Twilio, or Bluetooth service key is required. You control the game data in your database; it can be exported and migrated.
