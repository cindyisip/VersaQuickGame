import Foundation
import Combine

@MainActor final class AppStore: ObservableObject {
    @Published var userID: String?
    @Published var data: Bootstrap?
    @Published var isRestoring = true
    @Published var error: String?
    @Published var pendingInvite: InviteRoute?
    @Published var settingsPresented = false
    @Published var isDemo = false
    var service: any GameService = SupabaseGameService()
    var displayName: String { data?.profile.display_name ?? "Player" }
    var defaultPlace: String { data?.clubs.first { $0.id == data?.profile.default_club_id }?.name ?? "" }
    var configured: Bool { (service as? SupabaseGameService)?.configured ?? true }

    func restore() async {
        defer { isRestoring = false }
        do { let restored = try await service.restoreUser(); if restored != nil { try await reload() }; userID = restored }
        catch { self.error = error.localizedDescription }
    }
    func reload() async throws { data = try await service.bootstrap(name: nil) }
    func verify(email: String, code: String, name: String) async throws {
        let verified = try await service.verifyCode(email: email, code: code)
        data = try await service.bootstrap(name: name)
        userID = verified
    }
    func startDemo() async {
        service = DemoGameService(); isDemo = true
        do { let restored = try await service.restoreUser(); try await reload(); userID = restored }
        catch { self.error = error.localizedDescription }
    }
    func signOut() async {
        do {
            try await service.signOut()
            data = nil; userID = nil; isDemo = false; settingsPresented = false
            service = SupabaseGameService()
        } catch { self.error = error.localizedDescription }
    }
    func deleteAccount() async throws {
        try await service.deleteAccount()
        data = nil; userID = nil; isDemo = false; settingsPresented = false; pendingInvite = nil
        service = SupabaseGameService()
    }
    func receive(_ url: URL) {
        if let token = GameRules.invitationToken(from: url, expectedHost: AppConfig.inviteBase?.host) {
            if isDemo { error = "Exit demo mode before opening a real invitation."; return }
            pendingInvite = InviteRoute(id: token)
        }
    }
}
struct InviteRoute: Identifiable { var id: String }
