//
//  PastEventsListView.swift
//  Fanfolio
//
//  TheSportsDB에서 팀의 최근 경기 결과를 불러와 Fanfolio 아카이브로 저장하는 화면

import SwiftUI
import SwiftData

struct PastEventsListView: View {
    let folder: SportsFanFolder

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var events: [TheSportsDBEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var savingEventIDs: Set<String> = []
    @State private var justSavedIDs: Set<String> = []

    // 이미 아카이브된 외부 이벤트 ID 집합
    private var archivedIDs: Set<String> {
        Set(folder.matches.compactMap { $0.externalEventID })
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(message: error)
                } else if events.isEmpty {
                    emptyView
                } else {
                    eventList
                }
            }
            .navigationTitle("지난 경기 불러오기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
            }
            .task {
                await loadEvents()
            }
        }
    }

    // MARK: - 이벤트 리스트

    private var eventList: some View {
        List {
            Section {
                ForEach(events) { event in
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
                Text("최근 경기 결과 · TheSportsDB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("경기를 탭하면 내 아카이브에 추가됩니다. 이미 추가된 경기는 체크 표시됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 로딩 뷰

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("경기 목록을 불러오는 중...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 에러 뷰

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("불러오기 실패")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("다시 시도") {
                Task { await loadEvents() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 빈 상태 뷰

    private var emptyView: some View {
        ContentUnavailableView(
            "경기 정보 없음",
            systemImage: "sportscourt",
            description: Text("TheSportsDB에서 '\(folder.name)'의 최근 경기를 찾을 수 없습니다.")
        )
    }

    // MARK: - 데이터 로드

    private func loadEvents() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let team = try await TheSportsDBService.shared.searchTeam(name: folder.name),
                  let teamID = team.idTeam else {
                errorMessage = "'\(folder.name)' 팀을 TheSportsDB에서 찾을 수 없습니다."
                return
            }
            let result = try await TheSportsDBService.shared.fetchRecentEvents(theSportsDBTeamID: teamID)
            // 최신순 정렬
            events = result.sorted {
                ($0.dateEvent ?? "") > ($1.dateEvent ?? "")
            }
        } catch {
            errorMessage = "경기 목록을 불러오지 못했습니다.\n\(error.localizedDescription)"
        }
    }

    // MARK: - 아카이브 저장

    private func archiveEvent(_ event: TheSportsDBEvent) async {
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
            // 0.8초 뒤 "방금 저장" 강조 해제
            try? await Task.sleep(nanoseconds: 800_000_000)
        } catch {
            modelContext.delete(model)
        }
    }
}

// MARK: - 경기 행 컴포넌트

private struct EventRow: View {
    let event: TheSportsDBEvent
    let folder: SportsFanFolder
    let isArchived: Bool
    let isSaving: Bool
    let justSaved: Bool
    let onTap: () -> Void

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()
    private static let displayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt
    }()

    private var parsedDate: Date? {
        guard let str = event.dateEvent else { return nil }
        return Self.dateFormatter.date(from: str)
    }
    private var displayDate: String {
        parsedDate.map { Self.displayFormatter.string(from: $0) } ?? (event.dateEvent ?? "")
    }

    private var homeScore: Int? { Int(event.intHomeScore ?? "") }
    private var awayScore: Int? { Int(event.intAwayScore ?? "") }
    private var hasScore: Bool { homeScore != nil && awayScore != nil }

    // 내 팀이 홈인지 원정인지
    private var isHomeGame: Bool {
        let folderName = folder.name.lowercased()
        return event.strHomeTeam?.lowercased().contains(folderName) == true
    }
    private var myScore: Int? { isHomeGame ? homeScore : awayScore }
    private var oppScore: Int? { isHomeGame ? awayScore : homeScore }
    private var opponentName: String {
        isHomeGame ? (event.strAwayTeam ?? "상대팀") : (event.strHomeTeam ?? "상대팀")
    }

    private var result: MatchResult? {
        guard let my = myScore, let opp = oppScore else { return nil }
        if my > opp { return .win }
        if my < opp { return .loss }
        return .draw
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // 상태 아이콘
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(statusColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    statusIcon
                }

                // 경기 정보
                VStack(alignment: .leading, spacing: 4) {
                    Text("vs \(opponentName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(displayDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if hasScore, let my = myScore, let opp = oppScore {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text("\(my) - \(opp)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        if let league = event.strLeague {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(league)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // 아카이브 상태
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

    private var statusColor: Color {
        if isArchived || justSaved { return .green }
        if let r = result { return r.color }
        return .secondary
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isArchived || justSaved {
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(.green)
        } else if let r = result {
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

// MARK: - TheSportsDBEvent -> SportsModel 변환

extension TheSportsDBEvent {
    func toSportsModel(folder: SportsFanFolder) -> SportsModel {
        let folderName = folder.name.lowercased()
        let isHome = strHomeTeam?.lowercased().contains(folderName) == true

        let homeScore = Int(intHomeScore ?? "") ?? 0
        let awayScore = Int(intAwayScore ?? "") ?? 0
        let myScore = isHome ? homeScore : awayScore
        let oppScore = isHome ? awayScore : homeScore
        let opponentName = isHome ? (strAwayTeam ?? "상대팀") : (strHomeTeam ?? "상대팀")

        let result: MatchResult
        if myScore > oppScore { result = .win }
        else if myScore < oppScore { result = .loss }
        else { result = .draw }

        let date: Date? = {
            guard let str = dateEvent else { return nil }
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            return fmt.date(from: str)
        }()

        let title = "\(folder.displayName) vs \(opponentName)"

        let model = SportsModel(
            title: title,
            opponentTeam: opponentName,
            myTeamScore: myScore,
            opponentScore: oppScore,
            matchResult: result,
            matchStatus: .completed,
            isHomeGame: isHome,
            date: date,
            orderIndex: folder.matches.count,
            externalEventID: idEvent
        )
        model.folder = folder
        return model
    }
}
