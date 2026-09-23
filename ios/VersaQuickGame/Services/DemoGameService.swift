import Foundation

/// Fictional, device-local data. This service never connects to Supabase or creates live invitations.
@MainActor final class DemoGameService: GameService {
    let isDemo = true
    static let host = "demo-cindy"
    private let storageKey = "versa.quickgame.demo.v2"
    private var state: DemoState
    private struct DemoState: Codable { var data: Bootstrap; var games: [Game] }
    init() {
        if let saved = UserDefaults.standard.data(forKey: storageKey), let decoded = try? JSONDecoder().decode(DemoState.self, from: saved) { state = decoded }
        else { state = Self.makeSample() }
    }
    private func persist() { if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: storageKey) } }
    private func index(_ id: String) throws -> Int {
        guard let i = state.games.firstIndex(where: { $0.id == id }) else { throw AppFailure(message: "Game not found.") }
        return i
    }
    func restoreUser() async throws -> String? { Self.host }
    func sendCode(email: String, name: String) async throws { throw AppFailure(message: "Demo mode does not send email.") }
    func verifyCode(email: String, code: String) async throws -> String { Self.host }
    func signOut() async throws {}
    func bootstrap(name: String?) async throws -> Bootstrap { state.data }
    func saveProfile(name: String, clubID: String?) async throws -> Bootstrap {
        state.data.profile.display_name = name; state.data.profile.default_club_id = clubID; persist(); return state.data
    }
    func addClub(name: String) async throws -> Bootstrap {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw AppFailure(message: "Enter a club name.") }
        if !state.data.clubs.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) { state.data.clubs.append(Club(id: UUID().uuidString, name: clean)) }
        persist(); return state.data
    }
    func addPlayer(nickname: String) async throws -> PoolPlayer {
        let player = PoolPlayer(id: UUID().uuidString, nickname: nickname)
        state.data.players.append(player); persist(); return player
    }
    func saveGroup(id: String?, name: String, members: [String]) async throws -> Bootstrap {
        let group = PlayerGroup(id: id ?? UUID().uuidString, name: name, member_ids: Array(Set(members)))
        if let i = state.data.groups.firstIndex(where: { $0.id == group.id }) { state.data.groups[i] = group } else { state.data.groups.append(group) }
        persist(); return state.data
    }
    func sharedGroups() async throws -> [SharedGroup] { [] }
    func createSharedGroup(name: String, rule: String) async throws -> [SharedGroup] { throw AppFailure(message: "Sign in to create a shared group.") }
    func setGroupRule(id: String, rule: String) async throws -> [SharedGroup] { throw AppFailure(message: "Sign in to edit a shared group.") }
    func groupInvite(id: String) async throws -> String { throw AppFailure(message: "Sign in to invite group members.") }
    func joinGroup(token: String) async throws -> [SharedGroup] { throw AppFailure(message: "Sign in to join a shared group.") }
    func groupBoard(id: String, view: String) async throws -> GroupBoard { GroupBoard(games: [], leaders: []) }
    func createGame(_ draft: GameDraft) async throws -> Game {
        if let existing = state.games.first(where: { $0.id == draft.requestID }) { return existing }
        guard draft.valid else { throw AppFailure(message: "Add the place and your opponent(s).") }
        var participants = [Participant(id: UUID().uuidString, slot: 0, nickname: state.data.profile.display_name, display_name: state.data.profile.display_name, account_id: Self.host, is_me: true, claimed: true, peer_key: "user:" + Self.host)]
        for (i,entry) in (draft.gameType == "singles" ? [draft.players[1]] : draft.players).enumerated() {
            let player: PoolPlayer
            if let id = entry.player_id, let saved = state.data.players.first(where: { $0.id == id }) { player = saved }
            else { player = try await addPlayer(nickname: entry.nickname) }
            participants.append(Participant(id: UUID().uuidString, slot: draft.gameType == "singles" ? 2 : i+1, pool_player_id: player.id, nickname: player.nickname, display_name: "Guest - " + player.nickname, is_me: false, claimed: false, peer_key: "pool:" + player.id))
        }
        let game = Game(id: draft.requestID, host_id: Self.host, host_name: state.data.profile.display_name, place: draft.place, court: draft.court, starts_at: Dates.encode(draft.startsAt), target: draft.target, scoring: draft.scoring, win_by: draft.winBy, revision: 0, participants: participants, claims: [], confirmed_by_me: false, confirmation_count: 0)
        var typedGame = game
        typedGame.game_type = draft.gameType
        state.games.insert(typedGame, at: 0); persist(); return typedGame
    }
    func game(id: String) async throws -> Game { state.games[try index(id)] }
    func inviteLink(gameID: String, rotate: Bool) async throws -> InviteLink { InviteLink(token: String(repeating: "d", count: 64), expires_at: nil, revoked: false) }
    func revokeInvite(gameID: String) async throws {}
    func invitation(token: String) async throws -> Game { state.games[0] }
    func requestSpot(token: String, participantID: String) async throws -> Game { throw AppFailure(message: "Use the website demo to explore the guest’s joining flow.") }
    func reviewClaim(id: String, approve: Bool) async throws -> Game {
        guard let i = state.games.firstIndex(where: { $0.claims.contains { $0.id == id } }), let claim = state.games[i].claims.first(where: { $0.id == id }) else { throw AppFailure(message: "Request not found.") }
        if approve, let p = state.games[i].participants.firstIndex(where: { $0.id == claim.participant_id }) {
            state.games[i].participants[p].claimed = true
            state.games[i].participants[p].display_name = claim.requester_name ?? "Player"
            state.games[i].participants[p].account_id = "demo-" + (claim.requester_name ?? "player").lowercased()
        }
        state.games[i].claims.removeAll { $0.id == id }; persist(); return state.games[i]
    }
    func recordScore(gameID: String, a: Int, b: Int, revision: Int) async throws -> Game {
        let i = try index(gameID), game = state.games[i]
        guard game.revision == revision else { throw AppFailure(message: "Refresh the game before saving.") }
        guard GameRules.validScore(a: a, b: b, target: game.target, winBy: game.win_by) else { throw AppFailure(message: "Enter a completed score matching this format.") }
        state.games[i].score_a = a; state.games[i].score_b = b; state.games[i].revision += 1
        state.games[i].confirmation_count = 0; state.games[i].confirmed_by_me = false
        persist(); return state.games[i]
    }
    func confirmScore(gameID: String, revision: Int) async throws -> Game {
        let i = try index(gameID); state.games[i].confirmed_by_me = true; state.games[i].confirmation_count += 1; persist(); return state.games[i]
    }
    func games(_ filter: HistoryFilter) async throws -> [Game] {
        let found = state.games.filter { game in
            (filter.from == nil || game.startDate >= filter.from!) && (filter.until == nil || game.startDate < filter.until!) &&
            (filter.search.isEmpty || game.participants.contains { $0.nickname.localizedCaseInsensitiveContains(filter.search) || $0.display_name.localizedCaseInsensitiveContains(filter.search) })
        }.sorted { $0.startDate > $1.startDate }
        return Array(found.dropFirst(filter.offset).prefix(30))
    }
    func summary(peer: String?) async throws -> Summary {
        var people: [String: Peer] = [:], together: [Game] = [], against: [Game] = []
        for game in state.games where game.completed {
            for person in game.participants where !person.is_me {
                let key = person.peer_key ?? "slot:" + person.id
                var item = people[key] ?? Peer(key: key, name: person.display_name, games: 0)
                item.games += 1; people[key] = item
                if key == peer { if person.team == 0 { together.append(game) } else { against.append(game) } }
            }
        }
        return Summary(overall: .from(state.games, userID: Self.host), with_player: .from(together, userID: Self.host), against_player: .from(against, userID: Self.host), people: people.values.sorted { $0.name < $1.name })
    }
    func teammateStats(peer: String, from: Date?, until: Date?) async throws -> Stats {
        let matches = state.games.filter { game in
            game.completed && (from == nil || game.startDate >= from!) && (until == nil || game.startDate < until!) &&
            game.participants.contains { $0.team == 0 && !$0.is_me && ($0.peer_key ?? "slot:" + $0.id) == peer }
        }
        return Stats.from(matches, userID: Self.host)
    }
    func opponentStats(peer: String, from: Date?, until: Date?) async throws -> Stats {
        let matches = state.games.filter { game in
            game.completed && (from == nil || game.startDate >= from!) && (until == nil || game.startDate < until!) &&
            game.participants.contains { $0.team == 1 && ($0.peer_key ?? "slot:" + $0.id) == peer }
        }
        return Stats.from(matches, userID: Self.host)
    }
    func deleteAccount() async throws { UserDefaults.standard.removeObject(forKey: storageKey); state = Self.makeSample() }
    private static func makeSample() -> DemoState {
        let players = [PoolPlayer(id: "anna", nickname: "Anna"), PoolPlayer(id: "mike", nickname: "Mike"), PoolPlayer(id: "jo", nickname: "Jo"), PoolPlayer(id: "ben", nickname: "Ben"), PoolPlayer(id: "leah", nickname: "Leah")]
        let bootstrap = Bootstrap(profile: Profile(id: host, display_name: "Cindy", default_club_id: "hub"), clubs: [Club(id: "hub", name: "HUB Silicon Valley"), Club(id: "campbell", name: "HUB Campbell")], players: players, groups: [PlayerGroup(id: "tue", name: "Tuesday Group", member_ids: ["anna","mike","jo"]), PlayerGroup(id: "mon", name: "Monday Group", member_ids: ["ben","leah","mike"]), PlayerGroup(id: "pinoy", name: "Pinoy Group", member_ids: ["anna","jo","leah"])])
        var games: [Game] = []
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: Date())!.start
        let priorMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart)!
        let priorYearStart = calendar.date(byAdding: .year, value: -1, to: monthStart)!
        for i in 0..<10 {
            let partner = i % 3 == 0 ? players[1] : players[0]
            let opponents = i % 3 == 0 ? [players[0],players[2]] : [players[1],players[2]]
            var roster = [Participant(id: "g\(i)-0", slot: 0, nickname: "Cindy", display_name: "Cindy", account_id: host, is_me: true, claimed: true, peer_key: "user:" + host)]
            for (slot,p) in ([partner]+opponents).enumerated() { roster.append(Participant(id: "g\(i)-\(slot+1)", slot: slot+1, pool_player_id: p.id, nickname: p.nickname, display_name: "Guest - " + p.nickname, is_me: false, claimed: false, peer_key: "pool:" + p.id)) }
            let completed = i > 0, win = i % 3 != 0
            let date = i < 4 ? Date().addingTimeInterval(Double(-i)*86400) :
                calendar.date(byAdding: .day, value: i < 7 ? i - 4 : i - 7,
                              to: i < 7 ? priorMonthStart : priorYearStart)!
            games.append(Game(id: "demo-game-\(i)", host_id: host, host_name: "Cindy", place: i % 2 == 0 ? "HUB Silicon Valley" : "HUB Campbell", court: "\(i % 4 + 1)", starts_at: Dates.encode(date), target: 11, scoring: "sideout", win_by: 2, score_a: completed ? (win ? 11 : 7) : nil, score_b: completed ? (win ? 8 : 11) : nil, revision: completed ? 1 : 0, participants: roster, claims: i == 0 ? [Claim(id: "demo-claim", participant_id: roster[1].id, requester_name: roster[1].nickname, status: "pending")] : [], confirmed_by_me: false, confirmation_count: 0))
        }
        return DemoState(data: bootstrap, games: games)
    }
}
