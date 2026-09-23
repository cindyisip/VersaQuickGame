import Foundation

@MainActor protocol GameService {
    var isDemo: Bool { get }
    func restoreUser() async throws -> String?
    func sendCode(email: String, name: String) async throws
    func verifyCode(email: String, code: String) async throws -> String
    func signOut() async throws
    func bootstrap(name: String?) async throws -> Bootstrap
    func saveProfile(name: String, clubID: String?) async throws -> Bootstrap
    func addClub(name: String) async throws -> Bootstrap
    func addPlayer(nickname: String) async throws -> PoolPlayer
    func saveGroup(id: String?, name: String, members: [String]) async throws -> Bootstrap
    func sharedGroups() async throws -> [SharedGroup]
    func createSharedGroup(name: String, rule: String) async throws -> [SharedGroup]
    func setGroupRule(id: String, rule: String) async throws -> [SharedGroup]
    func groupInvite(id: String) async throws -> String
    func joinGroup(token: String) async throws -> [SharedGroup]
    func groupBoard(id: String, view: String) async throws -> GroupBoard
    func createGame(_ draft: GameDraft) async throws -> Game
    func game(id: String) async throws -> Game
    func inviteLink(gameID: String, rotate: Bool) async throws -> InviteLink
    func revokeInvite(gameID: String) async throws
    func invitation(token: String) async throws -> Game
    func requestSpot(token: String, participantID: String) async throws -> Game
    func reviewClaim(id: String, approve: Bool) async throws -> Game
    func recordScore(gameID: String, a: Int, b: Int, revision: Int) async throws -> Game
    func confirmScore(gameID: String, revision: Int) async throws -> Game
    func games(_ filter: HistoryFilter) async throws -> [Game]
    func summary(peer: String?) async throws -> Summary
    func teammateStats(peer: String, from: Date?, until: Date?) async throws -> Stats
    func opponentStats(peer: String, from: Date?, until: Date?) async throws -> Stats
    func deleteAccount() async throws
}
