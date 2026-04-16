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

    /// syncKBOPendingMatches / syncPendingMatches 과호출 방지 (CloudKit 배치 업데이트 대응)
    /// 마지막 동기화 시각을 기록해 2분 이내 중복 실행을 차단합니다.
    @State private var lastSyncDate: Date = .distantPast
    private let syncCooldown: TimeInterval = 120

    /// KBO 라이브 시 Firestore 폴링 간격 — `functions/index.js` 의 `fetchKboGameTime`(약 5분)과 맞출 것
    private static let kboLivePollIntervalSeconds: Double = 300

    /// 라이브 스코어 폴링 Task 핸들.
    /// scenePhase 변화·뷰 소멸 시 명시적으로 cancel()해 수명주기를 직접 제어합니다.
    @State private var pollingTask: Task<Void, Never>?
    
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

    /// 스코어 보드에 올릴 경기만 (종료·예정 중 이미 '예정 섹션'에 표시 중인 경기는 제외).
    /// - 완료 경기: 아래 직관 기록에서 확인하므로 제외
    /// - 예정(NS) 경기 중 folder.matches에 이미 upcoming으로 추적 중인 것: 예정 섹션과 중복 방지를 위해 제외
    /// - 예정이지만 아직 임포트되지 않은 경기(다음 예정 미리보기 등): 스코어보드에 유지
    private var scoreboardRelevantFixtures: [LiveFixture] {
        let trackedUpcomingIDs: Set<String> = Set(
            folder.matches
                .filter { $0.matchStatus == .upcoming }
                .compactMap { $0.externalEventID }
        )
        return liveFixtures.filter { fixture in
            guard !fixture.status.isFinished else { return false }
            if fixture.isUpcoming {
                let espnKey = "espn:\(fixture.id)"
                let kboKey  = "firestore-kbo:\(fixture.id)"
                if trackedUpcomingIDs.contains(espnKey) || trackedUpcomingIDs.contains(kboKey) {
                    return false
                }
            }
            return true
        }
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
                        title: String(localized: "common.section.completed", defaultValue: "완료"),
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
                        String(localized: "sports.list.emptyTitle", defaultValue: "경기 기록이 없습니다"),
                        systemImage: folder.sportType.iconName,
                        description: Text(String(localized: "sports.list.emptyDescription", defaultValue: "+ 버튼을 눌러 첫 경기를 기록해보세요!"))
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
            async let kboSync: Void = syncKBOPendingMatches()
            _ = await (live, sync, kboSync)
        }
        .task(id: "\(folder.sportType.rawValue)\u{1f}\(folder.leagueCode ?? "")\u{1f}\(folder.matches.count)") {
            // CloudKit 배치 동기화로 count가 연속으로 바뀌어도 syncCooldown 이내 중복 실행 차단
            guard Date().timeIntervalSince(lastSyncDate) >= syncCooldown else { return }
            lastSyncDate = Date()
            await syncPendingMatches()
            await syncKBOPendingMatches()
        }
        // 뷰가 처음 나타날 때 폴링 시작 (.onChange는 값이 변할 때만 발동하므로,
        // 초기 등장 시 scenePhase가 이미 .active인 경우를 .onAppear로 별도 처리)
        .onAppear {
            Logger.api.info("‼️ [DEBUG] onAppear 호출됨")
            guard folder.sportType != .other else {
                Logger.api.info("‼️ [DEBUG] sportType이 .other라서 종료됨")
                return
            }
            startPolling()
        }
        // 포그라운드 복귀 시 폴링 재시작.
        // @Environment(\.scenePhase)는 NavigationStack 중첩 시 전달이 불안정할 수 있으므로
        // UIApplication 알림을 직접 수신해 더 확실하게 처리.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Logger.api.info("‼️ [DEBUG] didBecomeActive → 폴링 재시작 경로 진입")
            guard folder.sportType != .other else {
                Logger.api.info("‼️ [DEBUG] didBecomeActive: sportType이 .other라서 종료됨")
                return
            }
            startPolling()
        }
        // 백그라운드 진입 시 폴링 중단.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            stopPolling()
        }
        // 뷰 소멸 시 안전장치 (NavigationStack pop 등)
        .onDisappear {
            stopPolling()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            // bottomBar는 trailing 전용 placement가 없어, 한 아이템 안에서 가로 전체 + trailing 정렬로 오른쪽 고정
            ToolbarItem(placement: .bottomBar) {
                HStack(spacing: 16) {
                    Spacer(minLength: 0)
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
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
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

    // MARK: - 폴링 수명주기 관리

    /// 라이브 스코어 폴링을 시작합니다.
    /// 기존에 실행 중인 폴링이 있으면 먼저 취소합니다.
    private func startPolling() {
        Logger.api.info("‼️ [DEBUG] startPolling 함수 진입함")

        pollingTask?.cancel()
        pollingTask = Task {
            Logger.api.info("‼️ [DEBUG] Task 시작됨")

            await fetchLiveScores()

            Logger.api.info("‼️ [DEBUG] fetchLiveScores 완료됨. 리그코드: \(folder.leagueCode ?? "nil")")

            guard !Task.isCancelled else { return }

            if (folder.leagueCode ?? "") == "KBO" {
                if let teamID = folder.apiSportsTeamID, teamID > 0 {
                    Logger.api.info("‼️ [DEBUG] KBO 스마트 폴링 시작 (teamID: \(teamID))")
                    await startKBOSmartPolling(teamID: teamID)
                } else {
                    Logger.api.info("‼️ [DEBUG] teamID가 없어서 중단됨: \(folder.apiSportsTeamID ?? -1)")
                }
            } else {
                // ESPN 등 일반 리그: 스마트 폴링
                // - 라이브 경기 진행 중 → 30초
                // - 예정 경기만 있음 → 5분
                // - 오늘 표시할 경기 없음 → 종료
                while !Task.isCancelled {
                    let hasLive     = liveFixtures.contains(where: { $0.isLive })
                    let hasUpcoming = liveFixtures.contains(where: { $0.isUpcoming })

                    let sleepSeconds: Double
                    if hasLive {
                        sleepSeconds = 30
                    } else if hasUpcoming {
                        sleepSeconds = 300
                    } else {
                        Logger.api.info("라이브 스코어 폴링: 오늘 진행·예정 경기 없음 → 종료")
                        break
                    }

                    do {
                        try await Task.sleep(for: .seconds(sleepSeconds))
                    } catch is CancellationError {
                        Logger.api.info("라이브 스코어 폴링: 취소로 정상 종료")
                        break
                    } catch {
                        Logger.api.error("라이브 스코어 폴링 sleep 오류(다음 주기 재시도): \(error.localizedDescription, privacy: .public)")
                        try? await Task.sleep(for: .seconds(30))
                        continue
                    }
                    await fetchLiveScores(showLoadingUI: false)
                }
            }
        }
    }

    /// 라이브 스코어 폴링을 중단합니다.
    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - KBO 스마트 폴링 (Firestore 읽기 빈도)
    //
    // Cloud Functions: 시즌 경기창에 약 5분마다 API-Sports → Firestore 동기화.
    // 앱은 그에 맞춰 라이브 중에도 5분마다만 forceRefresh( meta 선조회로 games 생략 가능 ).
    //
    // 상태별 전략
    //   ┌──────────────────────┬────────────────────────────────────────────────────┐
    //   │ 상태                 │ 대기 방식                                          │
    //   ├──────────────────────┼────────────────────────────────────────────────────┤
    //   │ 오늘 경기 없음       │ 폴링 즉시 종료                                     │
    //   │ 모든 경기 종료       │ 폴링 즉시 종료                                     │
    //   │ 라이브 진행 중       │ 5분마다 갱신 (CF 5분 주기와 정렬)                   │
    //   │ 시작 5분 초과 남음   │ (시작 - 5분)까지 Task.sleep (Deep)                 │
    //   │ 시작 5분 이내        │ 1분마다 예열 체크                                  │
    //   └──────────────────────┴────────────────────────────────────────────────────┘

    private func startKBOSmartPolling(teamID: Int) async {
        Logger.api.info("KBO 스마트 폴링: 시작 (teamID: \(teamID, privacy: .public))")
        while !Task.isCancelled {
            Logger.api.info("KBO 스마트 폴링: 주기 실행")
            do {
                // 폴링 루프에서는 항상 최신 Firestore 데이터를 가져와야 라이브 상태 변화를 감지할 수 있음
                let todayGames = try await KBOFirestoreService.shared.fetchTodayFixtures(teamID: teamID, forceRefresh: true)

                // 오늘 경기 없거나 전부 종료 → 완전 종료
                if todayGames.isEmpty || todayGames.allSatisfy({ $0.status.isFinished }) {
                    Logger.api.info("KBO 스마트 폴링: 오늘 남은 경기 없음 → 종료")
                    break
                }

                // 라이브 경기 진행 중 → CF 동기화 주기(약 5분)에 맞춰 폴링
                // liveFixtures를 여기서 직접 갱신해 루프 상단의 fetchTodayFixtures와 중복 fetch 방지
                if todayGames.contains(where: { $0.isLive }) {
                    liveFixtures = todayGames
                    try await Task.sleep(for: .seconds(Self.kboLivePollIntervalSeconds))
                    continue
                }

                // 예정 경기의 시작 시간으로 스마트 대기
                let nextGame = todayGames
                    .filter { !$0.status.isFinished }
                    .min { ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture) }

                guard let gameDate = nextGame?.startTime else { break }

                let timeUntilGame = gameDate.timeIntervalSinceNow

                if timeUntilGame > 300 {
                    // 경기 시작 5분 전까지 Deep Sleep (핵심 최적화)
                    let sleepSeconds = timeUntilGame - 300
                    Logger.api.info("KBO 스마트 폴링: 경기까지 \(Int(timeUntilGame / 60), privacy: .public)분 남음 → \(Int(sleepSeconds / 60), privacy: .public)분 대기")
                    try await Task.sleep(for: .seconds(sleepSeconds))
                } else {
                    // 5분 이내 임박 → 1분마다 예열 체크
                    Logger.api.info("KBO 스마트 폴링: 경기 시작 임박 → 1분 간격 체크")
                    try await Task.sleep(for: .seconds(60))
                }
                await fetchLiveScores(showLoadingUI: false)

            } catch is CancellationError {
                Logger.api.info("KBO 스마트 폴링: 취소로 정상 종료")
                break
            } catch {
                // 네트워크 오류 등 → 30초 후 재시도
                Logger.api.error("KBO 스마트 폴링 오류(30초 후 재시도): \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// 느린 네트워크에서 폴더(팀)만 빠르게 바꾼 뒤 이전 요청이 늦게 도착해 화면을 덮어쓰는 것을 막습니다.
    private func isStillSameSportsFolder(_ requestFolderID: PersistentIdentifier) -> Bool {
        folder.persistentModelID == requestFolderID
    }

    private func fetchLiveScores(showLoadingUI: Bool = true) async {
        let requestFolderID = folder.persistentModelID

        guard NetworkMonitor.shared.isConnected else {
            guard isStillSameSportsFolder(requestFolderID) else { return }
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
                guard isStillSameSportsFolder(requestFolderID) else { return }
                // 스코어보드 API는 리그 전체 경기를 주므로, 이 폴더에서 고른 팀이 출전한 경기만 표시
                if let espnTeam = ESPNTeamsLoader.team(name: folder.name, leagueCode: folder.leagueCode),
                   !espnTeam.id.isESPNFakeID,
                   let myTeamID = Int(espnTeam.id) {
                    fixtures = fixtures.filter { $0.homeTeam.id == myTeamID || $0.awayTeam.id == myTeamID }
                }
                liveFixtures = fixtures
            } catch {
                guard isStillSameSportsFolder(requestFolderID) else { return }
                liveLoadError = error.localizedDescription
                liveFixtures  = []
            }
            return
        }

        // KBO → Firestore 기반 (Cloud Functions 캐시 활용, API 추가 호출 없음)
        // forceRefresh: true — fetchLiveScores는 항상 최신 Firestore 데이터가 필요하므로 캐시를 우회
        if leagueCode == "KBO" {
            var teamID = folder.apiSportsTeamID ?? 0
            // 팀 ID 미설정 시(구버전 폴더 등) Firestore games 캐시에서 자동 조회 후 저장
            if teamID == 0, let resolved = await KBOFirestoreService.shared.resolveTeamID(for: folder.name) {
                guard isStillSameSportsFolder(requestFolderID) else { return }
                folder.apiSportsTeamID = resolved
                teamID = resolved
            }
            guard teamID > 0 else { return }
            do {
                let fixtures = try await KBOFirestoreService.shared.fetchLiveOrUpcomingFixtures(teamID: teamID, forceRefresh: true)
                guard isStillSameSportsFolder(requestFolderID) else { return }
                liveFixtures = fixtures
            } catch {
                guard isStillSameSportsFolder(requestFolderID) else { return }
                liveLoadError = error.localizedDescription
                liveFixtures = []
            }
            return
        }

        // 비ESPN 리그 → API-Sports (100회/일 제한). 키 없음 판단은 SSOT 메서드와 동일.
        guard !ESPNPlayerService.shared.shouldPromptForMissingAPISportsKey(leagueCode: leagueCode) else { return }

        if APIRateLimiter.shared.isLimitReached {
            guard isStillSameSportsFolder(requestFolderID) else { return }
            liveLoadError = String(localized: "api.error.dailyLimitExceeded", defaultValue: "오늘 API 호출 한도(100회)를 초과했습니다. 내일 다시 시도해주세요.")
            return
        }

        do {
            let sport    = folder.sportType
            let leagueID = sport.apiSportsLeagueIDs[leagueCode] ?? 0
            let teamID   = folder.apiSportsTeamID ?? 0
            guard teamID > 0 else { return }

            let fixtures = try await APISportsService.shared.fetchSoccerGames(leagueID: leagueID, teamID: teamID)
            guard isStillSameSportsFolder(requestFolderID) else { return }
            liveFixtures = fixtures
        } catch let error as APISportsError {
            guard isStillSameSportsFolder(requestFolderID) else { return }
            liveLoadError = error.errorDescription
            liveFixtures = []
        } catch {
            guard isStillSameSportsFolder(requestFolderID) else { return }
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

    /// 날짜가 지난 KBO 예정·진행중 티켓을 Firestore 캐시로 조용히 업데이트합니다.
    /// API 추가 호출 없이 메모리 캐시에서 처리하므로 비용 0원.
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
        // scheduleMap에는 PP/CANC 경기가 없으므로, 날짜가 지난 미매핑 티켓 = 연기·취소로 간주
        let oneDayAgo = now.addingTimeInterval(-24 * 3600)
        var hasChanges = false

        for match in pendingMatches {
            guard let eventID = match.externalEventID else { continue }

            if let updated = scheduleMap[eventID] {
                // location이 비어있으면 정적 구장 매핑으로 백필
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
                    // scheduleMap에 있지만 여전히 NS 상태 + 날짜가 하루 이상 지남
                    // → Firestore가 PP로 갱신 안 됐지만 사실상 연기·취소 → 삭제
                    modelContext.delete(match)
                    hasChanges = true
                    Logger.data.info("KBO NS 좀비 티켓 삭제: \(eventID) (\(match.opponentTeam))")
                }
            } else if let matchDate = match.date, matchDate < oneDayAgo,
                      (match.photoPaths ?? []).isEmpty, match.photosData == nil {
                // scheduleMap에 없고(PP/CANC) 날짜가 하루 이상 지남 → 삭제
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

    // MARK: - 실시간 스코어보드 UI 섹션
    
    private var liveScoreboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isLoadingLive {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(String(localized: "sports.live.loading", defaultValue: "실시간 스코어 로딩 중…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // 헤더는 실제 진행 중 경기가 있을 때만 LIVE 스타일 (그 외는 일반 스코어)
                    if scoreboardRelevantFixtures.contains(where: \.isLive) {
                        LiveIndicator()
                        Text(String(localized: "sports.live.header.live", defaultValue: "실시간 스코어"))
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "sportscourt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "sports.live.header.games", defaultValue: "경기 스코어"))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    Text(String(localized: "sports.live.pullRefresh", defaultValue: "· 아래로 당겨서 새로고침"))
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
                Text(String(localized: "sports.live.apiKey.title", defaultValue: "실시간 스코어 미설정"))
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text(String(localized: "sports.live.apiKey.message", defaultValue: "APIKeys.xcconfig에 API_SPORTS_KEY를 설정하면 실시간 스코어를 이용할 수 있습니다. example 파일을 복사해 사용하세요."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            // API 사용량 표시 (키 설정 시)
            let limiter = APIRateLimiter.shared
            if limiter.callCount > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: String(localized: "sports.live.api.callsRemaining", defaultValue: "%lld회 남음"), locale: .autoupdatingCurrent, Int64(limiter.remainingCalls)))
                        .font(.caption2.bold())
                        .foregroundStyle(limiter.remainingCalls < 20 ? .orange : .secondary)
                    Text(String(localized: "sports.live.api.todayRemaining", defaultValue: "오늘 API 잔여"))
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
        .groupedCardOutline(cornerRadius: 16)
    }

    private func bigStatDigit(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(count)")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(verbatim: label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(count) \(label)"))
    }

    // MARK: - 팀 정보 배너 카드 (탭하면 TeamInfoDetailView로 이동)

    private var teamInfoBanner: some View {
        let favCount = favorites.favoriteCount(inFolder: folder.folderID.uuidString)
        let gradients = folder.gradientColors

        let kboBannerAsset: String? = (folder.leagueCode == "KBO")
            ? KBOTeamLogoAsset.imageName(forTeamName: folder.name)
            : nil
        let showBannerLogo = kboBannerAsset != nil || (folder.teamLogoUrl != nil && !(folder.teamLogoUrl?.isEmpty ?? true))

        return HStack(spacing: 14) {
            // 팀 로고
            ZStack {
                LinearGradient(colors: gradients, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if let assetName = kboBannerAsset {
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else if showBannerLogo, let url = folder.teamLogoUrl {
                    KFImage.url(URL(string: url))
                        .placeholder { ProgressView().tint(.white) }
                        .onFailureView {
                            Image(systemName: "person.3.fill")
                                .font(.caption2).foregroundStyle(.white.opacity(0.8))
                        }
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    Image(systemName: "person.3.fill")
                        .font(.subheadline).foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)

            // 텍스트
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "sports.teamBanner.title", defaultValue: "팀 정보"))
                    .font(.subheadline.bold())
                HStack(spacing: 8) {
                    Label(String(localized: "sports.teamBanner.roster", defaultValue: "팀 선수단"), systemImage: "person.3.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if favCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.red)
                            Text(String(format: String(localized: "sports.teamBanner.favoriteCount", defaultValue: "최애 %lld명"), locale: .autoupdatingCurrent, Int64(favCount)))
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
                Text(String(localized: "common.action.viewDetails", defaultValue: "자세히 보기"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
        .groupedCardOutline(cornerRadius: 16)
    }

    // MARK: - 섹션 헤더
    private func sectionHeader(title: String, iconName: String, count: Int, hideCount: Bool = false) -> some View {
        HStack {
            Label(title, systemImage: iconName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            if !hideCount {
                Text(verbatim: "\(count)")
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
            Text(String(localized: "sports.deleteMatch.title", defaultValue: "경기 기록 삭제")),
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
                Text(String(format: String(localized: "record.deleteConfirm", defaultValue: "‘%@’ 기록을 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다."), locale: .autoupdatingCurrent, match.title))
            }
        }
    }
}

// MARK: - 승률 링 (팬 허브 전적 카드)
private struct FanWinRateRingView: View {
    let winRatePercent: Double
    let totalGames: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .stroke(GroupedCardChrome.winRateRingTrackColorHub(colorScheme: colorScheme), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(winRatePercent / 100, 0), 1)))
                .stroke(
                    WinRateTierPalette.ringStrokeGradient(
                        forPercent: winRatePercent,
                        hasCompletedGames: totalGames > 0
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(verbatim: "\(Int(winRatePercent))%")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        WinRateTierPalette.accentColor(
                            forPercent: winRatePercent,
                            hasCompletedGames: totalGames > 0
                        )
                    )
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
    /// from: .now 대신 startOfDay를 사용해야 24시간 미만이어도 "내일" 경기를 D-1로 표시
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
                
                // 날짜 + 장소
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
