import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var games: [Game] = []
    @State private var search = ""
    @State private var datesEnabled = false
    @State private var from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var through = Date()
    @State private var selected: Game?
    @State private var busy = false
    @State private var hasMore = false
    @State private var error: String?
    private var filterID: String { "\(search)|\(datesEnabled)|\(from.timeIntervalSince1970)|\(through.timeIntervalSince1970)" }
    var body: some View {
        List {
            Section {
                Toggle("Filter by date range", isOn: $datesEnabled)
                if datesEnabled { DatePicker("From", selection: $from, displayedComponents: .date); DatePicker("Through", selection: $through, in: from..., displayedComponents: .date) }
            }
            if let error { Section { ErrorNotice(text: error); Button("Retry") { Task { await load() } } } }
            if games.isEmpty && !busy && error == nil { ContentUnavailableView("No games found", systemImage: "list.bullet.rectangle", description: Text(search.isEmpty && !datesEnabled ? "Your games will appear here after you create or join one." : "Try another player or date range.")) }
            ForEach(games) { game in Button { selected = game } label: { GameRow(game: game, userID: store.userID) }.buttonStyle(.plain) }
            if hasMore { Button("Load more games") { Task { await load(more: true) } }.disabled(busy) }
            if busy { ProgressView().frame(maxWidth: .infinity) }
        }
        .navigationTitle("Game History").searchable(text: $search, prompt: "Search players")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
        .task(id: filterID) { do { try await Task.sleep(for: .milliseconds(250)) } catch { return }; await load() }
        .refreshable { await load() }
        .sheet(item: $selected, onDismiss: { Task { await load() } }) { game in NavigationStack { GameDetailView(initial: game) }.environmentObject(store) }
    }
    private func load(more: Bool = false) async {
        guard !datesEnabled || from <= through else { error = "Choose an end date after the start date."; return }
        busy = true; error = nil; defer { busy = false }
        let filter = HistoryFilter(from: datesEnabled ? Calendar.current.startOfDay(for: from) : nil,
            until: datesEnabled ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: through)) : nil, search: search, offset: more ? games.count : 0)
        do { let page = try await store.service.games(filter); guard !Task.isCancelled else { return }; games = more ? games + page : page; hasMore = page.count == 30 }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct SummaryView: View {
    @EnvironmentObject var store: AppStore
    @State private var summary = Summary.empty
    @State private var query = ""
    @State private var peer: Peer?
    @State private var playerPeriod: PlayerPeriod = .allTime
    @State private var selectedFrom = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var selectedThrough = Date()
    @State private var opponentCurrent: Stats?
    @State private var opponentPrevious: Stats?
    @State private var teammateCurrent: Stats?
    @State private var teammatePrevious: Stats?
    @State private var busy = false
    @State private var error: String?
    private var filterID: String { "\(peer?.key ?? "")|\(playerPeriod.rawValue)|\(selectedFrom.timeIntervalSince1970)|\(selectedThrough.timeIntervalSince1970)" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Your games, over time.").font(.title2.bold())
                Text("Overall results are all-time · No ratings").font(.subheadline).foregroundStyle(.secondary)
                StatsCard(title: "Overall", stats: summary.overall, prominent: true)
                QGCard {
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Search a player", text: $query).onChange(of: query) { _, new in if peer?.name != new { peer = nil } }; if !query.isEmpty { Button { query = ""; peer = nil } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear player search") } }
                }
                if peer == nil && !query.isEmpty {
                    let matches = summary.people.filter { $0.name.localizedCaseInsensitiveContains(query) }
                    if matches.isEmpty { Text("No completed games with that player yet.").foregroundStyle(.secondary) }
                    ForEach(matches) { player in
                        Button { peer = player; query = player.name } label: { QGCard { HStack { VStack(alignment: .leading) { Text(player.name).font(.headline); Text("\(player.games) shared game(s) · Player \(player.key.suffix(6))").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") } } }.buttonStyle(.plain)
                    }
                }
                if let peer {
                    Text(peer.name).font(.title3.bold())
                    QGCard {
                        Picker("With and against date range", selection: $playerPeriod) {
                            ForEach(PlayerPeriod.allCases, id: \.self) { option in Text(option.title).tag(option) }
                        }.pickerStyle(.menu)
                        if playerPeriod == .custom {
                            DatePicker("From", selection: $selectedFrom, displayedComponents: .date)
                                .onChange(of: selectedFrom) { _, date in if selectedThrough < date { selectedThrough = date } }
                            DatePicker("Through", selection: $selectedThrough, in: selectedFrom..., displayedComponents: .date)
                        }
                        Text("Compare your results both with and against \(peer.name). Overall stats stay all-time.").font(.caption).foregroundStyle(.secondary)
                    }
                    if !busy && error == nil {
                        if playerPeriod == .allTime {
                            StatsCard(title: "WITH · All time", stats: summary.with_player)
                            StatsCard(title: "AGAINST · All time", stats: summary.against_player)
                        } else if let window = playerPeriod.windows(customFrom: selectedFrom, through: selectedThrough),
                                  let teammateCurrent, let teammatePrevious,
                                  let opponentCurrent, let opponentPrevious {
                            PeriodComparison(label: "WITH", current: teammateCurrent, previous: teammatePrevious, window: window)
                            PeriodComparison(label: "AGAINST", current: opponentCurrent, previous: opponentPrevious, window: window)
                        }
                    }
                }
                if busy { ProgressView().frame(maxWidth: .infinity) }
                if let error { ErrorNotice(text: error); Button("Retry") { Task { await load() } } }
                Text("Stats describe recorded games, including self-reported results. They are not a skill rating.").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.background(QGTheme.background).navigationTitle("Summary")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
        .task(id: filterID) { await load() }.refreshable { await load() }
    }
    private func load() async {
        busy = true; error = nil
        opponentCurrent = nil; opponentPrevious = nil
        teammateCurrent = nil; teammatePrevious = nil
        defer { busy = false }
        let selectedPeer = peer
        let window = playerPeriod.windows(customFrom: selectedFrom, through: selectedThrough)
        if selectedPeer != nil && playerPeriod != .allTime && window == nil {
            error = "Choose an end date on or after the start date."; return
        }
        do {
            let result = try await store.service.summary(peer: selectedPeer?.key)
            guard !Task.isCancelled else { return }
            var teammateNow: Stats?, teammateBefore: Stats?
            var opponentNow: Stats?, opponentBefore: Stats?
            if let selectedPeer, let window {
                teammateNow = try await store.service.teammateStats(peer: selectedPeer.key, from: window.current.start, until: window.current.end)
                guard !Task.isCancelled else { return }
                teammateBefore = try await store.service.teammateStats(peer: selectedPeer.key, from: window.previous.start, until: window.previous.end)
                guard !Task.isCancelled else { return }
                opponentNow = try await store.service.opponentStats(peer: selectedPeer.key, from: window.current.start, until: window.current.end)
                guard !Task.isCancelled else { return }
                opponentBefore = try await store.service.opponentStats(peer: selectedPeer.key, from: window.previous.start, until: window.previous.end)
                guard !Task.isCancelled else { return }
            }
            summary = result
            teammateCurrent = teammateNow; teammatePrevious = teammateBefore
            opponentCurrent = opponentNow; opponentPrevious = opponentBefore
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
struct PeriodComparison: View {
    let label: String
    let current: Stats
    let previous: Stats
    let window: PlayerWindows
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label == "WITH" ? "Playing together" : "Playing against").font(.headline)
            StatsCard(title: "\(label) · \(window.current.label)", stats: current)
            StatsCard(title: "PREVIOUS · \(window.previous.label)", stats: previous)
            if current.games > 0 && previous.games > 0 {
                let change = current.win_percent - previous.win_percent
                Text("\(label) win rate: \(change >= 0 ? "+" : "")\(change, specifier: "%.1f") percentage points")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("A win-rate comparison needs a recorded game in both periods.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private extension DateInterval {
    var label: String {
        let finalDay = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        return "\(start.formatted(date: .abbreviated, time: .omitted)) – \(finalDay.formatted(date: .abbreviated, time: .omitted))"
    }
}
struct StatsCard: View {
    let title: String
    let stats: Stats
    var prominent = false
    var body: some View {
        QGCard {
            HStack { Text(title).font(.headline); Spacer(); Text("\(stats.games) games").font(.subheadline).foregroundStyle(.secondary) }
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("\(stats.wins)").font(prominent ? .largeTitle.bold() : .title.bold()); Text("Wins · \(stats.win_percent, specifier: "%.1f")%").font(.subheadline) }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) { Text("\(stats.losses)").font(prominent ? .largeTitle.bold() : .title.bold()); Text("Losses · \(stats.loss_percent, specifier: "%.1f")%").font(.subheadline) }.frame(maxWidth: .infinity, alignment: .leading)
            }.monospacedDigit()
            if stats.games == 0 { Text("No completed games yet.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
