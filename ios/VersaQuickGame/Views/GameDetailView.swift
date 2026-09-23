import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

struct GameDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var game: Game
    @State private var link: InviteLink?
    @State private var sharing = false
    @State private var scoring = false
    @State private var busy = false
    @State private var copied = false
    @State private var error: String?
    init(initial: Game) { _game = State(initialValue: initial) }
    private var isHost: Bool { game.host_id == store.userID }
    private var shareURL: URL? { guard !store.isDemo, let link, !link.revoked else { return nil }; return AppConfig.invitationURL(token: link.token) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(game.completed ? "Good game." : "Game ready.").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 5) { Text(game.place).font(.headline); Text("\(game.courtLabel) · \(game.startDate.formatted(date: .abbreviated, time: .shortened))"); Text(game.format) }.font(.subheadline).foregroundStyle(.secondary)
                if game.completed { scoreboard }
                if isHost {
                    QGCard {
                        if let shareURL { HStack(spacing: 20) { QRCodeView(text: shareURL.absoluteString).frame(width: 118, height: 118); VStack(alignment: .leading, spacing: 7) { Text("Invite your players").font(.headline); Text("Scan or share. Join in the app or browser.").font(.caption).foregroundStyle(.secondary) } } }
                        else { Label(store.isDemo ? "Demo game · live invitations are off" : "Invitation sharing is unavailable", systemImage: "qrcode").font(.subheadline); Text(store.isDemo ? "Sign in to create a real game and share by text, AirDrop, or link." : "Check the invitation website setting, or renew this game’s link.").font(.caption).foregroundStyle(.secondary) }
                    }
                    HStack {
                        Button { sharing = true } label: { Label("Share invitation", systemImage: "square.and.arrow.up") }.buttonStyle(PrimaryButton())
                        Button { if let shareURL { UIPasteboard.general.url = shareURL; copied = true } } label: { Text(copied ? "Copied ✓" : "Copy link").font(.headline).padding(.vertical, 14).padding(.horizontal, 12) }.buttonStyle(.bordered)
                    }.disabled(shareURL == nil)
                }
                TeamsView(game: game)
                if !game.claims.isEmpty {
                    ForEach(game.claims) { claim in QGCard {
                        Text("\(claim.requester_name ?? "A player") wants to join").font(.headline)
                        Text("Claiming \(game.participants.first { $0.id == claim.participant_id }?.display_name ?? "a guest spot")").font(.caption).foregroundStyle(.secondary)
                        HStack { Button("Approve") { review(claim, true) }.buttonStyle(.borderedProminent); Button("Decline", role: .destructive) { review(claim, false) }.buttonStyle(.bordered) }.disabled(busy)
                    } }
                }
                if let error { ErrorNotice(text: error) }
                if isHost { Button(game.completed ? "Correct final score" : "Enter final score") { scoring = true }.buttonStyle(PrimaryButton()) }
                else if game.completed {
                    if game.confirmed_by_me { Label("You confirmed this score", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    else { Button("Confirm this score") { Task { await run { game = try await store.service.confirmScore(gameID: game.id, revision: game.revision) } } }.buttonStyle(PrimaryButton()).disabled(busy) }
                }
                Text(game.completed ? "Recorded by \(game.host_name) · \(game.confirmation_count) player confirmation(s)" : "Joining is optional. Everyone can play.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(20)
        }.background(QGTheme.background).navigationTitle("Quick Game").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .topBarLeading) { Menu { Button("Refresh", systemImage: "arrow.clockwise") { Task { await reload() } }; if isHost && !store.isDemo { Button("Renew invitation link", systemImage: "link") { Task { await run { link = try await store.service.inviteLink(gameID: game.id, rotate: true); copied = false } } }; Button("Stop new invitations", systemImage: "link.badge.plus", role: .destructive) { Task { await run { try await store.service.revokeInvite(gameID: game.id); link = nil } } } } } label: { Image(systemName: "ellipsis.circle") } }
        }
        .task { await reload(); while !Task.isCancelled { do { try await Task.sleep(for: .seconds(15)) } catch { return }; if phase == .active { await reload(silent: true) } } }
        .refreshable { await reload() }
        .sheet(isPresented: $sharing) { if let shareURL { ActivitySheet(items: ["Join my Versa Quick Game at \(game.place), \(game.courtLabel). Claim your spot in the app or browser.", shareURL]) } }
        .sheet(isPresented: $scoring) { NavigationStack { ScoreEntryView(game: game) { updated in game = updated } }.environmentObject(store) }
    }
    private var scoreboard: some View {
        VStack(spacing: 10) { Text(game.won(userID: store.userID) == true ? "YOU WON" : "YOU LOST").font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 5).background(QGTheme.lime, in: Capsule()).foregroundStyle(QGTheme.forest); Text("\(game.score_a ?? 0) – \(game.score_b ?? 0)").font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit(); Text(game.game_type == "singles" ? "You · Opponent" : "Team A · Team B").font(.caption) }.frame(maxWidth: .infinity).padding(22).background(QGTheme.forest, in: RoundedRectangle(cornerRadius: 22)).foregroundStyle(.white)
    }
    private func review(_ claim: Claim, _ approve: Bool) { Task { await run { game = try await store.service.reviewClaim(id: claim.id, approve: approve) } } }
    @MainActor private func run(_ action: () async throws -> Void) async { busy = true; error = nil; defer { busy = false }; do { try await action() } catch { self.error = error.localizedDescription } }
    private func reload(silent: Bool = false) async { do { game = try await store.service.game(id: game.id); if isHost { link = try await store.service.inviteLink(gameID: game.id, rotate: false) }; if !silent { error = nil } } catch { if !silent { self.error = error.localizedDescription } } }
}
struct QRCodeView: View {
    let text: String
    private var image: UIImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    var body: some View { Group { if let image { Image(uiImage: image).interpolation(.none).resizable().scaledToFit().padding(8).background(.white) } else { Image(systemName: "qrcode") } }.accessibilityLabel("Game invitation QR code") }
}
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
struct ScoreEntryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let game: Game
    var onSave: (Game) -> Void
    @State private var a = ""
    @State private var b = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section { Text(game.format); TeamsView(game: game) }
            Section("Final score") { TextField("Team A", text: $a).keyboardType(.numberPad); TextField("Team B", text: $b).keyboardType(.numberPad) }
            Section {
                if game.completed { Text("Correcting the score clears previous confirmations. Players can confirm the updated score.").font(.caption) }
                if let error { ErrorNotice(text: error) }
                Button(busy ? "Saving…" : "Save result") {
                    Task {
                        guard let scoreA = Int(a), let scoreB = Int(b), GameRules.validScore(a: scoreA, b: scoreB, target: game.target, winBy: game.win_by) else { error = "Reach \(game.target) points and win by \(game.win_by)."; return }
                        busy = true; error = nil; defer { busy = false }
                        do { onSave(try await store.service.recordScore(gameID: game.id, a: scoreA, b: scoreB, revision: game.revision)); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy)
            }
        }.navigationTitle("Final score").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }.onAppear { a = game.score_a.map(String.init) ?? String(game.target); b = game.score_b.map(String.init) ?? "0" }
    }
}
