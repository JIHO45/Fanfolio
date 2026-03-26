//
//  MatchListView.swift
//  Fanfolio
//
//  팀의 지난 경기 결과와 예정 경기 일정을 불러와 아카이브로 저장하는 화면.
//  ESPN (NFL·NBA·MLB·EPL 등) 또는 API-Sports (KBO) 중 리그에 맞는 API를 자동 선택합니다.

import SwiftUI
import SwiftData

struct MatchListView: View {
    let folder: SportsFanFolder

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var allEvents: [MatchEvent] = []
    @State private var selectedTab: EventTab = .past
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var savingEventIDs: Set<String> = []
    @State private var justSavedIDs: Set<String> = []

    enum EventTab: String, CaseIterable {
        case past     = "past"
        case upcoming = "upcoming"
        
        var displayName: String {
            switch self {
            case .past:     return String(localized: "eventTab.past",     defaultValue: "지난 경기")
            case .upcoming: return String(localized: "eventTab.upcoming", defaultValue: "예정 경기")
            }
        }
    }

    private var archivedIDs: Set<String> {
        Set(folder.matches.compactMap { $0.externalEventID })
    }

    // 완료 + 진행 중 경기: 진행 중을 맨 위로, 나머지는 최신순 최대 5개
    private var pastEvents: [MatchEvent] {
        allEvents
            .filter { $0.isCompleted || $0.isLive }
            .sorted {
                // 진행 중 경기를 항상 맨 위로
                if $0.isLive != $1.isLive { return $0.isLive }
                return ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
            }
            .prefix(5)
            .map { $0 }
    }

    // 예정 경기: 진행 중 제외, 날짜 빠른 순 최대 5개
    private var upcomingEvents: [MatchEvent] {
        allEvents
            .filter { !$0.isCompleted && !$0.isLive }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            .prefix(5)
            .map { $0 }
    }

