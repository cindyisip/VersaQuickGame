import SwiftUI

struct PlayView: View {
    @EnvironmentObject var store: AppStore
    @State private var draft = GameDraft()
    @State private var savedDetails = GameDraft()
    @State private var editing = false
    @State private var initialized = false
    @State private var selectedSlot: SlotSelection?
    @State private var selectedGame: Game?
    @State private var active: [Game] = []
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BrandHeader()
                Text("Create Quick Game").font(.largeTitle.bold())
                QGCard {
                    HStack { Text("GAME DETAILS").font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); if !editing { Button("Edit") { savedDetails = draft; editing = true }.font(.subheadline) } }
                    if editing { detailsEditor }
                    else {
                        Text(draft.place.isEmpty ? "Choose a place" : draft.place).font(.headline)
                        Text(draft.startsAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                        Text("\(draft.gameType == "singles" ? "Singles" : "Doubles") · \(draft.target) points · \(draft.scoring == "sideout" ? "Side-out" : "Rally") · Win by \(draft.winBy)").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack { Text("Court #").font(.subheadline); Spacer(); TextField("TBD", text: $draft.court).textFieldStyle(.roundedBorder).frame(width: 90).onChange(of: draft.court) { _, v in draft.court = String(v.prefix(20)) } }
                }
                HStack { Text("Who’s playing?").font(.title3.bold()); Spacer(); Button { selectedSlot = SlotSelection(id: 0) } label: { Label("Player pools", systemImage: "person.3") }.font(.caption) }
                QGCard {
                    if draft.gameType == "singles" {
                        Text("YOU").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(store.displayName).font(.subheadline.weight(.semibold))
                        Divider()
                        Text("OPPONENT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        playerInput(1, "Opponent")
                    } else {
                        Text("TEAM A · YOU & YOUR PARTNER").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack { Text(store.displayName).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading); playerInput(0, "Partner") }
                        Divider()
                        Text("TEAM B · OPPONENTS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack { playerInput(1, "Opponent 1"); playerInput(2, "Opponent 2") }
                    }
                }
                Text("A nickname is enough. Players stay Guest - [Nickname] until they claim their spot.").font(.caption).foregroundStyle(.secondary)
                if let error { ErrorNotice(text: error) }
                Button {
                    Task {
                        busy = true; error = nil; defer { busy = false }
                        do {
                            let created = try await store.service.createGame(draft)
                            selectedGame = created
                            let savedPlayers = created.participants.filter { $0.slot > 0 }.sorted { $0.slot < $1.slot }.map { PlayerEntry(nickname: $0.nickname, player_id: $0.pool_player_id) }
                            if draft.gameType == "singles" { draft.players[1] = savedPlayers[0] }
                            else { draft.players = savedPlayers }
                            draft.requestID = UUID().uuidString
                            draft.startsAt = Date()
                            try await store.reload()
                            await loadActive()
                        }
                        catch { self.error = error.localizedDescription }
                    }
                } label: { if busy { ProgressView().tint(.white) } else { Label("Create game & invite", systemImage: "qrcode") } }
                .buttonStyle(PrimaryButton()).disabled(!draft.valid || editing || busy)
                if !active.isEmpty {
                    Text("Games in progress").font(.headline).padding(.top, 8)
                    ForEach(active) { game in Button { selectedGame = game } label: { QGCard { GameRow(game: game, userID: store.userID) } }.buttonStyle(.plain) }
                }
            }.padding(20)
        }.background(QGTheme.background).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
        .task { if !initialized { draft.place = store.defaultPlace; editing = draft.place.isEmpty; initialized = true }; await loadActive() }
        .onChange(of: store.defaultPlace) { old, new in if draft.place.isEmpty || draft.place == old { draft.place = new } }
        .sheet(item: $selectedSlot) { selection in NavigationStack { PlayerPickerView(slot: selection.id, singles: draft.gameType == "singles") { index, player in draft.players[index] = PlayerEntry(nickname: player.nickname, player_id: player.id.hasPrefix("account:") ? nil : player.id) } }.environmentObject(store) }
        .sheet(item: $selectedGame, onDismiss: { Task { await loadActive() } }) { game in NavigationStack { GameDetailView(initial: game) }.environmentObject(store) }
        .refreshable { await loadActive() }
    }
    private var detailsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Game", selection: $draft.gameType) { Text("Doubles").tag("doubles"); Text("Singles").tag("singles") }.pickerStyle(.segmented)
            HStack {
                TextField("Club or playing place", text: $draft.place).textFieldStyle(.roundedBorder).onChange(of: draft.place) { _, v in draft.place = String(v.prefix(120)) }
                Menu { ForEach(store.data?.clubs ?? []) { club in Button(club.name) { draft.place = club.name } } } label: { Image(systemName: "chevron.down.circle").font(.title2) }.accessibilityLabel("Choose a saved club")
            }
            if !draft.place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !(store.data?.clubs.contains { $0.name.caseInsensitiveCompare(draft.place) == .orderedSame } ?? false) {
                Button("Add this place to saved clubs") { Task { do { store.data = try await store.service.addClub(name: draft.place) } catch { self.error = error.localizedDescription } } }.font(.caption)
            }
            DatePicker("When", selection: $draft.startsAt).font(.subheadline)
            HStack {
                Picker("Points", selection: $draft.target) { ForEach([11,15,21], id: \.self) { Text("\($0)").tag($0) } }
                Picker("Scoring", selection: $draft.scoring) { Text("Side-out").tag("sideout"); Text("Rally").tag("rally") }
            }.font(.subheadline)
            Picker("Win by", selection: $draft.winBy) { Text("1 point").tag(1); Text("2 points").tag(2) }.font(.subheadline)
            HStack { Button("Save details") { editing = false }.buttonStyle(.borderedProminent).disabled(draft.place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty); Button("Cancel") { draft.place = savedDetails.place; draft.startsAt = savedDetails.startsAt; draft.target = savedDetails.target; draft.scoring = savedDetails.scoring; draft.winBy = savedDetails.winBy; draft.gameType = savedDetails.gameType; editing = false }.buttonStyle(.bordered) }
        }
    }
    private func playerInput(_ i: Int, _ placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: Binding(get: { draft.players[i].nickname }, set: { draft.players[i].nickname = String($0.prefix(60)); draft.players[i].player_id = nil })).textFieldStyle(.roundedBorder).accessibilityLabel(placeholder + " nickname")
            Button("Choose player") { selectedSlot = SlotSelection(id: i) }.font(.caption).padding(.vertical, 5)
        }.frame(maxWidth: .infinity)
    }
    private func loadActive() async { do { active = try await store.service.games(HistoryFilter()).filter { !$0.completed } } catch { self.error = error.localizedDescription } }
}
struct SlotSelection: Identifiable { var id: Int }

