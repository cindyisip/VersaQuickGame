import Foundation
import Supabase

enum AppConfig {
    static let supportURL = URL(string: "https://versagaldigital.com/apps/versaquickgame/support/")!
    static let privacyURL = URL(string: "https://versagaldigital.com/apps/versaquickgame/privacy/")!
    static let termsURL = URL(string: "https://versagaldigital.com/apps/versaquickgame/terms/")!
    static let informationURL = URL(string: "https://versagaldigital.com/apps/versaquickgame/")!
    static var inviteBase: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "InviteBaseURL") as? String,
              let url = URL(string: raw), url.scheme == "https", let host = url.host, !host.contains("YOUR_") else { return nil }
        return url
    }
    static func client() -> SupabaseClient? {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let key = Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String,
              let url = URL(string: rawURL), url.scheme == "https", url.host != nil,
              !rawURL.contains("YOUR_"), !key.contains("YOUR_"), key.hasPrefix("sb_publishable_") else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }
    static func invitationURL(token: String) -> URL? {
        guard let base = inviteBase else { return nil }
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)
        parts?.path = "/join/"; parts?.query = nil; parts?.fragment = token
        return parts?.url
    }
}

@MainActor final class SupabaseGameService: GameService {
    let isDemo = false
    private let client: SupabaseClient?
    init() { client = AppConfig.client() }
    var configured: Bool { client != nil && AppConfig.inviteBase != nil }
    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw AppFailure(message: "Add your Supabase settings in Config/Local.xcconfig, then rebuild. You can explore the demo meanwhile.") }
        return client
    }
    private func call<T: Decodable>(_ name: String, _ args: [String: AnyJSON] = [:]) async throws -> T {
        let response = try await requireClient().rpc(name, params: args).execute()
        return try JSONDecoder().decode(T.self, from: response.data)
    }
    private func action(_ name: String, _ args: [String: AnyJSON]) async throws {
        _ = try await requireClient().rpc(name, params: args).execute()
    }
    func restoreUser() async throws -> String? {
        guard let client else { return nil }
        guard client.auth.currentSession != nil else { return nil }
        return try await client.auth.session.user.id.uuidString.lowercased()
    }
    func sendCode(email: String, name: String) async throws {
        try await requireClient().auth.signInWithOTP(email: email, data: ["display_name": .string(name)])
    }
    func verifyCode(email: String, code: String) async throws -> String {
        let client = try requireClient()
        try await client.auth.verifyOTP(email: email, token: code, type: .email)
        return try await client.auth.session.user.id.uuidString.lowercased()
    }
    func signOut() async throws { try await requireClient().auth.signOut(scope: .local) }
    func bootstrap(name: String? = nil) async throws -> Bootstrap {
        try await call("bootstrap", ["p_display_name": name.map(AnyJSON.string) ?? .null])
    }
    func saveProfile(name: String, clubID: String?) async throws -> Bootstrap {
        try await call("save_profile", ["p_display_name": .string(name), "p_default_club_id": clubID.map(AnyJSON.string) ?? .null])
    }
    func addClub(name: String) async throws -> Bootstrap { try await call("add_club", ["p_name": .string(name)]) }
    func addPlayer(nickname: String) async throws -> PoolPlayer { try await call("add_player", ["p_nickname": .string(nickname)]) }
    func saveGroup(id: String?, name: String, members: [String]) async throws -> Bootstrap {
        try await call("save_group", ["p_group_id": id.map(AnyJSON.string) ?? .null, "p_name": .string(name), "p_player_ids": .array(members.map(AnyJSON.string))])
    }
    func sharedGroups() async throws -> [SharedGroup] { try await call("list_shared_groups") }
    func createSharedGroup(name: String, rule: String) async throws -> [SharedGroup] { try await call("create_shared_group", ["p_name": .string(name), "p_eligibility": .string(rule)]) }
    func setGroupRule(id: String, rule: String) async throws -> [SharedGroup] { try await call("set_shared_group_rule", ["p_group_id": .string(id), "p_eligibility": .string(rule)]) }
    func groupInvite(id: String) async throws -> String { try await call("get_shared_group_invite", ["p_group_id": .string(id)]) }
    func joinGroup(token: String) async throws -> [SharedGroup] { try await call("join_shared_group", ["p_token": .string(token)]) }
    func groupBoard(id: String, view: String) async throws -> GroupBoard { try await call("get_shared_group_board", ["p_group_id": .string(id), "p_view": .string(view)]) }
    func createGame(_ draft: GameDraft) async throws -> Game {
        try await call("create_game", ["p_place": .string(draft.place), "p_court": .string(draft.court), "p_starts_at": .string(Dates.encode(draft.startsAt)),
            "p_target": .integer(draft.target), "p_scoring": .string(draft.scoring), "p_win_by": .integer(draft.winBy), "p_request_id": .string(draft.requestID),
            "p_players": .array((draft.gameType == "singles" ? [draft.players[1]] : draft.players).map { .object(["nickname": .string($0.nickname), "player_id": $0.player_id.map(AnyJSON.string) ?? .null]) })])
    }
    func game(id: String) async throws -> Game { try await call("get_game", ["p_game_id": .string(id)]) }
    func inviteLink(gameID: String, rotate: Bool = false) async throws -> InviteLink { try await call("get_invite_link", ["p_game_id": .string(gameID), "p_rotate": .bool(rotate)]) }
    func revokeInvite(gameID: String) async throws { try await action("revoke_invite", ["p_game_id": .string(gameID)]) }
    func invitation(token: String) async throws -> Game { try await call("get_invitation", ["p_token": .string(token)]) }
    func requestSpot(token: String, participantID: String) async throws -> Game { try await call("request_spot", ["p_token": .string(token), "p_participant_id": .string(participantID)]) }
    func reviewClaim(id: String, approve: Bool) async throws -> Game { try await call("review_claim", ["p_claim_id": .string(id), "p_approve": .bool(approve)]) }
    func recordScore(gameID: String, a: Int, b: Int, revision: Int) async throws -> Game {
        try await call("record_score", ["p_game_id": .string(gameID), "p_score_a": .integer(a), "p_score_b": .integer(b), "p_expected_revision": .integer(revision)])
    }
    func confirmScore(gameID: String, revision: Int) async throws -> Game { try await call("confirm_score", ["p_game_id": .string(gameID), "p_revision": .integer(revision)]) }
    func games(_ filter: HistoryFilter) async throws -> [Game] {
        try await call("list_games", ["p_from": filter.from.map { .string(Dates.encode($0)) } ?? .null,
          "p_until": filter.until.map { .string(Dates.encode($0)) } ?? .null, "p_search": .string(filter.search), "p_offset": .integer(filter.offset)])
    }
    func summary(peer: String? = nil) async throws -> Summary { try await call("get_summary", ["p_peer_key": peer.map(AnyJSON.string) ?? .null]) }
    func teammateStats(peer: String, from: Date?, until: Date?) async throws -> Stats {
        try await call("get_teammate_stats", ["p_peer_key": .string(peer),
            "p_from": from.map { .string(Dates.encode($0)) } ?? .null,
            "p_until": until.map { .string(Dates.encode($0)) } ?? .null])
    }
    func opponentStats(peer: String, from: Date?, until: Date?) async throws -> Stats {
        try await call("get_opponent_stats", ["p_peer_key": .string(peer),
            "p_from": from.map { .string(Dates.encode($0)) } ?? .null,
            "p_until": until.map { .string(Dates.encode($0)) } ?? .null])
    }
    func deleteAccount() async throws {
        try await action("delete_my_account", ["p_confirmation": .string("DELETE")])
        try? await client?.auth.signOut(scope: .local)
    }
}
