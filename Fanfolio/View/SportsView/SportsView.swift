//
//  SportsView.swift
//  Fanfolio
//
//  Created by 박지호 on 12/15/25.
//

import SwiftUI
import SwiftData
import os.log
import Kingfisher

// MARK: - 탭 정의

enum SportsTab: Hashable {
    case matches
    case team
    case stats
}

// MARK: - SportsView (TabView 컨테이너)

struct SportsView: View {
    let folder: SportsFanFolder

    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: SportsLiveScoreViewModel
    @State private var selectedTab: SportsTab = .matches

    // 경기 탭 시트 트리거 (탭 내부 바인딩과 공유)
    @State private var showingAddMatchSheet = false
    @State private var showingMatchSheet = false
    // 폴더 편집 시트 (팀 정보 탭 툴바)
    @State private var showingFolderEditSheet = false

    init(folder: SportsFanFolder) {
        self.folder = folder
        _viewModel = State(initialValue: SportsLiveScoreViewModel(folder: folder))
    }

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            // 탭1: 경기
            SportsMatchesTab(
                folder: folder,
                viewModel: viewModel,
                showingAddMatchSheet: $showingAddMatchSheet,
                showingMatchSheet: $showingMatchSheet
            )
            .tabItem {
                Label(
                    String(localized: "sports.tab.matches", defaultValue: "경기"),
                    systemImage: "sportscourt"
                )
            }
            .tag(SportsTab.matches)

            // 탭2: 팀 정보 (기타 카테고리 제외)
            if folder.sportType != .other {
                TeamInfoDetailView(folder: folder)
                    .tabItem {
                        Label(
                            String(localized: "sports.tab.team", defaultValue: "팀 정보"),
                            systemImage: "person.3.fill"
                        )
                    }
                    .tag(SportsTab.team)
            }

