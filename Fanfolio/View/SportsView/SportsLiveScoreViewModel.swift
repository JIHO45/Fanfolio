//
//  SportsLiveScoreViewModel.swift
//  Fanfolio
//

import SwiftUI
import SwiftData
import os.log

/// 라이브 스코어 폴링 상태와 로직을 SportsView에서 분리한 ViewModel.
/// @Observable로 탭 전환 시 뷰가 파괴·재생성되어도 폴링 Task가 안전하게 유지됩니다.
@Observable
final class SportsLiveScoreViewModel {

    // MARK: - 공개 상태 (뷰에서 읽음)
    var liveFixtures: [LiveFixture] = []
    var liveLoadError: String? = nil
    var isLoadingLive = false

    // MARK: - 내부 상태
    private(set) var folder: SportsFanFolder
    private var pollingTask: Task<Void, Never>?
    private var lastSyncDate: Date = .distantPast

    // MARK: - 상수
    private let syncCooldown: TimeInterval = 120
    /// KBO 라이브 시 Firestore 폴링 간격 — `functions/index.js` 의 `fetchKboGameTime`(약 5분)과 맞출 것
    private static let kboLivePollIntervalSeconds: Double = 300

    // MARK: - 초기화
    init(folder: SportsFanFolder) {
        self.folder = folder
    }

    deinit {
        pollingTask?.cancel()
    }

    // MARK: - 라이브 액티비티 연동
    //
    // Foreground에서 폴링 결과(`liveFixtures`)가 갱신될 때마다 호출합니다.
    // - 진행 중(`isLive`) 경기가 있으면 라이브 액티비티를 시작/업데이트
    // - 라이브가 끝났거나 사라졌으면 액티비티 종료
    // - 잠금 화면에서 유저가 강제로 닫은 경우는 LiveActivityManager 내부에서 자동 정리됨
    @MainActor
    private func syncLiveActivity() async {
        let leagueCode = folder.leagueCode ?? ""

        // 가장 진행 중인 경기 1건 선택 (라이브 > 가장 가까운 upcoming 1시간 이내)
        let liveOne = liveFixtures.first(where: { $0.isLive })
        let oneHour = Date().addingTimeInterval(60 * 60)
        let upcomingOne = liveFixtures
            .filter { $0.isUpcoming && ($0.startTime ?? .distantFuture) <= oneHour }
            .min { ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture) }

        guard let target = liveOne ?? upcomingOne else {
            await LiveActivityManager.shared.endActivity()
            return
        }

        let externalEventID = Self.makeExternalEventID(leagueCode: leagueCode, fixtureID: target.id)
        let homeAsset = leagueCode == "KBO" ? KBOTeamLogoAsset.imageName(forTeamName: target.homeTeam.name) : nil
        let awayAsset = leagueCode == "KBO" ? KBOTeamLogoAsset.imageName(forTeamName: target.awayTeam.name) : nil

