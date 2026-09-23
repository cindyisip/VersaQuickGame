import SwiftUI

@main struct VersaQuickGameApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(QGTheme.forest)
                .task { await store.restore() }
                .onOpenURL { store.receive($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { if let url = $0.webpageURL { store.receive(url) } }
        }
    }
}
struct RootView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        Group {
            if store.isRestoring { ProgressView("Opening your games…") }
            else if store.userID == nil { NavigationStack { WelcomeView() } }
            else {
                TabView {
                    NavigationStack { PlayView() }.tabItem { Label("Play", systemImage: "plus.circle") }
                    NavigationStack { HistoryView() }.tabItem { Label("History", systemImage: "list.bullet.rectangle") }
                    NavigationStack { SummaryView() }.tabItem { Label("Summary", systemImage: "chart.bar") }
                    NavigationStack { GroupsView() }.tabItem { Label("Groups", systemImage: "person.3") }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if store.isDemo { Text("DEMO · Fictional games on this device").font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(7).background(QGTheme.lime).foregroundStyle(QGTheme.forest) }
                }
            }
        }
        .sheet(isPresented: $store.settingsPresented) { NavigationStack { SettingsView() }.environmentObject(store) }
        .sheet(item: $store.pendingInvite) { route in NavigationStack { InviteJoinView(token: route.id) }.environmentObject(store) }
        .alert("Something needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK", role: .cancel) { store.error = nil } } message: { Text(store.error ?? "") }
    }
}
