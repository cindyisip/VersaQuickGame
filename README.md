# Versa Quick Game

Native iPhone pickleball game records, a limited mobile invitation website, and a Supabase backend. No ratings or DUPR connection.

Read **[START-HERE.md](START-HERE.md)**, then **[SETUP-CHECKLIST.md](SETUP-CHECKLIST.md)**.

```sh
npm ci
npm run dev:demo
```

For iOS, open `ios/VersaQuickGame.xcodeproj` on a Mac with Xcode 16.3+. Try the fictional demo before configuring the backend.

```sh
npm run check
npx playwright install chromium
npm run test:browser
```

See `docs/VALIDATION.md` for what was actually run and what remains unverified. This is prerelease source, not a live deployment.
