import SwiftUI

enum QGTheme {
    static let forest = Color(red: 0.09, green: 0.31, blue: 0.23)
    static let lime = Color(red: 0.84, green: 0.94, blue: 0.50)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}
struct QGCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { VStack(alignment: .leading, spacing: 12) { content }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(QGTheme.surface, in: RoundedRectangle(cornerRadius: 18)) }
}
struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
            .foregroundStyle(.white).background(QGTheme.forest.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4), in: RoundedRectangle(cornerRadius: 14))
    }
}
struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 10) { Image("BrandMark").resizable().scaledToFit().frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 10)); Text("Versa Quick Game").font(.headline) }
    }
}
struct ErrorNotice: View {
    let text: String
    var body: some View { Label(text, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.updatesFrequently) }
}
struct SettingsButton: View {
    @EnvironmentObject var store: AppStore
    var body: some View { Button { store.settingsPresented = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings") }
}
struct TeamsView: View {
    let game: Game
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(0..<2) { team in
                QGCard {
                    Text(team == 0 ? "TEAM A" : "TEAM B").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(game.participants.filter { $0.team == team }) { p in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.display_name).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                            Text(p.slot == 0 ? "Host" : p.is_me ? "You" : p.claimed ? "Joined" : "Unclaimed").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if p.slot % 2 == 0 { Divider() }
                    }
                }
            }
        }
    }
}
struct GameRow: View {
    let game: Game
    let userID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(game.place).font(.headline); Spacer(); if let a = game.score_a, let b = game.score_b { Text("\(a)–\(b)").font(.headline.monospacedDigit()) } else { Text("In progress").font(.caption).foregroundStyle(.secondary) } }
            Text("\(game.courtLabel) · \(game.startDate.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            Text(game.participants.map(\.display_name).joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            if let won = game.won(userID: userID) { Text(won ? "Won" : "Lost").font(.caption.weight(.semibold)).foregroundStyle(won ? Color.green : Color.secondary) }
        }.padding(.vertical, 5)
    }
}
