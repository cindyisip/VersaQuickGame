# Architecture and data ownership

## Applications

The iPhone app is SwiftUI, targeting iOS 17+, with an interchangeable `GameService`. `SupabaseGameService` calls the backend; `DemoGameService` uses isolated fictional UserDefaults data. `AppStore` publishes the signed-in profile and pools. Authentication uses Supabase email OTP and the SDK’s Apple session storage.

The invitation website is a small TypeScript/Vite application, with no history, statistics, group-management, or game-creation interface. It uses the same email account and database as iOS. Browser sessions persist in local storage. The only account-management operation exposed there is deletion/sign-out. Demo mode is separate and uses fictional state.

Both clients use a publishable project key. No privileged server key belongs in either application. There is no custom Node server to deploy; Supabase exposes the checked database functions through PostgREST.

## Core records

| Table in `private` | Role |
|---|---|
| `profiles` | One account display name and selected default club |
| `clubs` | Account-owned saved places, deduplicated by normalized name within that account |
| `players` | Account-owned stable player-pool identity; nickname is not an identity key |
| `player_groups`, `group_members` | Reusable, overlapping pools |
| `games` | Host, location snapshot, time, format, score, revision |
| `game_players` | Four ordered slots; 0/1 Team A, 2/3 Team B; optional pool and claimed account links |
| `invites` | Random token, expiration, closed flag; one current link per game |
| `claims` | One account’s request for one game slot, pending/approved/declined |
| `confirmations` | A joined player’s confirmation of one score revision |
| `score_changes` | Audit history of score revisions without free-text comments |

The host is slot 0. Creating a game assigns or creates stable pool IDs for the other three players but does not give them accounts or mark them claimed. An approved claim links only that slot. Names are never used for automatic identity merging.

## Operations

`bootstrap`, `save_profile`, `add_club`, `add_player`, and `save_group` operate only on the current account’s setup data.

`create_game` validates three other players, format and ownership; creates slots and invitation in one transaction; and uses a client UUID for idempotent retries. The app retains the request ID if the save fails, and reuses returned pool identities when preparing the next game.

`get_invite_link`, `revoke_invite`, `review_claim`, and `record_score` require the host. `request_spot` requires a valid invitation and verified account; it does not itself join the player. Host approval is serialized with the game/slot and cannot assign an occupied spot. A unique constraint prevents one account filling two slots in one game.

`record_score` validates a completed score for the chosen target and margin and compares the expected revision. It clears confirmations. `confirm_score` requires a current joined, non-host account and the current revision.

`get_game`, `list_games`, and `get_summary` restrict data to games in which the current account has a claimed spot. History returns at most 30 games per page, accepts an inclusive lower date and exclusive upper date, and searches participants. The iOS date UI converts the selected final day into the next local midnight.

Summary calculates completed-game wins and losses from the caller’s team. The overall total stays all-time. A peer key selects teammate and opponent breakdowns. The second migration adds `get_opponent_stats`; the third adds `get_teammate_stats`. Both take an optional inclusive start/exclusive end and count completed games in the relevant team relationship only. The iPhone view uses one date selector and requests selected and previous windows for each relationship. Month/year-to-date compares the same elapsed dates in the preceding period; a full month/year compares the preceding full period; custom dates compare the immediately preceding equal number of calendar days. It displays each relationship’s current and previous records, and shows that relationship’s win-rate difference in percentage points only when both periods contain games. Pool identity takes precedence over linked account identity to preserve a host’s guest history. This means the same real person can have multiple peer entries when different hosts use different pools; account-wide canonical merging is not implemented.

`get_invitation` is the sole anonymous RPC. The token exposes one game’s place/time/names/result, never emails. Nonmembers do not receive account IDs, pool IDs, or peer keys. The host alone receives the pending-claim review list. Random tokens contain two UUIDs of entropy, remain active until revoked, and can be rotated. Possession of a token is intentionally sufficient to view its invitation, not to approve a spot or edit a score.

## Permissions

The `private` schema is not exposed by the Data API. Its tables have RLS enabled and no direct anonymous/authenticated read or write grants. Public `SECURITY DEFINER` functions use an empty search path, fully qualified references, an authenticated-user existence check, and explicit role/ownership checks. Their default public execution grants are removed; approved RPCs are granted to `authenticated`, and only invitation reading is also granted to `anon`.

These functions are the authorization boundary; future RPCs must follow the same pattern. Do not “fix” access errors by exposing `private` or granting broad table policies. Test the migration on the real Supabase project because the local harness simulates the auth schema and cannot validate the hosted platform’s exact grants and services.

## Links and hosting

Invitation URL: `https://<invite-host>/join/#<token>`. The fragment keeps tokens out of ordinary HTTP request paths and referrers; it is still sensitive to anyone viewing or receiving the URL. Tokens are not added to analytics (none is installed). The app parses only its configured HTTPS host and the explicit custom join scheme.

Cloudflare serves the SPA and security headers. A generated Apple association file connects `/join/*` to the chosen app. HTTPS, DNS, signing, and physical-device universal-link checks are deployment tasks. There is no deferred deep-link SDK; reopen the original link after installing the app.

## Deletion and portability

`delete_my_account` requires the literal confirmation `DELETE`, removes the caller’s auth user/profile and owned records, and anonymizes claimed slots in other hosts’ games. Hosted-game deletion cascades to participants’ histories. Other unlinked nicknames may remain. Providers’ logs/backups and copies shared by message are separate from live database deletion. Restore procedures must respect deletion requests instead of accidentally restoring deleted personal records.

The schema, SQL functions, and game records are yours to administer and export. Supabase Auth and PostgREST remain service dependencies; moving providers requires replacing those integrations, not obtaining access to an outside rating supplier’s data. Use administrative database exports/backups, protect them as personal data, and test restoration. No in-app personal-data export UI is implemented yet.
