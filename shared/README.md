# Shared contracts

The iOS and mobile invitation website live as sibling projects. Their common contract is the versioned SQL RPC API in `../backend/migrations/`. Swift models live in `../ios/VersaQuickGame/Core/Models.swift`, and the limited invitation-page models live in `../web/src/types.ts`.

Keep schema, payloads, and invitation URL rules in sync when changing either client. Add generated cross-language models here once there is a stable schema generator; do not duplicate UI code between SwiftUI and the website.