    private var displayedEvents: [MatchEvent] {
        selectedTab == .past ? pastEvents : upcomingEvents
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(message: error)
                } else {
                    mainContent
                }
            }
            .navigationTitle(String(localized: "matchImport.navigationTitle", defaultValue: "경기 불러오기"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.action.close", defaultValue: "닫기")) { dismiss() }
                }
            }
            // 시트가 열린 뒤 폴더 편집으로 리그·팀이 바뀌면 일정을 다시 불러옴
            .task(id: matchListScheduleTaskID(folder)) {
                await loadSchedule()
            }
        }
    }

    // MARK: - 메인 컨텐츠

    private var mainContent: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "matchImport.picker.accessibility", defaultValue: "탭 선택"), selection: $selectedTab) {
                ForEach(EventTab.allCases, id: \.self) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 12)

            if displayedEvents.isEmpty {
                emptyView
            } else {
                eventList
            }
        }
    }

    // MARK: - 경기 리스트
    private var eventList: some View {
        List {
            Section {
                ForEach(displayedEvents) { event in
                    EventRow(
                        event: event,
                        folder: folder,
                        isArchived: archivedIDs.contains(event.id),
                        isSaving: savingEventIDs.contains(event.id),
                        justSaved: justSavedIDs.contains(event.id)
                    ) {
                        Task { await archiveEvent(event) }
                    }
                }
            } header: {
                Text(
                    selectedTab == .past
                        ? String(localized: "matchImport.section.recentResults", defaultValue: "최근 경기 결과 (최대 5경기)")
                        : String(localized: "matchImport.section.upcomingSchedule", defaultValue: "예정 경기 일정 (최대 5경기)")
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text(
                    selectedTab == .past
                        ? String(localized: "matchImport.footer.pastHint", defaultValue: "경기를 탭하면 내 아카이브에 추가됩니다. 이미 추가된 경기는 체크 표시됩니다.")
                        : String(localized: "matchImport.footer.upcomingHint", defaultValue: "예정 경기를 탭하면 내 일정에 추가됩니다. 경기 후 결과를 직접 입력하세요.")
                )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 보조 뷰

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(String(localized: "matchImport.loading", defaultValue: "경기 목록을 불러오는 중..."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(String(localized: "matchImport.error.title", defaultValue: "불러오기 실패"))
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "common.action.retry", defaultValue: "다시 시도")) {
                Task { await loadSchedule() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            selectedTab == .past
                ? String(localized: "matchImport.empty.pastTitle", defaultValue: "지난 경기 없음")
                : String(localized: "matchImport.empty.upcomingTitle", defaultValue: "예정 경기 없음"),
            systemImage: selectedTab == .past ? "clock.arrow.circlepath" : "calendar",
            description: Text(
                selectedTab == .past
                    ? String(
                        format: String(localized: "matchImport.empty.pastDescription", defaultValue: "‘%@’의 완료된 경기를 찾을 수 없습니다."),
                        locale: .autoupdatingCurrent,
                        folder.name
                    )
                    : String(
                        format: String(localized: "matchImport.empty.upcomingDescription", defaultValue: "‘%@’의 예정 경기를 찾을 수 없습니다."),
                        locale: .autoupdatingCurrent,
                        folder.name
                    )
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 데이터 로드

    private func loadSchedule() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let leagueCode = folder.leagueCode ?? ""
        let isESPN     = ESPNPlayerService.shared.supportsLiveScoreboard(leagueCode)

        guard NetworkMonitor.shared.isConnected else {
            errorMessage = String(localized: "network.error.noConnection", defaultValue: "인터넷 연결이 없습니다. 연결 후 다시 시도해주세요.")
            return
        }

        if isESPN,
           let espnTeam = ESPNTeamsLoader.team(name: folder.name, leagueCode: folder.leagueCode),
           !espnTeam.id.isESPNFakeID {
            do {
                allEvents = try await ESPNPlayerService.shared.fetchTeamSchedule(
                    teamESPNId: espnTeam.id,
                    leagueCode: leagueCode
                )
                if allEvents.isEmpty {
                    errorMessage = String(
                        format: String(localized: "matchImport.error.emptyScheduleFormat", defaultValue: "‘%@’의 경기 일정을 불러올 수 없습니다."),
                        locale: .autoupdatingCurrent,
                        folder.name
                    )
                }
            } catch {
                errorMessage = String(
                    format: String(localized: "matchImport.error.loadFailedFormat", defaultValue: "경기 목록을 불러오지 못했습니다.\n%@"),
                    locale: .autoupdatingCurrent,
                    error.localizedDescription
                )
            }
        } else if leagueCode == "KBO", let teamID = folder.apiSportsTeamID {
            if APIConfig.apiSportsKey.isEmpty {
                errorMessage = String(localized: "api.error.noAPIKey", defaultValue: "API 키가 설정되지 않았습니다. 프로젝트 루트에서 APIKeys.xcconfig.example을 복사해 APIKeys.xcconfig를 만들고 API_SPORTS_KEY를 넣은 뒤 다시 빌드하세요.")
            } else if APIRateLimiter.shared.isLimitReached {
                errorMessage = String(localized: "api.error.dailyLimitExceeded", defaultValue: "오늘 API 호출 한도(100회)를 초과했습니다. 내일 다시 시도해주세요.")
            } else {
                do {
                    allEvents = try await APISportsService.shared.fetchKBOSchedule(teamID: teamID)
                } catch {
                    errorMessage = String(
                    format: String(localized: "matchImport.error.loadFailedFormat", defaultValue: "경기 목록을 불러오지 못했습니다.\n%@"),
                    locale: .autoupdatingCurrent,
                    error.localizedDescription
                )
                }
            }
        } else {
            errorMessage = String(localized: "matchImport.error.unsupportedLeague", defaultValue: "이 리그는 경기 불러오기를 지원하지 않습니다.\n(지원: NFL·NBA·MLB·EPL 등 ESPN 리그, KBO)")
        }
    }

    // MARK: - 아카이브 저장

    private func archiveEvent(_ event: MatchEvent) async {
        let eventID = event.id
        guard !archivedIDs.contains(eventID),
              !savingEventIDs.contains(eventID) else { return }

        savingEventIDs.insert(eventID)
        defer { savingEventIDs.remove(eventID) }

        let model = event.toSportsModel(folder: folder)
        modelContext.insert(model)

        do {
            try modelContext.save()
            justSavedIDs.insert(eventID)
            try? await Task.sleep(nanoseconds: 800_000_000)
        } catch {
            modelContext.delete(model)
        }
    }

    /// `.task(id:)`용 — `SportType`이 들어간 튜플은 `Equatable` 자동 충족이 안 되는 경우가 있어 문자열로 고정
    private func matchListScheduleTaskID(_ folder: SportsFanFolder) -> String {
        "\(folder.sportType.rawValue)\u{1f}\(folder.leagueCode ?? "")\u{1f}\(folder.name)\u{1f}\(folder.apiSportsTeamID ?? 0)"
    }
}

// MARK: - 경기 행 컴포넌트

private struct EventRow: View {
    let event: MatchEvent
    let folder: SportsFanFolder
    let isArchived: Bool
    let isSaving: Bool
    let justSaved: Bool
    let onTap: () -> Void

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        fmt.locale = Locale.autoupdatingCurrent
        return fmt
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        fmt.locale = Locale.autoupdatingCurrent
        return fmt
    }()

    private var statusColor: Color {
        if isArchived || justSaved { return .green }
        if event.isLive { return .red }
        if !event.isCompleted { return .blue }
        if let r = event.result { return r.color }
        return .secondary
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                statusBadge

                VStack(alignment: .leading, spacing: 4) {
                    Text("vs \(event.opponentName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let date = event.date {
                            Text(event.isCompleted
                                 ? Self.dateFormatter.string(from: date)
                                 : Self.dateTimeFormatter.string(from: date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if (event.isCompleted || event.isLive),
                           let my = event.myScore,
                           let opp = event.opponentScore {
                            Text("·").font(.caption).foregroundStyle(.tertiary)
                            Text("\(my) - \(opp)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(event.isLive ? .red : .secondary)
                        }

                        if !event.isCompleted && !event.isLive {
                            Text("·").font(.caption).foregroundStyle(.tertiary)
                            Text(event.isHome ? "홈" : "원정")
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                        }

                        if let league = event.leagueName {
                            Text("·").font(.caption).foregroundStyle(.tertiary)
                            Text(LeagueInfo.displayName(for: league))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                if isSaving {
                    ProgressView().scaleEffect(0.7)
                } else if isArchived || justSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isArchived || isSaving)
    }

    @ViewBuilder
    private var statusBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(statusColor.opacity(0.12))
                .frame(width: 40, height: 40)

            if isArchived || justSaved {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            } else if event.isLive {
                VStack(spacing: 1) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.red)
                }
            } else if !event.isCompleted {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.blue)
            } else if let r = event.result {
                Text(r == .win ? "W" : r == .loss ? "L" : "D")
                    .font(.caption.bold())
                    .foregroundStyle(r.color)
            } else {
                Image(systemName: "questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - PastEvent → SportsModel 변환

extension MatchEvent {
    func toSportsModel(folder: SportsFanFolder) -> SportsModel {
        let title = "\(folder.displayName) vs \(opponentName)"
        let my    = myScore ?? 0
        let opp   = opponentScore ?? 0

        let result: MatchResult
        if isCompleted {
            if my > opp      { result = .win }
            else if my < opp { result = .loss }
            else             { result = .draw }
        } else {
            result = .draw
        }

        let status: MatchStatus = isCompleted ? .completed : (isLive ? .upcoming : .upcoming)

        let periodData: Data? = {
            guard !periods.isEmpty else { return nil }
            return try? JSONEncoder().encode(periods)
        }()

        let model = SportsModel(
            title: title,
            opponentTeam: opponentName,
            myTeamScore: my,
            opponentScore: opp,
            matchResult: result,
            matchStatus: status,
            isHomeGame: isHome,
            date: date,
            orderIndex: folder.matches.count,
            externalEventID: id,
            importedPeriodScoresData: periodData
        )
        model.folder = folder
        return model
    }
}