            // 탭3: 팬 통계
            FanStatsView(folder: folder)
                .tabItem {
                    Label(
                        String(localized: "sports.tab.stats", defaultValue: "팬 통계"),
                        systemImage: "chart.bar.fill"
                    )
                }
                .tag(SportsTab.stats)
        }
        // MARK: - 폴링 수명주기
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.startPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            viewModel.stopPolling()
        }
        // MARK: - 자동 동기화
        // ModelContext는 non-Sendable이므로 뷰 메서드에서 직접 처리합니다.
        .task(id: "\(folder.sportType.rawValue)\u{1f}\(folder.leagueCode ?? "")\u{1f}\(folder.matches.count)") {
            guard viewModel.checkAndUpdateSyncCooldown() else { return }
            await syncPendingMatches()
            await syncKBOPendingMatches()
        }
        // MARK: - 시트
        .sheet(isPresented: $showingFolderEditSheet) {
            AddFolderView(folder: folder)
        }
        // MARK: - 동적 툴바
        .toolbar {
            dynamicToolbar
        }
    }

    // MARK: - 예정 경기 자동 동기화

    /// 날짜가 지난 예정·진행중 티켓을 ESPN 최신 데이터로 조용히 업데이트합니다.
    private func syncPendingMatches() async {
        let leagueCode = folder.leagueCode ?? ""
        guard ESPNPlayerService.shared.supportsLiveScoreboard(leagueCode) else { return }

        let now = Date()
        let pendingMatches = folder.matches.filter {
            $0.matchStatus != .completed
            && $0.externalEventID?.hasPrefix("espn:") == true
            && ($0.date.map { $0 <= now.addingTimeInterval(3600) } ?? false)
        }
        guard !pendingMatches.isEmpty else { return }

        guard let espnTeam = ESPNTeamsLoader.team(name: folder.name, leagueCode: folder.leagueCode),
              !espnTeam.id.isESPNFakeID else { return }

        let latestSchedule: [MatchEvent]
        do {
            latestSchedule = try await ESPNPlayerService.shared.fetchTeamSchedule(
                teamESPNId: espnTeam.id,
                leagueCode: leagueCode
            )
        } catch {
            Logger.api.warning("syncPendingMatches 스케줄 조회 실패 (\(folder.name)): \(error.localizedDescription)")
            return
        }
        guard !latestSchedule.isEmpty else { return }

        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let scheduleIDs  = Set(latestSchedule.map { $0.id })

        var hasChanges = false
        for match in pendingMatches {
            guard let eventID = match.externalEventID else { continue }

            if !scheduleIDs.contains(eventID),
               let matchDate = match.date,
               matchDate < sevenDaysAgo {
                ArchivePhotoStore.delete(paths: match.photoPaths ?? [])
                modelContext.delete(match)
                hasChanges = true
                Logger.data.info("좀비 티켓 삭제: \(eventID) (\(folder.name))")
                continue
            }

            guard let updated = latestSchedule.first(where: { $0.id == eventID }) else { continue }

            if updated.isCompleted {
                match.matchStatus   = .completed
                match.myTeamScore   = updated.myScore ?? match.myTeamScore
                match.opponentScore = updated.opponentScore ?? match.opponentScore
                let my = match.myTeamScore, opp = match.opponentScore
                match.matchResult   = my > opp ? .win : (my < opp ? .loss : .draw)
                hasChanges = true
            } else if updated.isLive {
                match.matchStatus = .live
                if let s = updated.myScore       { match.myTeamScore   = s }
                if let s = updated.opponentScore { match.opponentScore = s }
                hasChanges = true
            }
        }

        if hasChanges {
            try? modelContext.save()
            Logger.data.info("자동 동기화 완료: \(folder.name) 예정 경기 업데이트됨")
        }
    }

    /// 날짜가 지난 KBO 예정·진행중 티켓을 Firestore 캐시로 조용히 업데이트합니다.
    private func syncKBOPendingMatches() async {
        guard (folder.leagueCode ?? "") == "KBO",
              let teamID = folder.apiSportsTeamID, teamID > 0 else { return }

        let now = Date()
        let pendingMatches = folder.matches.filter {
            $0.matchStatus != .completed
            && $0.externalEventID?.hasPrefix("firestore-kbo:") == true
            && ($0.date.map { $0 <= now.addingTimeInterval(3600) } ?? false)
        }
        guard !pendingMatches.isEmpty else { return }

        let latestSchedule: [MatchEvent]
        do {
            latestSchedule = try await KBOFirestoreService.shared.fetchKBOSchedule(teamID: teamID)
        } catch {
            Logger.api.warning("KBO syncPending 실패 (\(folder.name)): \(error.localizedDescription)")
            return
        }
        guard !latestSchedule.isEmpty else { return }

        let scheduleMap = Dictionary(uniqueKeysWithValues: latestSchedule.map { ($0.id, $0) })
        let oneDayAgo = now.addingTimeInterval(-24 * 3600)
        var hasChanges = false

        for match in pendingMatches {
            guard let eventID = match.externalEventID else { continue }

            if let updated = scheduleMap[eventID] {
                if match.location == nil || match.location?.isEmpty == true,
                   let stadium = updated.importedVenueSearchQuery {
                    match.location = stadium
                    hasChanges = true
                }
                if updated.isCompleted {
                    match.matchStatus   = .completed
                    match.myTeamScore   = updated.myScore ?? match.myTeamScore
                    match.opponentScore = updated.opponentScore ?? match.opponentScore
                    let my = match.myTeamScore, opp = match.opponentScore
                    match.matchResult   = my > opp ? .win : (my < opp ? .loss : .draw)
                    hasChanges = true
                    Logger.data.info("KBO 자동 완료 처리: \(eventID) (\(match.opponentTeam))")
                } else if updated.isLive {
                    match.matchStatus = .live
                    if let s = updated.myScore       { match.myTeamScore   = s }
                    if let s = updated.opponentScore { match.opponentScore = s }
                    hasChanges = true
                } else if let matchDate = match.date, matchDate < oneDayAgo,
                          (match.photoPaths ?? []).isEmpty, match.photosData == nil {
                    modelContext.delete(match)
                    hasChanges = true
                    Logger.data.info("KBO NS 좀비 티켓 삭제: \(eventID) (\(match.opponentTeam))")
                }
            } else if let matchDate = match.date, matchDate < oneDayAgo,
                      (match.photoPaths ?? []).isEmpty, match.photosData == nil {
                modelContext.delete(match)
                hasChanges = true
                Logger.data.info("KBO PP/CANC 티켓 삭제: \(eventID) (\(match.opponentTeam))")
            }
        }

        if hasChanges {
            try? modelContext.save()
            Logger.data.info("KBO 자동 동기화 완료: \(folder.name)")
        }
    }

    // MARK: - 동적 툴바

    @ToolbarContentBuilder
    private var dynamicToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            switch selectedTab {
            case .matches:
                if folder.sportType == .other {
                    Button {
                        showingAddMatchSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                } else {
                    Menu {
                        Button {
                            showingAddMatchSheet = true
                        } label: {
                            Label(String(localized: "sports.menu.manualEntry", defaultValue: "직접 입력"), systemImage: "square.and.pencil")
                        }
                        Button {
                            showingMatchSheet = true
                        } label: {
                            Label(String(localized: "sports.menu.importSchedule", defaultValue: "경기 불러오기"), systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }

            case .team:
                Button {
                    showingFolderEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }

            case .stats:
                EmptyView()
            }
        }
    }

}

// MARK: - 경기 카드 (SportsMatchesTab에서도 사용)

struct SportsGameCard: View {
    let match: SportsModel

    @Environment(\.colorScheme) private var colorScheme

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.autoupdatingCurrent
        fmt.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return fmt
    }()

    private var sportType: SportType {
        match.folder?.sportType ?? .other
    }

    private var team1Name: String { match.team1Display }
    private var team2Name: String { match.team2Display }
    private var team1NameUI: String {
        KBOTeamLogoAsset.uiDisplayName(forTeamName: team1Name, leagueCode: match.folder?.leagueCode)
    }
    private var team2NameUI: String {
        KBOTeamLogoAsset.uiDisplayName(forTeamName: team2Name, leagueCode: match.folder?.leagueCode)
    }

    private var team1Gradient: [Color] {
        match.folder?.gradientColors ?? [.gray, .gray.opacity(0.7)]
    }

    private var team1Data: ESPNTeam? {
        ESPNTeamsLoader.team(name: match.team1Display, leagueCode: match.folder?.leagueCode)
    }
    private var team2Data: ESPNTeam? {
        ESPNTeamsLoader.team(name: match.opponentTeam, leagueCode: match.folder?.leagueCode)
    }

    private var isKBO: Bool { match.folder?.leagueCode == "KBO" }

    /// location이 비어 있으면 KBO 정적 매핑으로 구장명 유도 (기존 저장 경기 소급 적용)
    private var displayLocation: String? {
        if let loc = match.location, !loc.trimmingCharacters(in: .whitespaces).isEmpty { return loc }
        guard isKBO else { return nil }
        let teamName = match.isHomeGame
            ? (match.folder?.name ?? "")
            : match.opponentTeam
        return KBOTeamLogoAsset.homeStadium(forTeamName: teamName)
    }

    private var isActive: Bool {
        match.matchStatus != .completed
    }

    private var isNoOpponentMode: Bool {
        match.folder?.sportType == .other && !(match.folder?.matchHasOpponent ?? true)
    }

    /// 완료 카드: 점수가 있으면 VS 생략 (0–0 무는 점수로 간주)
    private var completedCardHasScores: Bool {
        match.myTeamScore != 0
            || match.opponentScore != 0
            || match.matchResult == .draw
    }

    /// D-day 계산 (경기 예정일 때)
    private var dDayText: String? {
        guard match.matchStatus == .upcoming,
              let date = match.date else { return nil }
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        let startOfGameDay = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startOfToday, to: startOfGameDay).day ?? 0
        if days > 0 {
            return String(format: String(localized: "sports.card.dDay.countdown", defaultValue: "D-%lld"), locale: .autoupdatingCurrent, Int64(days))
        }
        if days == 0 { return String(localized: "sports.card.dDay.today", defaultValue: "D-Day") }
        return nil
    }

    var body: some View {
        if isNoOpponentMode {
            noOpponentCard
        } else if isActive {
            activeCard
        } else {
            completedCard
        }
    }

    // MARK: - 상대팀 없는 기타 카드
    private var noOpponentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(sportType.displayName, systemImage: sportType.iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                let status = match.matchStatus
                Text(status.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(status.color.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(match.title)
                .font(.headline)
                .lineLimit(2)

            HStack {
                if let date = match.date {
                    Label(Self.dateFormatter.string(from: date), systemImage: "calendar")
                }
                Spacer()
                if let location = displayLocation {
                    Label(location, systemImage: "mappin")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .groupedCardOutline(cornerRadius: 16)
    }

    // MARK: - 예정/진행중 카드
    private var activeCard: some View {
        VStack(spacing: 0) {
            // 진행중: 상단 LIVE 바
            if match.matchStatus == .live {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .symbolEffect(.pulse)
                    Text(String(localized: "sports.card.liveBadge", defaultValue: "LIVE"))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(MatchStatus.live.color)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 16, topTrailingRadius: 16
                ))
            }

            VStack(spacing: 12) {
                HStack {
                    if let dDay = dDayText {
                        Text(dDay)
                            .font(.caption.bold())
                            .foregroundStyle(match.matchStatus.color)
                    }

                    Label(sportType.displayName, systemImage: sportType.iconName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if match.matchStatus == .upcoming {
                        Text(match.matchStatus.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(match.matchStatus.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(match.matchStatus.color.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                HStack {
                    TeamLogoLabel(
                        name: team1NameUI,
                        logoUrl: match.hasFavoriteTeam ? match.folder?.teamLogoUrl : team1Data?.logo_url,
                        gradientColors: match.hasFavoriteTeam ? team1Gradient : (team1Data?.gradientColors ?? [.gray, .gray.opacity(0.7)]),
                        assetName: isKBO ? KBOTeamLogoAsset.imageName(forTeamName: team1Name) : nil
                    )

                    Text(String(localized: "sports.card.vs", defaultValue: "VS"))
                        .font(.title3.bold())
                        .foregroundStyle(match.matchStatus.color.opacity(0.6))

                    TeamLogoLabel(
                        name: team2NameUI,
                        logoUrl: team2Data?.logo_url,
                        gradientColors: team2Data?.gradientColors ?? [.gray, .gray.opacity(0.7)],
                        assetName: isKBO ? KBOTeamLogoAsset.imageName(forTeamName: team2Name) : nil
                    )
                }

                HStack(alignment: .top, spacing: 8) {
                    if let date = match.date {
                        Label(Self.dateFormatter.string(from: date), systemImage: "calendar")
                    }
                    Spacer(minLength: 8)
                    if let location = displayLocation {
                        Label {
                            Text(location)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                                .minimumScaleFactor(0.82)
                        } icon: {
                            Image(systemName: "mappin")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            match.matchStatus.color.opacity(0.08),
                            Color(uiColor: .secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    match.matchStatus.color.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 5])
                )
        )
    }

    // MARK: - 완료 카드
    private var completedCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label(sportType.displayName, systemImage: sportType.iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(match.matchResult.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(match.matchResult.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(match.matchResult.color.opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(spacing: 12) {
                HStack {
                    TeamLogoLabel(
                        name: team1NameUI,
                        logoUrl: match.hasFavoriteTeam ? match.folder?.teamLogoUrl : team1Data?.logo_url,
                        gradientColors: match.hasFavoriteTeam ? team1Gradient : (team1Data?.gradientColors ?? [.gray, .gray.opacity(0.7)]),
                        assetName: isKBO ? KBOTeamLogoAsset.imageName(forTeamName: team1Name) : nil
                    )

                    VStack(spacing: 6) {
                        if !completedCardHasScores {
                            Text(String(localized: "sports.card.vs", defaultValue: "VS"))
                                .font(.title3.bold())
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            Text(verbatim: "\(match.myTeamScore)")
                                .font(.title.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(match.matchResult == .win ? match.matchResult.color : .primary)
                            Text(":")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.tertiary)
                            Text(verbatim: "\(match.opponentScore)")
                                .font(.title.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(match.matchResult == .loss ? match.matchResult.color : .primary)
                        }
                    }
                    .frame(minWidth: completedCardHasScores ? 56 : 72)

                    TeamLogoLabel(
                        name: team2NameUI,
                        logoUrl: team2Data?.logo_url,
                        gradientColors: team2Data?.gradientColors ?? [.gray, .gray.opacity(0.7)],
                        assetName: isKBO ? KBOTeamLogoAsset.imageName(forTeamName: team2Name) : nil
                    )
                }

                HStack(alignment: .top, spacing: 8) {
                    if let date = match.date {
                        Label(Self.dateFormatter.string(from: date), systemImage: "calendar")
                    }
                    Spacer(minLength: 8)
                    if let location = displayLocation {
                        Label {
                            Text(location)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                                .minimumScaleFactor(0.82)
                        } icon: {
                            Image(systemName: "mappin")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .groupedCardOutline(cornerRadius: 16)
    }
}

// MARK: - 팀 로고 + 이름 셀 (SportsMatchesTab에서도 사용)

struct TeamLogoLabel: View {
    let name: String
    let logoUrl: String?
    let gradientColors: [Color]
    /// Asset catalog 이미지 이름. 있으면 URL 로딩보다 우선합니다.
    var assetName: String? = nil

    private var showLogoBox: Bool {
        assetName != nil || (logoUrl != nil && !(logoUrl?.isEmpty ?? true))
    }

    var body: some View {
        VStack(spacing: 6) {
            if showLogoBox {
                ZStack {
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    if let assetName {
                        Image(assetName)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    } else if let url = logoUrl, !url.isEmpty {
                        KFImage.url(URL(string: url))
                            .placeholder { ProgressView().tint(.white) }
                            .onFailureView {
                                Image(systemName: "photo")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    }
                }
                .frame(width: 36, height: 36)
            }
            Text(name)
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.68)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SportsView(folder: {
            let folder = SportsFanFolder(name: "LG 트윈스", sportType: .baseball)

            let live = SportsModel(
                title: "LG vs KT",
                opponentTeam: "KT 위즈",
                matchStatus: .live,
                date: Date(),
                location: "잠실 야구장",
                orderIndex: 0
            )
            live.folder = folder

            let upcoming = SportsModel(
                title: "LG vs SSG",
                opponentTeam: "SSG 랜더스",
                matchStatus: .upcoming,
                date: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
                location: "잠실 야구장",
                orderIndex: 1
            )
            upcoming.folder = folder

            let matches: [(String, Int, Int, MatchResult, Int)] = [
                ("두산 베어스", 5, 2, .win, 2),
                ("SSG 랜더스", 3, 1, .win, 3),
                ("한화 이글스", 7, 4, .win, 4),
                ("NC 다이노스", 2, 5, .loss, 5),
                ("키움 히어로즈", 4, 4, .draw, 6),
                ("KT 위즈", 6, 3, .win, 7),
                ("삼성 라이온즈", 1, 3, .loss, 8),
                ("KIA 타이거즈", 8, 2, .win, 9),
                ("롯데 자이언츠", 3, 6, .loss, 10),
                ("두산 베어스", 4, 1, .win, 11),
            ]

            for (opponent, my, opp, result, idx) in matches {
                let m = SportsModel(
                    title: "LG vs \(opponent)",
                    opponentTeam: opponent,
                    myTeamScore: my,
                    opponentScore: opp,
                    matchResult: result,
                    matchStatus: .completed,
                    date: Calendar.current.date(byAdding: .day, value: -idx, to: Date()),
                    location: "잠실 야구장",
                    orderIndex: idx
                )
                m.folder = folder
                folder.matches.append(m)
            }

            folder.matches.append(contentsOf: [live, upcoming])
            return folder
        }())
    }
    .modelContainer(SportsPreviewSampleData.container)
}
