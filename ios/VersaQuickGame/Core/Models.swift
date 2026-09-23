import Foundation

struct Profile: Codable, Identifiable, Hashable {
    var id: String
    var display_name: String
    var default_club_id: String?
}
struct Club: Codable, Identifiable, Hashable { var id: String; var name: String }
struct PoolPlayer: Codable, Identifiable, Hashable { var id: String; var nickname: String }
struct PlayerGroup: Codable, Identifiable, Hashable { var id: String; var name: String; var member_ids: [String] }
struct SharedMember: Codable, Identifiable, Hashable { var id: String; var name: String }
struct SharedGroup: Codable, Identifiable, Hashable {
    var id: String; var name: String; var eligibility: String; var owner_id: String; var members: [SharedMember]
}
struct GroupGame: Codable, Identifiable { var id: String; var starts_at: String; var score_a: Int; var score_b: Int }
struct GroupLeader: Codable, Identifiable {
    var account_id: String; var name: String; var partner_id: String?; var partner_name: String
    var games: Int; var wins: Int; var losses: Int; var win_percent: Double
    var id: String { account_id + ":" + (partner_id ?? "all") }
}
struct GroupBoard: Codable { var games: [GroupGame]; var leaders: [GroupLeader] }
struct Bootstrap: Codable {
    var profile: Profile
    var clubs: [Club]
    var players: [PoolPlayer]
    var groups: [PlayerGroup]
}
struct Participant: Codable, Identifiable, Hashable {
    var id: String
    var slot: Int
    var pool_player_id: String?
    var nickname: String
    var display_name: String
    var account_id: String?
    var is_me: Bool
    var claimed: Bool
    var peer_key: String?
    var team: Int { slot < 2 ? 0 : 1 }
}
struct Claim: Codable, Identifiable, Hashable {
    var id: String
    var participant_id: String
    var requester_name: String?
    var status: String
}
struct Game: Codable, Identifiable, Hashable {
    var id: String
    var game_type: String? = nil
    var host_id: String?
    var host_name: String
    var place: String
    var court: String
    var starts_at: String
    var target: Int
    var scoring: String
    var win_by: Int
    var score_a: Int?
    var score_b: Int?
    var revision: Int
    var participants: [Participant]
    var claims: [Claim]
    var my_claim: Claim?
    var confirmed_by_me: Bool
    var confirmation_count: Int
    var completed: Bool { score_a != nil && score_b != nil }
    var startDate: Date { Dates.parse(starts_at) ?? .distantPast }
    var format: String { "\(game_type == "singles" ? "Singles" : "Doubles") · \(target) points · \(scoring == "sideout" ? "Side-out" : "Rally") · Win by \(win_by)" }
    var courtLabel: String { court.isEmpty ? "Court TBD" : "Court \(court)" }
    func myTeam(userID: String?) -> Int? { participants.first { $0.account_id != nil && $0.account_id == userID }?.team }
    func won(userID: String?) -> Bool? {
        guard let team = myTeam(userID: userID), let a = score_a, let b = score_b else { return nil }
        return team == 0 ? a > b : b > a
    }
}
struct InviteLink: Codable {
    var token: String
    var expires_at: String?
    var revoked: Bool
}
struct Stats: Codable, Hashable {
    var games: Int
    var wins: Int
    var losses: Int
    var win_percent: Double
    var loss_percent: Double
    static let empty = Stats(games: 0, wins: 0, losses: 0, win_percent: 0, loss_percent: 0)
    static func from(_ games: [Game], userID: String) -> Stats {
        let completed = games.filter { $0.completed && $0.myTeam(userID: userID) != nil }
        let wins = completed.filter { $0.won(userID: userID) == true }.count
        let total = completed.count
        return Stats(games: total, wins: wins, losses: total - wins,
                     win_percent: total == 0 ? 0 : Double(wins) * 100 / Double(total),
                     loss_percent: total == 0 ? 0 : Double(total - wins) * 100 / Double(total))
    }
}
struct Peer: Codable, Identifiable, Hashable { var key: String; var name: String; var games: Int; var id: String { key } }
struct Summary: Codable {
    var overall: Stats
    var with_player: Stats
    var against_player: Stats
    var people: [Peer]
    static let empty = Summary(overall: .empty, with_player: .empty, against_player: .empty, people: [])
}
struct PlayerEntry: Codable { var nickname = ""; var player_id: String? }
struct GameDraft: Codable {
    var requestID = UUID().uuidString
    var place = ""
    var court = ""
    var startsAt = Date()
    var target = 11
    var scoring = "sideout"
    var winBy = 2
    var gameType = "doubles"
    var players = [PlayerEntry(), PlayerEntry(), PlayerEntry()]
    var valid: Bool { !place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (gameType == "singles" ? !players[1].nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : players.allSatisfy { !$0.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) }
}
struct HistoryFilter {
    var from: Date?
    var until: Date?
    var search = ""
    var offset = 0
}
enum Dates {
    static func encode(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
enum GameRules {
    static func validScore(a: Int, b: Int, target: Int, winBy: Int) -> Bool {
        let high = max(a, b), low = min(a, b)
        return low >= 0 && high <= 99 && high >= target && high - low >= winBy &&
            (high == target || high - low == winBy) && (winBy != 1 || high == target)
    }
    static func invitationToken(from url: URL, expectedHost: String?) -> String? {
        let token: String?
        if url.scheme == "versaquickgame", url.host == "join" {
            token = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "token" }?.value
        } else if url.scheme == "https", let expectedHost, url.host == expectedHost, url.path == "/join/" || url.path == "/join" {
            token = url.fragment
        } else { return nil }
        guard let token, token.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
        return token
    }
}
struct AppFailure: LocalizedError { let message: String; var errorDescription: String? { message } }

enum PlayerPeriod: String, CaseIterable {
    case allTime, thisMonth, lastMonth, thisYear, lastYear, custom
    var title: String {
        switch self {
        case .allTime: "All time"
        case .thisMonth: "This month to date"
        case .lastMonth: "Last full month"
        case .thisYear: "This year to date"
        case .lastYear: "Last full year"
        case .custom: "Custom date range"
        }
    }
    func windows(customFrom: Date, through: Date, now: Date = Date(), calendar: Calendar = .current) -> PlayerWindows? {
        if self == .allTime { return nil }
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let start: Date, end: Date, previousStart: Date, previousEnd: Date
        switch self {
        case .thisMonth, .lastMonth, .thisYear, .lastYear:
            let component: Calendar.Component = self == .thisMonth || self == .lastMonth ? .month : .year
            guard let active = calendar.dateInterval(of: component, for: now),
                  let lastStart = calendar.date(byAdding: component, value: -1, to: active.start) else { return nil }
            let isCurrent = self == .thisMonth || self == .thisYear
            start = isCurrent ? active.start : lastStart
            end = isCurrent ? todayEnd : active.start
            guard let prior = calendar.date(byAdding: component, value: -1, to: start) else { return nil }
            previousStart = prior
            if isCurrent && component == .month {
                let elapsedDays = calendar.dateComponents([.day], from: active.start, to: end).day ?? 0
                previousEnd = min(start, calendar.date(byAdding: .day, value: elapsedDays, to: prior) ?? start)
            } else {
                previousEnd = isCurrent ? min(start, calendar.date(byAdding: component, value: -1, to: end) ?? start) : start
            }
        case .custom:
            start = calendar.startOfDay(for: customFrom)
            guard calendar.startOfDay(for: through) >= start,
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: through)) else { return nil }
            end = nextDay
            let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            guard let prior = calendar.date(byAdding: .day, value: -days, to: start) else { return nil }
            previousStart = prior; previousEnd = start
        case .allTime: return nil
        }
        guard start < end, previousStart < previousEnd else { return nil }
        return PlayerWindows(current: DateInterval(start: start, end: end), previous: DateInterval(start: previousStart, end: previousEnd))
    }
}
struct PlayerWindows {
    let current: DateInterval
    let previous: DateInterval
}
