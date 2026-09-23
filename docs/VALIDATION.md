# Validation report

September 23, 2026 · source version 0.1.0

## Completed here

| Check | Result | Scope |
|---|---|---|
| `npm test` | **12 passed** | All three migrations and PL/pgSQL executed by PGlite; simulated Supabase auth schema and anonymous/authenticated roles |
| `npm run build` | **Passed** | Strict TypeScript checking and Vite production build, both unconfigured and with fictional public test configuration |
| `npm run test:browser` | **Passed** | Chromium + real Supabase JS client + real SQL functions; simulated email verification and PostgREST HTTP adapter |
| Swift syntax parsing | **Passed** | All app/core/test Swift source parsed with tree-sitter-swift; this is not compilation or SDK type checking |
| Native project/assets | **Passed static checks** | Regenerated deterministic project, resolved source references, plist/XML parsing, 1024px RGB app icon |
| Marketing links | **Passed** | All 16 HTML pages checked for local link/asset/anchor targets and duplicate IDs |
| Marketing layout | **Passed** | Home, Apps, and five new Quick Game pages at 320, 390, and 1440px; no horizontal overflow, missing images, or JavaScript errors |
| Visual inspection | **Completed** | Mobile invitation/result light and dark layouts, and mobile/desktop marketing overview |

The database tests cover private-table denial, ownership checks, saved clubs, idempotent game creation, invitation data minimization, pending and approved claims, occupied spots, host-only score changes, score rules and revision conflicts, confirmation invalidation, team-aware summary, teammate and opponent month/year windows sharing a selected range without changing the all-time overall total, overlapping groups, invitation revocation/rotation, and account deletion.

The browser integration test walks through invalid and valid email codes, claim request, host approval, an opponent’s loss, score confirmation, host correction, retained login after reload, 320px dark layout, connection failure/retry, standalone account deletion without a game token, invalid invitations, and absence of app-only routes. An HTML-like nickname is rendered as text, not executed.

## Not verified in this environment

- Xcode compilation, Swift core test execution, simulator rendering, or a physical iPhone.
- Native QR scanning, Messages/AirDrop share behavior, universal links, accessibility/VoiceOver, and App Store/TestFlight signing.
- A real Supabase project’s auth schema, permissions, SMTP delivery, rate limits, or production concurrency/load.
- Actual Cloudflare response headers/DNS/association delivery. The local test server does not reproduce Cloudflare’s header processing.
- A GitHub Actions run. Workflows are supplied but have not run in Cindy’s new repository.
- Public website deployment. A dry-run Git push failed because GitHub credentials were not available. No remote changes were made.

## Reproduce locally

Use Node.js 24 and run from the repository root:

```sh
npm ci
npm run check
npx playwright install chromium
npm run test:browser
```

Linux may need `npx playwright install --with-deps chromium`. The browser test builds with fictional settings and leaves that local build in `web/dist`; run `npm run build` with your intended environment before deploying. Build output is not part of the source package. Optional `CHROMIUM_EXECUTABLE` and JSON `CHROMIUM_ARGS` environment values support a preinstalled browser.

On a Mac:

```sh
swift test --package-path ios
xcodebuild -project ios/VersaQuickGame.xcodeproj -scheme VersaQuickGame -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

If Swift files are added or removed, regenerate the source project with `python3 scripts/generate-xcode-project.py`. Do not use regeneration to overwrite intentional Xcode project changes without reviewing the generator.

The complete live two-account test is in SETUP-CHECKLIST.md. These automated checks support an initial implementation; they do not establish production readiness.
