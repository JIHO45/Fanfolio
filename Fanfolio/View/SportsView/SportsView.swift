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

struct SportsView: View {
    let folder: SportsFanFolder
    
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddMatchSheet = false
    @State private var showingFolderEditSheet = false
    @State private var showingMatchSheet = false
    @State private var matchToDelete: SportsModel?
    @State private var showingDeleteMatchAlert = false
    
    // MARK: - 실시간 스코어 상태
    @State private var liveFixtures: [LiveFixture] = []
    @State private var liveLoadError: String? = nil
    @State private var isLoadingLive = false

    // MARK: - 즐겨찾기 상태 (배너 뱃지용)
    @State private var favorites = FavoritePlayersManager.shared
    
    /// 경기 예정만 (가까운 날짜가 위). 진행 중은 상단 실시간 스코어로만 표시해 중복 카드를 없앰.
    private var activeMatches: [SportsModel] {
        folder.matches
            .filter { $0.matchStatus == .upcoming }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    
    /// 완료된 경기 (최근 경기가 위에)
    private var completedMatches: [SportsModel] {
        folder.matches
            .filter { $0.matchStatus == .completed }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// 스코어 보드에 올릴 경기만 (종료는 아래 직관 기록에서 보면 되므로 제외)
    private var scoreboardRelevantFixtures: [LiveFixture] {
        liveFixtures.filter { !$0.status.isFinished }
    }

    // MARK: - 통계 계산
    private var wins: Int { completedMatches.filter { $0.matchResult == .win }.count }
    private var losses: Int { completedMatches.filter { $0.matchResult == .loss }.count }
    private var draws: Int { completedMatches.filter { $0.matchResult == .draw }.count }
    private var totalCompleted: Int { completedMatches.count }
    
    private var winRate: Double {
        guard totalCompleted > 0 else { return 0 }
        return Double(wins) / Double(totalCompleted) * 100
    }
    
    /// 현재 연승/연패 계산 (최근 경기부터)
    private var currentStreak: (count: Int, type: MatchResult)? {
        let sorted = completedMatches.sorted {
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
        guard let first = sorted.first,
              first.matchResult != .draw else { return nil }
        
        let streakType = first.matchResult
        var count = 0
        for match in sorted {
            if match.matchResult == streakType {
                count += 1
            } else {
                break
            }
        }
        return count >= 2 ? (count, streakType) : nil
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // 팀 정보 배너 (기타 카테고리 제외)
                if folder.sportType != .other {
                    NavigationLink(destination: TeamInfoDetailView(folder: folder)) {
                        teamInfoBanner
                    }
                    .buttonStyle(.plain)
                }

                // 전적 통계 배너 (탭하면 상세 통계)
                NavigationLink(destination: FanStatsView(folder: folder)) {
                    statsHeader
                }
                .buttonStyle(.plain)

                // 실시간 스코어보드 섹션 (기타 카테고리 제외) — 진행 중·예정만 (종료 경기는 미표시)
                if folder.sportType != .other {
                    if !scoreboardRelevantFixtures.isEmpty || isLoadingLive {
                        liveScoreboardSection
                    }

                    // 라이브 스코어 라우팅·키 필요 여부는 `ESPNPlayerService`와 동일 기준(SSOT)
                    let leagueCode = folder.leagueCode ?? ""
                    if ESPNPlayerService.shared.shouldPromptForMissingAPISportsKey(leagueCode: leagueCode)
                        && scoreboardRelevantFixtures.isEmpty && !isLoadingLive {
                        liveScoreAPIKeyPrompt
                    }
                }

                // 에러 배너
                if let error = liveLoadError {
                    errorBanner(message: error)
                }

                // 예정 경기 (진행 중은 실시간 스코어 전용)
                if !activeMatches.isEmpty {
                    sectionHeader(
                        title: String(localized: "sports.section.upcomingMatches", defaultValue: "예정"),
                        iconName: "clock",
                        count: activeMatches.count
                    )

                    ForEach(activeMatches) { match in
                        matchRow(match: match)
                    }
                }

                // 완료된 경기
                if !completedMatches.isEmpty {
                    sectionHeader(
                        title: "완료",
                        iconName: "checkmark.circle",
                        count: completedMatches.count
                    )

                    ForEach(completedMatches) { match in
                        matchRow(match: match)
                    }
                }

                // 경기 기록이 없을 때 안내
                if folder.matches.isEmpty && scoreboardRelevantFixtures.isEmpty && !isLoadingLive {
                    ContentUnavailableView(
                        "경기 기록이 없습니다",
                        systemImage: folder.sportType.iconName,
                        description: Text("+ 버튼을 눌러 첫 경기를 기록해보세요!")
                    )
                    .padding(.top, 16)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {
            async let live: Void = fetchLiveScores(showLoadingUI: false)
            async let sync: Void = syncPendingMatches()
            _ = await (live, sync)
        }
        .task(id: "\(folder.sportType.rawValue)\u{1f}\(folder.leagueCode ?? "")\u{1f}\(folder.matches.count)") {
            await syncPendingMatches()
        }
        .task(id: "\(folder.sportType.rawValue)\u{1f}\(folder.leagueCode ?? "")") {
            guard folder.sportType != .other else { return }
            await fetchLiveScores()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch is CancellationError {
                    Logger.api.info("라이브 스코어 폴링: 취소로 정상 종료")
                    break
                } catch {
                    Logger.api.error("라이브 스코어 폴링 sleep 오류(다음 주기 재시도): \(error.localizedDescription, privacy: .public)")
                    continue
                }

                await fetchLiveScores(showLoadingUI: false)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingFolderEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }

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
                            Label("직접 입력", systemImage: "square.and.pencil")
                        }

                        Button {
                            showingMatchSheet = true
                        } label: {
                            Label("경기 불러오기", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddMatchSheet) {
            AddSportsMatchView(
                folder: folder,
                nextOrderIndex: folder.matches.count
            )
        }
        .sheet(isPresented: $showingFolderEditSheet) {
            AddFolderView(folder: folder)
        }
        .sheet(isPresented: $showingMatchSheet) {
            MatchListView(folder: folder)
        }
    }
    
    // MARK: - 실시간 스코어 로드
    /// - `showLoadingUI`: 첫 로드 등에만 true. 30초 폴링·당겨서 새로고침은 false로 헤더·레이아웃이 튀지 않게 함.
    // 라우팅 원칙:
    //   supportsLiveScoreboard 리그(NFL·NBA·MLB·주요 축구 등) → ESPN, API 키 불필요
    //   그 외(예: KBO) → API-Sports (100회/일 제한)

    private func fetchLiveScores(showLoadingUI: Bool = true) async {
        guard NetworkMonitor.shared.isConnected else {
            liveLoadError = String(localized: "network.error.noConnection", defaultValue: "인터넷 연결이 없습니다. 연결 후 다시 시도해주세요.")
            return
        }
        if showLoadingUI {
            isLoadingLive = true
        }
        liveLoadError = nil

        defer {
            if showLoadingUI {
                isLoadingLive = false
            }
        }

        let leagueCode = folder.leagueCode ?? ""

        // ESPN 스코어보드 지원 리그 → API 키 불필요
        if ESPNPlayerService.shared.supportsLiveScoreboard(leagueCode) {
            do {
                var fixtures = try await ESPNPlayerService.shared.fetchLiveScoreboard(leagueCode: leagueCode)
                // 스코어보드 API는 리그 전체 경기를 주므로, 이 폴더에서 고른 팀이 출전한 경기만 표시
                if let espnTeam = ESPNTeamsLoader.team(name: folder.name, leagueCode: folder.leagueCode),
                   !espnTeam.id.isESPNFakeID,
                   let myTeamID = Int(espnTeam.id) {
                    fixtures = fixtures.filter { $0.homeTeam.id == myTeamID || $0.awayTeam.id == myTeamID }
                }
                liveFixtures = fixtures
            } catch {
                liveLoadError = error.localizedDescription
                liveFixtures  = []
            }
            return
        }

        // 비ESPN 리그 → API-Sports (100회/일 제한). 키 없음 판단은 SSOT 메서드와 동일.
        guard !ESPNPlayerService.shared.shouldPromptForMissingAPISportsKey(leagueCode: leagueCode) else { return }

        if APIRateLimiter.shared.isLimitReached {
            liveLoadError = String(localized: "api.error.dailyLimitExceeded", defaultValue: "오늘 API 호출 한도(100회)를 초과했습니다. 내일 다시 시도해주세요.")
            return
        }

        do {
            let sport    = folder.sportType
            let leagueID = sport.apiSportsLeagueIDs[leagueCode] ?? 0
            let teamID   = folder.apiSportsTeamID ?? 0
            guard teamID > 0 else { return }

            liveFixtures = try await APISportsService.shared.fetchSoccerGames(leagueID: leagueID, teamID: teamID)
        } catch let error as APISportsError {
            liveLoadError = error.errorDescription
            liveFixtures = []
        } catch {
            liveLoadError = String(localized: "error.load.generic", defaultValue: "데이터를 불러오는 중 오류가 발생했습니다.")
            liveFixtures = []
        }
    }

    // MARK: - 예정 경기 자동 동기화

    /// 날짜가 지난 예정·진행중 티켓을 ESPN 최신 데이터로 조용히 업데이트합니다.
    /// - ESPN 지원 리그(NFL·NBA·MLB 등)만 처리 (KBO 등 API-Sports 리그는 미지원)
    /// - 이미 경기 시작 시간이 된 티켓만 조회해 불필요한 API 호출을 방지합니다.
    private func syncPendingMatches() async {
        let leagueCode = folder.leagueCode ?? ""
        guard ESPNPlayerService.shared.supportsLiveScoreboard(leagueCode) else { return }

        // 완료되지 않았고, ESPN 이벤트 ID가 있으며, 경기 시작 시간이 된 것만 대상
        let now = Date()
        let pendingMatches = folder.matches.filter {
            $0.matchStatus != .completed
            && $0.externalEventID?.hasPrefix("espn:") == true
            && ($0.date.map { $0 <= now.addingTimeInterval(3600) } ?? false)
        }
        guard !pendingMatches.isEmpty else { return }

        // ESPN 팀 ID 조회
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

        // parseESPNScheduleEvent에서 취소·연기 경기는 nil을 반환하므로 latestSchedule에 없음
        // → 날짜가 7일 이상 지났는데 스케줄에 없으면 취소/연기된 좀비 티켓으로 판단해 삭제
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let scheduleIDs  = Set(latestSchedule.map { $0.id })

        var hasChanges = false
        for match in pendingMatches {
            guard let eventID = match.externalEventID else { continue }

            // 좀비 티켓 제거: 스케줄에 없고 날짜가 7일 이상 지난 경우
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

    // MARK: - 실시간 스코어보드 UI 섹션
    
    private var liveScoreboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isLoadingLive {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("실시간 스코어 로딩 중...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // 헤더는 실제 진행 중 경기가 있을 때만 LIVE 스타일 (그 외는 일반 스코어)
                    if scoreboardRelevantFixtures.contains(where: \.isLive) {
                        LiveIndicator()
                        Text("실시간 스코어")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "sportscourt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("경기 스코어")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    Text("· 아래로 당겨서 새로고침")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            
            if !scoreboardRelevantFixtures.isEmpty {
                LiveScoreboardSection(fixtures: scoreboardRelevantFixtures, sportType: folder.sportType)
            }
        }
        .padding(.top, 4)
    }
    
    private var liveScoreAPIKeyPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("실시간 스코어 미설정")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text("APIKeys.xcconfig에 API_SPORTS_KEY를 설정하면 실시간 스코어를 이용할 수 있습니다. example 파일을 복사해 사용하세요.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            // API 사용량 표시 (키 설정 시)
            let limiter = APIRateLimiter.shared
            if limiter.callCount > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(limiter.remainingCalls)회 남음")
                        .font(.caption2.bold())
                        .foregroundStyle(limiter.remainingCalls < 20 ? .orange : .secondary)
                    Text("오늘 API 잔여")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.08))
        )
    }
    
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - 럭키팬 칭호 (String Catalog)
    private var luckyTitle: (emoji: String, title: String) {
        switch winRate {
        case 80...:
            return ("🍀", String(localized: "sports.lucky.legend", defaultValue: "전설의 럭키팬"))
        case 65..<80:
            return ("⭐️", String(localized: "sports.lucky.star", defaultValue: "행운의 팬"))
        case 50..<65:
            return ("👍", String(localized: "sports.lucky.blessed", defaultValue: "복 받은 팬"))
        case 40..<50:
            return ("😅", String(localized: "sports.lucky.grit", defaultValue: "분투의 팬"))
        case 25..<40:
            return ("😢", String(localized: "sports.lucky.struggle", defaultValue: "시련의 팬"))
        default:
            return ("💪", String(localized: "sports.lucky.resilient", defaultValue: "불굴의 팬"))
        }
    }

    // MARK: - 전적 통계 배너 (승률 링 + 큰 승/패/무)
    private var statsHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                FanWinRateRingView(
                    winRatePercent: winRate,
                    totalGames: totalCompleted
                )
                .frame(width: 96, height: 96)

                VStack {
                    HStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Text(luckyTitle.emoji)
                            Text(luckyTitle.title)
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        }
                                 
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Text(String(localized: "common.action.viewDetails", defaultValue: "자세히 보기"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    VStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            bigStatDigit(
                                count: wins,
                                label: String(localized: "sports.stats.label.win", defaultValue: "승"),
                                color: MatchResult.win.color
                            )
                            bigStatDigit(
                                count: losses,
                                label: String(localized: "sports.stats.label.loss", defaultValue: "패"),
                                color: MatchResult.loss.color
                            )
                            bigStatDigit(
                                count: draws,
                                label: String(localized: "sports.stats.label.draw", defaultValue: "무"),
                                color: Color.secondary
                            )
                            
                            Spacer()
                            
                            if let streak = currentStreak {
                                HStack(spacing: 4) {
                                    Text(streak.type == .win ? "🔥" : "💧")
                                    let streakFmt = streak.type == .win
                                    ? String(localized: "sports.streak.wins", defaultValue: "%lld연승")
                                    : String(localized: "sports.streak.losses", defaultValue: "%lld연패")
                                    Text(String(format: streakFmt, locale: .autoupdatingCurrent, Int64(streak.count)))
                                        .font(.caption2.bold())
                                        .foregroundStyle(streak.type.color)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(streak.type.color.opacity(0.12))
                                .clipShape(Capsule())
                            }

                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minHeight: 96)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func bigStatDigit(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(label)")
    }

    // MARK: - 팀 정보 배너 카드 (탭하면 TeamInfoDetailView로 이동)

    private var teamInfoBanner: some View {
        let favCount = favorites.favoriteCount(inFolder: folder.folderID.uuidString)
        let gradients = folder.gradientColors

        return HStack(spacing: 14) {
            // 팀 로고
            if let url = folder.teamLogoUrl, !url.isEmpty {
                ZStack {
                    LinearGradient(colors: gradients, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    KFImage.url(URL(string: url))
                        .placeholder { ProgressView().tint(.white) }
                        .onFailureView {
                            Image(systemName: "person.3.fill")
                                .font(.caption2).foregroundStyle(.white.opacity(0.8))
                        }
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                }
                .frame(width: 44, height: 44)
            } else {
                ZStack {
                    LinearGradient(colors: gradients, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Image(systemName: "person.3.fill")
                        .font(.subheadline).foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
            }

            // 텍스트
            VStack(alignment: .leading, spacing: 4) {
                Text("팀 정보")
                    .font(.subheadline.bold())
                HStack(spacing: 8) {
                    Label("팀 선수단", systemImage: "person.3.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if favCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.red)
                            Text("최애 \(favCount)명")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Text("자세히 보기")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: - 섹션 헤더
    private func sectionHeader(title: String, iconName: String, count: Int, hideCount: Bool = false) -> some View {
        HStack {
            Label(title, systemImage: iconName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            if !hideCount {
                Text("\(count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            
            Spacer()
        }
        .padding(.top, 8)
    }
    
    // MARK: - 경기 행 (네비게이션 + 삭제)
    private func matchRow(match: SportsModel) -> some View {
        NavigationLink(destination: SportsDetailView(match: match)) {
            SportsGameCard(match: match)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                matchToDelete = match
                showingDeleteMatchAlert = true
            } label: {
                Label(String(localized: "common.action.delete", defaultValue: "삭제"), systemImage: "trash")
            }
        }
        .alert(
            Text("경기 기록 삭제"),
            isPresented: $showingDeleteMatchAlert
        ) {
            Button(String(localized: "common.action.cancel", defaultValue: "취소"), role: .cancel) {
                matchToDelete = nil
            }
            Button(String(localized: "common.action.delete", defaultValue: "삭제"), role: .destructive) {
                if let match = matchToDelete {
                    TicketImageStore.delete(paths: match.savedTicketPaths)
                    ArchivePhotoStore.delete(paths: match.photoPaths ?? [])
                    withAnimation {
                        modelContext.delete(match)
                    }
                    matchToDelete = nil
                }
            }
        } message: {
            if let match = matchToDelete {
                Text("‘\(match.title)’ 기록을 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.")
            }
        }
    }
}

// MARK: - 승률 링 (팬 허브 전적 카드)
private struct FanWinRateRingView: View {
    let winRatePercent: Double
    let totalGames: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(winRatePercent / 100, 0), 1)))
                .stroke(
                    Color.green.gradient,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int(winRatePercent))%")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(winRatePercent >= 50 ? Color.green : (winRatePercent > 0 ? Color.orange : Color.secondary))
                Text(String(localized: "sports.stats.winRateCaption", defaultValue: "승률"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(gamesPlayedLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(winRateAccessibilityLabel)
    }

    private var gamesPlayedLabel: String {
        let fmt = String(localized: "sports.stats.gamesPlayedFormat", defaultValue: "%lld경기")
        return String(format: fmt, locale: .autoupdatingCurrent, Int64(totalGames))
    }

    private var winRateAccessibilityLabel: String {
        let winRateWord = String(localized: "sports.stats.winRateCaption", defaultValue: "승률")
        return "\(winRateWord) \(Int(winRatePercent))%, \(gamesPlayedLabel)"
    }
}

// MARK: - 팀 로고 + 이름 셀
private struct TeamLogoLabel: View {
    let name: String
    let logoUrl: String?
    let gradientColors: [Color]
    
    var body: some View {
        VStack(spacing: 6) {
            if let url = logoUrl, !url.isEmpty {
                ZStack {
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
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

// MARK: - 경기 카드
private struct SportsGameCard: View {
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
    
    private var team1Gradient: [Color] {
        match.folder?.gradientColors ?? [.gray, .gray.opacity(0.7)]
    }
    
    private var team1Data: ESPNTeam? {
        ESPNTeamsLoader.team(name: match.team1Display, leagueCode: match.folder?.leagueCode)
    }
    private var team2Data: ESPNTeam? {
        ESPNTeamsLoader.team(name: match.opponentTeam, leagueCode: match.folder?.leagueCode)
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
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
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
                if let location = match.location {
                    Label(location, systemImage: "mappin")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
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
                // 상단: D-day / 종목 + 상태 배지
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
                
                // 팀 VS 팀 (로고 + 이름)
                HStack {
                    TeamLogoLabel(
                        name: team1Name,
                        logoUrl: match.hasFavoriteTeam ? match.folder?.teamLogoUrl : team1Data?.logo_url,
                        gradientColors: match.hasFavoriteTeam ? team1Gradient : (team1Data?.gradientColors ?? [.gray, .gray.opacity(0.7)])
                    )
                    
                    Text(String(localized: "sports.card.vs", defaultValue: "VS"))
                        .font(.title3.bold())
                        .foregroundStyle(match.matchStatus.color.opacity(0.6))
                    
                    TeamLogoLabel(
                        name: team2Name,
                        logoUrl: team2Data?.logo_url,
                        gradientColors: team2Data?.gradientColors ?? [.gray, .gray.opacity(0.7)]
                    )
                }
                
                // 날짜 + 장소
                HStack(alignment: .top, spacing: 8) {
                    if let date = match.date {
                        Label(Self.dateFormatter.string(from: date), systemImage: "calendar")
                    }
                    Spacer(minLength: 8)
                    if let location = match.location {
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
                        name: team1Name,
                        logoUrl: match.hasFavoriteTeam ? match.folder?.teamLogoUrl : team1Data?.logo_url,
                        gradientColors: match.hasFavoriteTeam ? team1Gradient : (team1Data?.gradientColors ?? [.gray, .gray.opacity(0.7)])
                    )

                    VStack(spacing: 6) {
                        if !completedCardHasScores {
                            Text("VS")
                                .font(.title3.bold())
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            Text("\(match.myTeamScore)")
                                .font(.title.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(match.matchResult == .win ? match.matchResult.color : .primary)
                            Text(":")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.tertiary)
                            Text("\(match.opponentScore)")
                                .font(.title.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(match.matchResult == .loss ? match.matchResult.color : .primary)
                        }
                    }
                    .frame(minWidth: completedCardHasScores ? 56 : 72)

                    TeamLogoLabel(
                        name: team2Name,
                        logoUrl: team2Data?.logo_url,
                        gradientColors: team2Data?.gradientColors ?? [.gray, .gray.opacity(0.7)]
                    )
                }

                HStack(alignment: .top, spacing: 8) {
                    if let date = match.date {
                        Label(Self.dateFormatter.string(from: date), systemImage: "calendar")
                    }
                    Spacer(minLength: 8)
                    if let location = match.location {
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
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}


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
            
            // 완료된 경기들 — 통계 확인용
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
