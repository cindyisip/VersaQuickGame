import SwiftUI
import UIKit

struct GroupsView: View {
    @EnvironmentObject var store: AppStore
    @State private var editor: GroupEditorRoute?
    @State private var shared: [SharedGroup] = []
    @State private var sharedName = ""
    @State private var joinCode = ""
    @State private var sharedError: String?
    @State private var selectedGroup: SharedGroup?
    var body: some View {
        List {
            Section("Shared groups") {
                Text("Members see a live leaderboard. Games qualify automatically when claimed players meet the group rule.").font(.caption).foregroundStyle(.secondary)
                ForEach(shared) { group in Button { selectedGroup = group } label: {
                    HStack { Image(systemName: "trophy.fill"); Text(group.name); Spacer(); Text("\(group.members.count) members").font(.caption).foregroundStyle(.secondary) }
                } }
                if !store.isDemo {
                    HStack { TextField("New group name", text: $sharedName); Button("Create") { Task { await perform { shared = try await store.service.createSharedGroup(name: sharedName, rule: "one_each"); sharedName = "" } } }.disabled(sharedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    HStack { TextField("Group invitation code", text: $joinCode).textInputAutocapitalization(.never).autocorrectionDisabled(); Button("Join") { Task { await perform { shared = try await store.service.joinGroup(token: joinCode.trimmingCharacters(in: .whitespacesAndNewlines)); joinCode = "" } } }.disabled(joinCode.isEmpty) }
                }
            }
            Section("Saved player pools") { ForEach(store.data?.groups ?? []) { group in
                Button { editor = GroupEditorRoute(group: group) } label: {
                    HStack { Image(systemName: "person.3.fill").frame(width: 35); VStack(alignment: .leading, spacing: 5) { Text(group.name).font(.headline); Text("\(group.member_ids.count) players").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                }.buttonStyle(.plain)
            }
            if store.data?.groups.isEmpty != false { ContentUnavailableView("Build your player pools", systemImage: "person.3", description: Text("Try Tuesday Group, Monday Group, or Pinoy Group.")) }
            Button("Create player pool", systemImage: "plus") { editor = GroupEditorRoute(group: nil) }
            }
            if let sharedError { Section { ErrorNotice(text: sharedError) } }
        }.navigationTitle("Groups").toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
        .task { do { try await store.reload(); shared = try await store.service.sharedGroups() } catch { sharedError = error.localizedDescription } }
        .sheet(item: $editor) { route in NavigationStack { GroupEditorView(group: route.group) }.environmentObject(store) }
        .sheet(item: $selectedGroup, onDismiss: { Task { shared = (try? await store.service.sharedGroups()) ?? shared } }) { group in NavigationStack { SharedGroupView(group: group) }.environmentObject(store) }
    }
    @MainActor private func perform(_ action: () async throws -> Void) async { do { try await action(); sharedError = nil } catch { sharedError = error.localizedDescription } }
}

struct SharedGroupView: View {
    @EnvironmentObject var store: AppStore
    @State var group: SharedGroup
    @State private var board: GroupBoard?
    @State private var view = "players"
    @State private var error: String?
    @State private var inviteCode: String?
    var body: some View {
        List {
            Section("Who counts") {
                Text(group.eligibility == "all_players" ? "All four players must be members" : "At least one member on each team")
                if group.owner_id == store.userID { Picker("Game rule", selection: $group.eligibility) {
                    Text("One on each team").tag("one_each"); Text("All four players").tag("all_players")
                }.onChange(of: group.eligibility) { _, rule in
                    Task {
                        do {
                            let groups = try await store.service.setGroupRule(id: group.id, rule: rule)
                            let updatedGroup = groups.first { candidate in candidate.id == group.id }
                            if let updatedGroup { group = updatedGroup }
                            await refresh()
                        } catch let caughtError {
                            self.error = caughtError.localizedDescription
                        }
                    }
                } }
            }
            Section("Leaderboard") {
                Picker("View", selection: $view) { Text("Players").tag("players"); Text("Partners").tag("partners") }.pickerStyle(.segmented)
                if let board {
                    ForEach(board.leaders) { leader in
                        VStack(alignment: .leading) {
                            Text(view == "partners" ? "\(leader.name) + \(leader.partner_name)" : leader.name).font(.headline)
                            Text("\(leader.wins) W · \(leader.losses) L · \(leader.games) games · \(leader.win_percent.formatted())% wins").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if board.leaders.isEmpty { Text("No qualifying scored games yet.").foregroundStyle(.secondary) }
                } else { ProgressView() }
            }
            Section("Qualifying games") {
                // Keep each formatted value separate so Swift 5's type checker can compile this view reliably.
                ForEach(board?.games ?? []) { game in
                    let gameDate = Dates.parse(game.starts_at) ?? Date.now
                    let dateText = gameDate.formatted(date: .abbreviated, time: .omitted)
                    let scoreText = "\(game.score_a) – \(game.score_b)"
                    HStack {
                        Text(dateText)
                        Spacer()
                        Text(scoreText)
                    }
                }
            }
            Section("Members") { ForEach(group.members) { member in Text(member.name) } }
            Section("Invite a member") {
                Button("Copy invitation code") { Task { do {
                    inviteCode = try await store.service.groupInvite(id: group.id)
                    UIPasteboard.general.string = inviteCode
                } catch let caughtError { error = caughtError.localizedDescription } } }
                if inviteCode != nil { Text("Code copied. Send it to the player, who can enter it on the Groups screen after signing in.").font(.caption).foregroundStyle(.secondary) }
            }
            if let error { ErrorNotice(text: error) }
        }.navigationTitle(group.name).task { await refresh() }.onChange(of: view) { _, _ in Task { await refresh() } }.refreshable { await refresh() }
    }
    private func refresh() async {
        do {
            board = try await store.service.groupBoard(id: group.id, view: view)
            error = nil
        } catch let caughtError {
            self.error = caughtError.localizedDescription
        }
    }
}
struct GroupEditorRoute: Identifiable { let id = UUID(); var group: PlayerGroup? }
struct GroupEditorView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let group: PlayerGroup?
    @State private var name = ""
    @State private var members = Set<String>()
    @State private var query = ""
    @State private var newNickname = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        Form {
            Section("Group name") { TextField("For example, Tuesday Group", text: $name).onChange(of: name) { _, v in name = String(v.prefix(60)) } }
            Section("Add someone new") {
                TextField("Nickname", text: $newNickname).onChange(of: newNickname) { _, v in newNickname = String(v.prefix(60)) }
                Button("Add to player pool") { Task { await run { let player = try await store.service.addPlayer(nickname: newNickname.trimmingCharacters(in: .whitespacesAndNewlines)); try await store.reload(); members.insert(player.id); newNickname = "" } } }.disabled(newNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            }
            Section { TextField("Search your saved players", text: $query); ForEach((store.data?.players ?? []).filter { query.isEmpty || $0.nickname.localizedCaseInsensitiveContains(query) }) { player in
                Button { if members.contains(player.id) { members.remove(player.id) } else { members.insert(player.id) } } label: { HStack { VStack(alignment: .leading) { Text(player.nickname); Text("Player \(player.id.suffix(6))").font(.caption2).foregroundStyle(.secondary) }; Spacer(); Image(systemName: members.contains(player.id) ? "checkmark.circle.fill" : "circle") } }.buttonStyle(.plain)
            } } header: { Text("Members · \(members.count) selected") } footer: { Text("A person can belong to several groups. Adding a nickname does not create an account for them.") }
            if let error { Section { ErrorNotice(text: error) } }
        }.navigationTitle(group == nil ? "Create player pool" : "Player pool")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await run { store.data = try await store.service.saveGroup(id: group?.id, name: name, members: Array(members)); dismiss() } } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy) }
        }.onAppear { name = group?.name ?? ""; members = Set(group?.member_ids ?? []) }
    }
    @MainActor private func run(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await work()
        } catch let caughtError {
            self.error = caughtError.localizedDescription
        }
    }
}
