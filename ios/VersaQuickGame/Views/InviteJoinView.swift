import SwiftUI

struct InviteJoinView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    let token: String
    @State private var game: Game?
    @State private var selectedID: String?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BrandHeader()
                if let game {
                    Text(game.participants.contains(where: \.is_me) ? "Your game." : "\(game.host_name) invited you.").font(.largeTitle.bold())
                    QGCard { Text(game.place).font(.headline); Text("\(game.courtLabel) · \(game.startDate.formatted(date: .abbreviated, time: .shortened))").font(.subheadline); Text(game.format).font(.caption).foregroundStyle(.secondary) }
                    TeamsView(game: game)
                    if store.userID == nil { LoginForm(onSuccess: { Task { await reload() } }) }
                    else if game.participants.contains(where: \.is_me) {
                        if let a = game.score_a, let b = game.score_b {
                            QGCard { Text(game.won(userID: store.userID) == true ? "You won" : "You lost").font(.headline); Text("Team A \(a) – \(b) Team B").font(.title2.bold()); Text("Recorded by \(game.host_name)").font(.caption).foregroundStyle(.secondary) }
                            if game.confirmed_by_me { Label("Score confirmed", systemImage: "checkmark.circle.fill") }
                            else if game.host_id != store.userID { Button("Confirm this score") { Task { await run { self.game = try await store.service.confirmScore(gameID: game.id, revision: game.revision) } } }.buttonStyle(PrimaryButton()).disabled(busy) }
                        } else { Label("Your spot is confirmed. Waiting for the final score.", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                    }
                    else if game.my_claim?.status == "pending" { QGCard { Text("Waiting for \(game.host_name)’s approval.").font(.headline); Text("Go ahead and play. Your spot stays a guest until the host confirms.").font(.subheadline).foregroundStyle(.secondary) } }
                    else {
                        if game.my_claim?.status == "declined" { Text("The host declined your previous request. Check your spot with them before trying again.").font(.callout) }
                        Text("Which player are you?").font(.title3.bold())
                        ForEach(game.participants.filter { !$0.claimed && $0.slot != 0 }) { player in
                            Button { selectedID = player.id } label: { QGCard { HStack { Text(player.display_name); Spacer(); Image(systemName: selectedID == player.id ? "checkmark.circle.fill" : "circle") } } }.buttonStyle(.plain)
                        }
                        Button("Request this spot") { if let selectedID { Task { await run { self.game = try await store.service.requestSpot(token: token, participantID: selectedID) } } } }.buttonStyle(PrimaryButton()).disabled(selectedID == nil || busy)
                    }
                } else if error == nil { ProgressView("Opening invitation…").frame(maxWidth: .infinity) }
                if let error { ErrorNotice(text: error); Button("Try again") { Task { await reload() } } }
            }.padding(20)
        }.background(QGTheme.background).navigationTitle("Invitation").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await reload(); while !Task.isCancelled { do { try await Task.sleep(for: .seconds(12)) } catch { return }; if phase == .active { await reload(silent: true) } } }
        .refreshable { await reload() }
    }
    private func reload(silent: Bool = false) async { do { game = try await store.service.invitation(token: token); if !silent { error = nil } } catch { if !silent { self.error = error.localizedDescription } } }
    @MainActor private func run(_ work: () async throws -> Void) async { busy = true; error = nil; defer { busy = false }; do { try await work() } catch { self.error = error.localizedDescription } }
}
