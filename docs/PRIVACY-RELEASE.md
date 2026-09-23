# Release privacy and operational details

The prepared public pages are prerelease policies that match the source design, not a completed live-service compliance review. Resolve the following against the deployed build before opening signup broadly.

## Data inventory

| Data | Purpose and visibility |
|---|---|
| Email | Account verification and service messages; not in game payloads |
| Display name/user ID | Account identity and approved game spots; display names visible to game invite holders |
| Nicknames | Host-entered guest labels, saved player pools; game labels visible to invite holders |
| Place, court, time, format | User-entered game context; visible to invite holders; no GPS permission |
| Scores, claims, confirmations | Results and personal statistics; pending claim requests visible to the host and requester as appropriate |
| Clubs/groups | Private account setup data |
| Session | Keychain on iOS through the auth SDK; browser local storage; cleared on local sign-out |
| Demo data | Fictional iOS data in UserDefaults; browser demo in memory |
| Provider logs and support email | Authentication/delivery/security operations and requested support; check chosen provider settings |

`PrivacyInfo.xcprivacy` declares no tracking, linked name/email/user ID/user content/gameplay content for app functionality, and UserDefaults required-reason use `CA92.1`. Review the archive privacy report, SDK manifests, and actual provider configuration before completing App Store Connect’s questionnaire. Picked places are user content in the source; assess whether the released use also warrants location disclosures. No contacts, GPS, camera, microphone, Bluetooth, ads, or analytics SDK is requested by this version.

## Decisions before launch

- Confirm the actual SMTP provider and publish its identity/privacy reference on the privacy page. The source is compatible with standard SMTP through Supabase; no provider has been provisioned.
- Set and document database backups, request/security-log retention, email-log retention, and support-correspondence handling. Public pages deliberately do not invent a purge deadline.
- The drafted public pages target an adult initial release. Confirm the intended age audience and align onboarding, App Store age rating, and policy wording before launch; age verification is not implemented.
- Confirm the support/privacy mailboxes work, and establish the process for deletion requests from guests whose unclaimed nicknames cannot be linked to an account.
- Decide how incorrect post-approval identity claims or erroneous games are resolved during the beta. There is no host-side reassignment, individual game deletion, or administrative web console in this first source.
- Review policy wording for the regions in which you offer the service. Update development labels, provider details, account deletion URL, and App Store link together at launch.

## Account deletion

Available from iOS Settings and the browser’s `/account/` route, even without a game token. Supabase email code verifies account control. Typing DELETE confirms the permanent action. The database removes the auth account, owned clubs/groups/player pool, hosted games, claims, and confirmations, and unlinks/anonymizes claimed spots in other games. This is implemented, not just an email link.

Deleting an app or signing out is not cloud deletion. Copies in shared messages, unrelated unclaimed nicknames, backups/logs, and support email require separate handling. Explain that deleting a host account also removes its games from others’ history. See [Apple account-deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/).

## Distribution details

The app has no paid feature, subscription, or in-app purchase in this version. Email-only login means there is no social-login provider configuration. The Info.plist export-encryption answer assumes standard operating-system/network encryption only; review it for the final archive. No App Store credentials, signing certificate, provisioning profile, SMTP secret, or backend service key is included in the source.

For account-based review, provide Apple a reliable way to access a populated review account and clear directions for the guest workflow, following current App Review requirements. Demo mode helps demonstrate features but does not replace review access to live functionality.

Primary references: [App privacy details](https://developer.apple.com/app-store/app-privacy-details/), [privacy manifest data types](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype), [Supabase SMTP](https://supabase.com/docs/guides/auth/auth-smtp), [Supabase database functions](https://supabase.com/docs/guides/database/functions).