        let manager = LiveActivityManager.shared
        if manager.currentActivity == nil || manager.currentEventID != externalEventID {
            manager.startActivity(
                fixture: target,
                externalEventID: externalEventID,
                leagueCode: leagueCode,
                homeAssetImageName: homeAsset,
                awayAssetImageName: awayAsset
            )
        } else {
            await manager.updateActivity(fixture: target)
        }
    }

    private static func makeExternalEventID(leagueCode: String, fixtureID: Int) -> String {
        if leagueCode == "KBO" { return "firestore-kbo:\(fixtureID)" }
        return "live:\(leagueCode):\(fixtureID)"
    }

    // MARK: - 계산 프로퍼티

    /// 스코어보드에 표시할 경기.
    /// - 완료 경기는 제외
    /// - 이미 upcoming으로 추적 중인 경기는 중복 방지를 위해 제외
    var scoreboardRelevantFixtures: [LiveFixture] {
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

    // MARK: - 동기화 쿨다운 체크

    /// syncCooldown 이내 중복 실행을 차단. 통과 시 lastSyncDate를 갱신합니다.
    func checkAndUpdateSyncCooldown() -> Bool {
        guard Date().timeIntervalSince(lastSyncDate) >= syncCooldown else { return false }
        lastSyncDate = Date()
        return true
    }

    // MARK: - 폴링 수명주기

    /// 라이브 스코어 폴링을 시작합니다. 기존 폴링이 있으면 먼저 취소합니다.
    func startPolling() {
        guard folder.sportType != .other else { return }
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchLiveScores()

            guard !Task.isCancelled else { return }

            if (folder.leagueCode ?? "") == "KBO" {
                if let teamID = folder.apiSportsTeamID, teamID > 0 {
                    await startKBOSmartPolling(teamID: teamID)
                }
            } else {
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
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - KBO 스마트 폴링

    private func startKBOSmartPolling(teamID: Int) async {
        Logger.api.info("KBO 스마트 폴링: 시작 (teamID: \(teamID, privacy: .public))")
        while !Task.isCancelled {
            Logger.api.info("KBO 스마트 폴링: 주기 실행")
            do {
                let todayGames = try await KBOFirestoreService.shared.fetchTodayFixtures(teamID: teamID, forceRefresh: true)

                if todayGames.isEmpty || todayGames.allSatisfy({ $0.status.isFinished }) {
                    Logger.api.info("KBO 스마트 폴링: 오늘 남은 경기 없음 → 종료")
                    break
                }

                if todayGames.contains(where: { $0.isLive }) {
                    await MainActor.run { self.liveFixtures = todayGames }
                    await syncLiveActivity()
                    try await Task.sleep(for: .seconds(Self.kboLivePollIntervalSeconds))
                    continue
                }

                let nextGame = todayGames
                    .filter { !$0.status.isFinished }
                    .min { ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture) }

                guard let gameDate = nextGame?.startTime else { break }

                let timeUntilGame = gameDate.timeIntervalSinceNow

                if timeUntilGame > 300 {
                    let sleepSeconds = timeUntilGame - 300
                    Logger.api.info("KBO 스마트 폴링: 경기까지 \(Int(timeUntilGame / 60), privacy: .public)분 남음 → \(Int(sleepSeconds / 60), privacy: .public)분 대기")
                    try await Task.sleep(for: .seconds(sleepSeconds))
                } else {
                    Logger.api.info("KBO 스마트 폴링: 경기 시작 임박 → 1분 간격 체크")
                    try await Task.sleep(for: .seconds(60))
                }
                await fetchLiveScores(showLoadingUI: false)

            } catch is CancellationError {
                Logger.api.info("KBO 스마트 폴링: 취소로 정상 종료")
                break
            } catch {
                Logger.api.error("KBO 스마트 폴링 오류(30초 후 재시도): \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: - 라이브 스코어 로드

    /// 느린 네트워크에서 폴더가 이미 바뀐 경우 이전 요청 결과가 덮어쓰지 않도록 방어합니다.
    private func isStillSameFolder(_ requestFolderID: PersistentIdentifier) -> Bool {
        folder.persistentModelID == requestFolderID
    }

    @MainActor
    func fetchLiveScores(showLoadingUI: Bool = true) async {
        let requestFolderID = folder.persistentModelID

        guard NetworkMonitor.shared.isConnected else {
            guard isStillSameFolder(requestFolderID) else { return }
            liveLoadError = String(localized: "network.error.noConnection", defaultValue: "인터넷 연결이 없습니다. 연결 후 다시 시도해주세요.")
            return
        }
        if showLoadingUI { isLoadingLive = true }
        liveLoadError = nil

        defer { if showLoadingUI { isLoadingLive = false } }

        let leagueCode = folder.leagueCode ?? ""

        // ESPN 스코어보드 지원 리그
        if ESPNPlayerService.shared.supportsLiveScoreboard(leagueCode) {
            do {
                var fixtures = try await ESPNPlayerService.shared.fetchLiveScoreboard(leagueCode: leagueCode)
                guard isStillSameFolder(requestFolderID) else { return }
                if let espnTeam = ESPNTeamsLoader.team(name: folder.name, leagueCode: folder.leagueCode),
                   !espnTeam.id.isESPNFakeID,
                   let myTeamID = Int(espnTeam.id) {
                    fixtures = fixtures.filter { $0.homeTeam.id == myTeamID || $0.awayTeam.id == myTeamID }
                }
                liveFixtures = fixtures
            } catch {
                guard isStillSameFolder(requestFolderID) else { return }
                liveLoadError = error.localizedDescription
                liveFixtures  = []
            }
            await syncLiveActivity()
            return
        }

        // KBO → Firestore 기반
        if leagueCode == "KBO" {
            var teamID = folder.apiSportsTeamID ?? 0
            if teamID == 0, let resolved = await KBOFirestoreService.shared.resolveTeamID(for: folder.name) {
                guard isStillSameFolder(requestFolderID) else { return }
                folder.apiSportsTeamID = resolved
                teamID = resolved
            }
            guard teamID > 0 else { return }
            do {
                let fixtures = try await KBOFirestoreService.shared.fetchLiveOrUpcomingFixtures(teamID: teamID, forceRefresh: true)
                guard isStillSameFolder(requestFolderID) else { return }
                liveFixtures = fixtures
            } catch {
                guard isStillSameFolder(requestFolderID) else { return }
                liveLoadError = error.localizedDescription
                liveFixtures = []
            }
            await syncLiveActivity()
            return
        }

        // 비ESPN 리그 → API-Sports
        guard !ESPNPlayerService.shared.shouldPromptForMissingAPISportsKey(leagueCode: leagueCode) else { return }

        if APIRateLimiter.shared.isLimitReached {
            guard isStillSameFolder(requestFolderID) else { return }
            liveLoadError = String(localized: "api.error.dailyLimitExceeded", defaultValue: "오늘 API 호출 한도(100회)를 초과했습니다. 내일 다시 시도해주세요.")
            return
        }

        do {
            let sport    = folder.sportType
            let leagueID = sport.apiSportsLeagueIDs[leagueCode] ?? 0
            let teamID   = folder.apiSportsTeamID ?? 0
            guard teamID > 0 else { return }

            let fixtures = try await APISportsService.shared.fetchSoccerGames(leagueID: leagueID, teamID: teamID)
            guard isStillSameFolder(requestFolderID) else { return }
            liveFixtures = fixtures
        } catch let error as APISportsError {
            guard isStillSameFolder(requestFolderID) else { return }
            liveLoadError = error.errorDescription
            liveFixtures = []
        } catch {
            guard isStillSameFolder(requestFolderID) else { return }
            liveLoadError = String(localized: "error.load.generic", defaultValue: "데이터를 불러오는 중 오류가 발생했습니다.")
            liveFixtures = []
        }
        await syncLiveActivity()
    }

}