struct PlayerPickerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var slot: Int
    var singles = false
    var onSelect: (Int, PoolPlayer) -> Void
    @State private var query = ""
    @State private var groupID = ""
    @State private var sharedGroups: [SharedGroup] = []
    private var choices: [PoolPlayer] {
        if groupID.hasPrefix("shared:"), let group = sharedGroups.first(where: { "shared:" + $0.id == groupID }) {
            return group.members.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.map { PoolPlayer(id: "account:" + $0.id, nickname: $0.name) }
        }
        let members = store.data?.groups.first { $0.id == groupID }?.member_ids
        return (store.data?.players ?? []).filter { (members == nil || members!.contains($0.id)) && (query.isEmpty || $0.nickname.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        List {
            Section { if !singles { Picker("Add as", selection: $slot) { Text("Your partner").tag(0); Text("Opponent 1").tag(1); Text("Opponent 2").tag(2) } }; Picker("Player pool", selection: $groupID) { Text("All saved players").tag(""); ForEach(store.data?.groups ?? []) { Text($0.name).tag($0.id) }; ForEach(sharedGroups) { Text($0.name + " · shared").tag("shared:" + $0.id) } } }
            Section { ForEach(choices) { player in Button { onSelect(singles ? 1 : slot, player); dismiss() } label: { HStack { VStack(alignment: .leading) { Text(player.nickname); if !player.id.hasPrefix("account:") { Text("Player \(player.id.suffix(6))").font(.caption2).foregroundStyle(.secondary) } }; Spacer(); Image(systemName: "plus.circle") } } } } footer: { Text("Choosing a shared group member enters their name as a guest until they claim the game. Any player can still join.") }
        }.searchable(text: $query, prompt: "Search players").navigationTitle("Choose a player")
            .task { sharedGroups = (try? await store.service.sharedGroups()) ?? [] }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
}
