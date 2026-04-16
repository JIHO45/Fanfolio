//
//  KBOFirestoreService.swift
//  Fanfolio
//
//  Firestore REST API로 KBO 경기 데이터를 읽어옵니다.
//  Firebase SDK 없이 URLSession으로 직접 호출하며,
//  인메모리 TTL 캐시로 Firestore 읽기 횟수를 최소화합니다.
//
//  ⚠️ 비용 방어 규칙:
//  - 전체 시즌 데이터를 1회 읽어 메모리에 보관 (TTL: 3시간)
//  - 팀 필터링은 클라이언트에서 수행 (Firestore 추가 호출 없음)
//  - 자동 새로고침 절대 금지, 사용자 액션에서만 forceRefresh: true
//  - forceRefresh 시 kbo_cache/meta를 먼저 읽어 gamesSyncIso가 이전과 같으면
//    대용량 kbo_cache/games 문서 GET을 생략 (Cloud Functions가 meta와 games에 동일 토큰 기록)
//

import Foundation
import os.log

// MARK: - Firestore REST 값 파서 (SDK 없이 동작)

/// Firestore REST API 응답의 typed value를 처리하는 내부 열거형.
/// https://firebase.google.com/docs/firestore/reference/rest/v1/Value
private indirect enum FSValue: Decodable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case null
    case array([FSValue])
    case map([String: FSValue])

    private enum CK: String, CodingKey {
        case stringValue, integerValue, doubleValue, booleanValue
        case nullValue, arrayValue, mapValue, timestampValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        if let v = try c.decodeIfPresent(String.self, forKey: .stringValue) {
            self = .string(v)
        } else if let v = try c.decodeIfPresent(String.self, forKey: .integerValue), let i = Int(v) {
            self = .integer(i)
        } else if let v = try c.decodeIfPresent(String.self, forKey: .timestampValue) {
            self = .string(v)  // ISO 8601 타임스탬프를 문자열로 처리
        } else if let v = try c.decodeIfPresent(Double.self, forKey: .doubleValue) {
            self = .double(v)
        } else if let v = try c.decodeIfPresent(Bool.self, forKey: .booleanValue) {
            self = .boolean(v)
        } else if c.contains(.nullValue) {
            self = .null
        } else if let arr = try c.decodeIfPresent(_FSArray.self, forKey: .arrayValue) {
            self = .array(arr.values ?? [])
        } else if let map = try c.decodeIfPresent(_FSMap.self, forKey: .mapValue) {
            self = .map(map.fields ?? [:])
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var intValue: Int? {
        switch self {
        case .integer(let i): return i
        case .double(let d):  return Int(d)
        case .string(let s):  return Int(s)
        default:              return nil
        }
    }
    var arrayValue: [FSValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
    var mapValue: [String: FSValue]? {
        if case .map(let m) = self { return m }
        return nil
    }
}

private struct _FSArray: Decodable { let values: [FSValue]? }
private struct _FSMap:   Decodable { let fields: [String: FSValue]? }
private struct _FSDoc:   Decodable { let fields: [String: FSValue]? }

// MARK: - 파싱 중간 모델

private struct KBORawGame {
    let id: Int
    let date: Date?
    let statusShort: String   // "NS", "FT", "IN1"~"IN18" 등
    /// API-Sports `game.stage` 값. 저장하지 않은 구버전 데이터는 nil.
    /// 예: "Regular Season", "Pre Season", "Post Season", "Korean Series"
    let stage: String?
    let homeID: Int
    let awayID: Int
    let homeName: String
    let awayName: String
    let homeLogoURL: String?
    let awayLogoURL: String?
    let homeTotal: Int?
    let awayTotal: Int?
    /// 이닝별 홈팀 점수 (인덱스 0 = 1회). CF 구버전 데이터는 빈 배열.
    let homeInnings: [Int?]
    /// 이닝별 원정팀 점수 (인덱스 0 = 1회). CF 구버전 데이터는 빈 배열.
    let awayInnings: [Int?]

    var isCompleted: Bool { statusShort == "FT" || statusShort == "F" }
    /// 연기·취소·포기 경기. 불러오기 목록에서 제외하고, 순위 계산에서도 건너뜁니다.
    var isPostponedOrCancelled: Bool {
        let s = statusShort.uppercased()
        return s == "POST" || s == "PP" || s == "CANC" || s == "ABD" || s == "WO" || s == "AWD"
    }

    /// 정규시즌 여부.
    /// stage 미저장(nil) 구버전 데이터는 정규시즌으로 간주합니다.
    var isRegularSeason: Bool {
        guard let stage else { return true }
        let lower = stage.lowercased()
        // pre season / postseason·playoffs·korean series 제외
        if lower.contains("pre") { return false }
        if lower.contains("post") || lower.contains("playoff")
            || lower.contains("korean series") || lower.contains("wildcard") { return false }
        return true
    }
    /// API-Sports baseball 라이브 상태 코드:
    /// 이닝(1ST~9TH·IN1~IN18·숫자 1~18), 연장(ET), 하프타임 이닝 사이(HT), LIVE, IN_PLAY
    var isLive: Bool {
        if isCompleted || statusShort == "NS" || statusShort == "TBD" { return false }
        let knownLive: Set<String> = ["1ST","2ND","3RD","4TH","5TH","6TH","7TH","8TH","9TH",
                                      "1H","2H","HT","LIVE","IN_PLAY","ET"]
        if knownLive.contains(statusShort) { return true }
        // 숫자 이닝 (연장 포함)
        if let n = Int(statusShort), (1...18).contains(n) { return true }
        // API-Sports KBO: "IN1"~"IN18" 형식 (예: "IN3" = 3이닝 진행 중)
        if statusShort.hasPrefix("IN"), let n = Int(statusShort.dropFirst(2)), (1...18).contains(n) { return true }
        return false
    }
}

// MARK: - KBO 팀 공개 모델

/// `AddFolderView`의 KBO 팀 선택 UI에 전달되는 공개 타입
struct KBOTeamInfo: Identifiable, Sendable {
    let id: Int           // API-Sports 팀 ID
    let name: String      // 영문 팀 이름
    let logoURL: String?  // API-Sports CDN 로고 URL
}

// MARK: - 에러

enum KBOFirestoreError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case httpError(Int)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(
                localized: "kbo.firestore.error.notConfigured",
                defaultValue: "Firebase 프로젝트 ID가 설정되지 않았습니다. APIKeys.xcconfig에 FIREBASE_PROJECT_ID를 추가하세요."
            )
        case .invalidURL:
            return String(localized: "kbo.firestore.error.invalidURL", defaultValue: "Firestore URL이 올바르지 않습니다.")
        case .httpError(let code):
            return String(
                format: String(localized: "kbo.firestore.error.httpErrorFormat", defaultValue: "Firestore 응답 오류 (HTTP %d). Firestore 보안 규칙과 API 키를 확인하세요."),
                code
            )
        case .parseError(let msg):
            return String(
                format: String(localized: "kbo.firestore.error.parseErrorFormat", defaultValue: "Firestore 데이터 파싱 실패: %@"),
                msg
            )
        }
    }
}

// MARK: - KBO Firestore 서비스

actor KBOFirestoreService {

    static let shared = KBOFirestoreService()
    private init() {}

    /// 인메모리 캐시 TTL: 3시간
    /// 하루 최대 ~8회 Firestore 읽기로 과금 최소화
    private let cacheTTL: TimeInterval = 3 * 60 * 60

    private var rawGamesCache: [KBORawGame]? = nil
    private var cacheExpiry: Date = .distantPast
    private var inFlight: Task<(games: [KBORawGame], syncIso: String?), Error>? = nil
    /// 마지막으로 실제 Firestore 네트워크 호출이 완료된 시각.
    /// forceRefresh여도 이 시각으로부터 10초 이내라면 캐시를 반환해 중복 호출을 차단한다.
    private var lastFetchTime: Date = .distantPast
    /// 마지막으로 로드한 `kbo_cache/games`의 `gamesSyncIso`(CF가 meta·games에 동시 기록).
    /// meta 선조회 시 서버 스냅샷이 바뀌지 않았으면 games 문서 읽기를 건너뜀.
    private var lastGamesSyncIso: String? = nil

    // MARK: - 순위 캐시 (TTL: 30분)
    private let standingsCacheTTL: TimeInterval = 30 * 60
    private var standingsCache: LeagueStandingsPayload? = nil
    private var standingsCacheExpiry: Date = .distantPast

    // MARK: - 공개 API

    /// 특정 팀의 KBO 경기 일정을 `MatchEvent` 배열로 반환합니다.
    /// - Parameters:
    ///   - teamID: API-Sports 팀 ID (`folder.apiSportsTeamID`)
    ///   - forceRefresh: true이면 캐시를 무시하고 Firestore를 다시 읽습니다.
    func fetchKBOSchedule(teamID: Int, forceRefresh: Bool = false) async throws -> [MatchEvent] {
        let raw = try await fetchAllRawGames(forceRefresh: forceRefresh)
        return raw.compactMap { convertToMatchEvent($0, teamID: teamID) }
    }

    /// KBO 전체 순위를 반환합니다. (Firestore kbo_cache/standings, CF가 API-Sports에서 동기화)
    /// - Parameter forceRefresh: true이면 캐시를 무시하고 최신 데이터를 요청합니다.
    func computeKBOStandings(forceRefresh: Bool = false) async throws -> LeagueStandingsPayload {
        if !forceRefresh, let cached = standingsCache, standingsCacheExpiry > Date() {
            return cached
        }
        let result = try await fetchStandingsFromFirestore()
        standingsCache = result
        standingsCacheExpiry = Date().addingTimeInterval(standingsCacheTTL)
        return result
    }

    // MARK: - Firestore kbo_cache/standings (API-Sports 공식 순위)

    private func fetchStandingsFromFirestore() async throws -> LeagueStandingsPayload {
        let projectID = APIConfig.firebaseProjectID
        guard !projectID.isEmpty else { throw KBOFirestoreError.notConfigured }

        let apiKey = APIConfig.firebaseWebAPIKey
        var urlStr = "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/kbo_cache/standings"
        if !apiKey.isEmpty { urlStr += "?key=\(apiKey)" }
        guard let url = URL(string: urlStr) else { throw KBOFirestoreError.invalidURL }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw KBOFirestoreError.httpError(http.statusCode)
        }

        let doc = try JSONDecoder().decode(_FSDoc.self, from: data)
        guard let fields = doc.fields,
              let standingsArr = fields["standings"]?.arrayValue,
              !standingsArr.isEmpty else {
            throw KBOFirestoreError.parseError("standings 배열을 찾을 수 없습니다")
        }

        let source = fields["source"]?.stringValue ?? "unknown"
        Logger.api.debug("Firestore 순위 source: \(source)")

        let year = fields["season"]?.intValue ?? Calendar.current.component(.year, from: Date())

        var rows: [WinPctStandingRow] = []
        for item in standingsArr {
            guard let m = item.mapValue else { continue }
            let position   = m["position"]?.intValue ?? (rows.count + 1)
            let teamName   = m["teamName"]?.stringValue ?? ""
            let wins       = m["wins"]?.intValue ?? 0
            let losses     = m["losses"]?.intValue ?? 0
            let draws      = m["draws"]?.intValue ?? 0
            let winPct     = {
                if case .double(let d) = m["winPct"] { return d }
                if let i = m["winPct"]?.intValue { return Double(i) }
                return 0.0
            }()

            // GB 계산 (1위 기준)
            let gbDisplay: String? = {
                guard position > 1, let leader = standingsArr.first?.mapValue else { return "-" }
                let leaderWins   = leader["wins"]?.intValue ?? 0
                let leaderLosses = leader["losses"]?.intValue ?? 0
                let gb = Double(leaderWins - wins + losses - leaderLosses) / 2.0
                if gb <= 0 { return "-" }
                return gb.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(gb))" : String(format: "%.1f", gb)
            }()

            rows.append(WinPctStandingRow(
                id: m["teamID"]?.intValue.map { "\($0)" } ?? teamName,
                rank: position,
                teamDisplayName: KBOTeamLogoAsset.uiDisplayName(forKBOCandidate: teamName),
                wins: wins,
                losses: losses,
                ties: draws,
                winPct: winPct,
                gamesBehindDisplay: gbDisplay,
                streakDisplay: nil
            ))
        }

        guard !rows.isEmpty else {
            throw KBOFirestoreError.parseError("Firestore 순위: 파싱된 팀 없음")
        }

        let config = WinPctStandingsConfiguration(
            recordFormat: .winsLossesTies,
            subColumns: [.gamesBehind],
            winPctSource: .computeExcludingTies
        )
        let section = WinPctStandingsSection(
            id: "kbo-api-\(year)",
            title: String(
                format: String(localized: "standings.kbo.sectionTitle", defaultValue: "KBO %d 순위"),
                year
            ),
            rows: rows
        )
        Logger.api.info("Firestore API-Sports 순위: \(rows.count)팀 로드 완료")
        return .winPct(config, [section])
    }


    // MARK: - KBO 라이브·오늘 경기 (Firestore 기반, API 추가 호출 없음)

    /// Firestore 캐시에서 오늘 날짜의 팀 경기를 `LiveFixture` 형식으로 반환합니다.
    /// Cloud Functions가 시즌 중 경기 시간대에 약 5분마다 갱신하므로, 앱 폴링 주기와 맞추는 것이 좋습니다.
    /// - Parameters:
    ///   - teamID: API-Sports 팀 ID
    ///   - forceRefresh: true이면 캐시를 무시하고 Firestore를 다시 읽습니다.
    ///     라이브 폴링 경로에서는 반드시 true로 호출해 최신 상태를 반영하세요.
    func fetchTodayFixtures(teamID: Int, forceRefresh: Bool = false) async throws -> [LiveFixture] {
        let games = try await fetchAllRawGames(forceRefresh: forceRefresh)
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        return games.compactMap { game -> LiveFixture? in
            guard game.homeID == teamID || game.awayID == teamID else { return nil }
            guard let date = game.date else { return nil }
            // 날짜를 캘린더 기준으로 비교해 timezone 엣지케이스 방지
            let gameDay = cal.startOfDay(for: date)
            guard gameDay >= today && gameDay < tomorrow else { return nil }
            return convertToLiveFixture(game)
        }
        .sorted { ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture) }
    }

    /// 라이브 중이거나 오늘 예정된 팀 경기를 반환합니다 (오늘 날짜 없으면 다음 예정 경기 1개).
    /// - Parameter forceRefresh: true이면 캐시를 무시합니다. 라이브 폴링 경로에서 true로 호출하세요.
    func fetchLiveOrUpcomingFixtures(teamID: Int, forceRefresh: Bool = false) async throws -> [LiveFixture] {
        let todayFixtures = try await fetchTodayFixtures(teamID: teamID, forceRefresh: forceRefresh)
        if !todayFixtures.isEmpty { return todayFixtures }

        // 오늘 경기 없으면 가장 가까운 예정 경기 1개
        let games = try await fetchAllRawGames(forceRefresh: forceRefresh)
        let now = Date()
        let next = games
            .filter { ($0.homeID == teamID || $0.awayID == teamID) && ($0.date ?? .distantPast) > now }
            .min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        return next.map { [convertToLiveFixture($0)] } ?? []
    }

    private func convertToLiveFixture(_ game: KBORawGame) -> LiveFixture {
        let status = LiveFixtureStatus(
            short: game.statusShort,
            elapsed: nil,
            period: nil
        )

        let periods: [PeriodScore] = game.homeInnings.enumerated().compactMap { idx, homeScore -> PeriodScore? in
            let awayScore = idx < game.awayInnings.count ? game.awayInnings[idx] : nil
            // 둘 다 nil이면 아직 플레이되지 않은 이닝 → 제외
            guard homeScore != nil || awayScore != nil else { return nil }
            let label = idx < 9 ? "\(idx + 1)" : String(localized: "inning.extra.label", defaultValue: "연장")
            return PeriodScore(period: label, home: homeScore, away: awayScore)
        }

        return LiveFixture(
            id: game.id,
            homeTeam: LiveTeamInfo(id: game.homeID, name: game.homeName, logoURL: game.homeLogoURL),
            awayTeam: LiveTeamInfo(id: game.awayID, name: game.awayName, logoURL: game.awayLogoURL),
            score: LiveScore(home: game.homeTotal, away: game.awayTotal),
            status: status,
            league: LiveLeagueInfo(id: APIConfig.LeagueIDs.kbo, name: "KBO", season: nil),
            startTime: game.date,
            periods: periods
        )
    }

    // MARK: - KBO 팀 목록 추출

    /// games 캐시에서 유일한 KBO 팀 목록을 반환합니다.
    /// `AddFolderView`의 KBO 팀 선택 그리드에 사용합니다.
    /// - games가 비어있으면 (시범경기 전·초기 설정) 빈 배열을 반환합니다.
    func fetchKBOTeams(forceRefresh: Bool = false) async throws -> [KBOTeamInfo] {
        let games = try await fetchAllRawGames(forceRefresh: forceRefresh)
        var seen  = Set<Int>()
        var teams: [KBOTeamInfo] = []
        for game in games {
            if seen.insert(game.homeID).inserted {
                teams.append(KBOTeamInfo(id: game.homeID, name: game.homeName, logoURL: game.homeLogoURL))
            }
            if seen.insert(game.awayID).inserted {
                teams.append(KBOTeamInfo(id: game.awayID, name: game.awayName, logoURL: game.awayLogoURL))
            }
        }
        return teams.sorted { $0.name < $1.name }
    }

    // MARK: - 팀 이름 → API-Sports 팀 ID 역조회

    /// games 캐시에서 팀 이름을 검색해 API-Sports 팀 ID를 반환합니다.
    /// KBO 폴더 생성 시 `apiSportsTeamID`를 자동으로 채우는 데 사용합니다.
    /// - Parameter teamName: `espn_teams_master.json`의 `name_en` 또는 `name_kr`
    func resolveTeamID(for teamName: String) async -> Int? {
        guard let games = try? await fetchAllRawGames(forceRefresh: false) else { return nil }
        let normalized = teamName.lowercased()
        for game in games {
            if game.homeName.lowercased().contains(normalized) || normalized.contains(game.homeName.lowercased()) {
                return game.homeID
            }
            if game.awayName.lowercased().contains(normalized) || normalized.contains(game.awayName.lowercased()) {
                return game.awayID
            }
        }
        return nil
    }

    /// games 캐시에서 팀 ID에 해당하는 API-Sports 로고 URL을 반환합니다.
    func resolveTeamLogoURL(for teamID: Int) async -> String? {
        guard let games = try? await fetchAllRawGames(forceRefresh: false) else { return nil }
        for game in games {
            if game.homeID == teamID { return game.homeLogoURL }
            if game.awayID == teamID { return game.awayLogoURL }
        }
        return nil
    }

    /// games 캐시에서 팀 이름으로 로고 URL을 반환합니다.
    /// `SportsDetailView`에서 SwiftData 저장 여부와 무관하게 항상 로고를 표시하는 데 사용합니다.
    func resolveTeamLogoURL(forTeamName name: String) async -> String? {
        guard !name.isEmpty,
              let games = try? await fetchAllRawGames(forceRefresh: false) else { return nil }
        let lower = name.lowercased()
        for game in games {
            if game.homeName.lowercased() == lower { return game.homeLogoURL }
            if game.awayName.lowercased() == lower { return game.awayLogoURL }
        }
        return nil
    }

    // MARK: - 전체 시즌 로드 (캐시 우선)

    private func fetchAllRawGames(forceRefresh: Bool) async throws -> [KBORawGame] {
        // forceRefresh여도 10초 이내에 이미 로드했으면 캐시 반환 (부팅 시 다중 컴포넌트 연사 방어)
        let throttled = forceRefresh && Date().timeIntervalSince(lastFetchTime) < 10.0
        if (!forceRefresh || throttled), let cached = rawGamesCache, cacheExpiry > Date() {
            return cached
        }
        if let task = inFlight {
            return try await task.value.games
        }

        // forceRefresh: 서버가 아직 같은 스냅샷이면 경량 meta만 읽고 games GET 생략
        if forceRefresh && !throttled {
            if let remoteIso = await fetchMetaGamesSyncIso(),
               !remoteIso.isEmpty,
               remoteIso == lastGamesSyncIso,
               let cached = rawGamesCache,
               !cached.isEmpty {
                lastFetchTime = Date()
                Logger.api.info("KBOFirestore: meta 동일 → games 문서 생략 (\(cached.count)경기 메모리 캐시)")
                return cached
            }
        }

        let task = Task<(games: [KBORawGame], syncIso: String?), Error> { try await self._loadFromFirestore() }
        inFlight = task
        do {
            let result = try await task.value
            rawGamesCache = result.games
            if let s = result.syncIso, !s.isEmpty {
                lastGamesSyncIso = s
            }
            cacheExpiry   = Date().addingTimeInterval(cacheTTL)
            lastFetchTime = Date()
            inFlight      = nil
            Logger.api.info("KBOFirestore: \(result.games.count)경기 로드 완료, 캐시 TTL \(Int(self.cacheTTL / 60))분")
            return result.games
        } catch {
            inFlight = nil
            throw error
        }
    }

    /// `kbo_cache/meta`의 `gamesSyncIso` (실패·문서 없음 시 nil)
    private func fetchMetaGamesSyncIso() async -> String? {
        let projectID = APIConfig.firebaseProjectID
        guard !projectID.isEmpty else { return nil }

        let apiKey = APIConfig.firebaseWebAPIKey
        var urlStr = "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/kbo_cache/meta"
        if !apiKey.isEmpty { urlStr += "?key=\(apiKey)" }
        guard let url = URL(string: urlStr) else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            let doc = try JSONDecoder().decode(_FSDoc.self, from: data)
            return doc.fields?["gamesSyncIso"]?.stringValue
        } catch {
            return nil
        }
    }

    // MARK: - Firestore REST API 호출

    private func _loadFromFirestore() async throws -> (games: [KBORawGame], syncIso: String?) {
        let projectID = APIConfig.firebaseProjectID
        guard !projectID.isEmpty else { throw KBOFirestoreError.notConfigured }

        let apiKey = APIConfig.firebaseWebAPIKey
        var urlStr = "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/kbo_cache/games"
        if !apiKey.isEmpty { urlStr += "?key=\(apiKey)" }

        guard let url = URL(string: urlStr) else { throw KBOFirestoreError.invalidURL }

        Logger.api.info("Firestore → kbo_cache/games (\(projectID))")

        var req = URLRequest(url: url)
        req.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw KBOFirestoreError.httpError(http.statusCode)
        }

        let doc = try JSONDecoder().decode(_FSDoc.self, from: data)
        guard let fields = doc.fields,
              let gamesArr = fields["games"]?.arrayValue else {
            throw KBOFirestoreError.parseError("games 배열을 찾을 수 없습니다")
        }

        let syncIso = fields["gamesSyncIso"]?.stringValue
        let games = gamesArr.compactMap { parseRawGame($0) }
        return (games, syncIso)
    }

    // MARK: - Firestore 값 → KBORawGame

    private func parseRawGame(_ value: FSValue) -> KBORawGame? {
        guard let fields = value.mapValue else { return nil }

        guard let gameID = fields["id"]?.intValue else { return nil }

        let dateStr     = fields["date"]?.stringValue ?? ""
        let statusShort = fields["status"]?.mapValue?["short"]?.stringValue ?? "NS"
        let stage       = fields["stage"]?.stringValue   // 구버전 데이터는 nil

        let homeFields = fields["teams"]?.mapValue?["home"]?.mapValue
        let awayFields = fields["teams"]?.mapValue?["away"]?.mapValue
        guard let homeFields, let awayFields else { return nil }

        let homeID   = homeFields["id"]?.intValue   ?? 0
        let awayID   = awayFields["id"]?.intValue   ?? 0
        let homeName = homeFields["name"]?.stringValue ?? ""
        let awayName = awayFields["name"]?.stringValue ?? ""
        let homeLogo = homeFields["logo"]?.stringValue
        let awayLogo = awayFields["logo"]?.stringValue

        let scoresMap = fields["scores"]?.mapValue
        let homeTotal = scoresMap?["homeTotal"]?.intValue
        let awayTotal = scoresMap?["awayTotal"]?.intValue

        // CF 배열 방식: homeInnings / awayInnings 배열로 저장 (구버전은 필드 없음 → 빈 배열)
        let homeInnings: [Int?] = scoresMap?["homeInnings"]?.arrayValue?.map { $0.intValue } ?? []
        let awayInnings: [Int?] = scoresMap?["awayInnings"]?.arrayValue?.map { $0.intValue } ?? []
        // 배열이 있어도 전부 null이면 실질 데이터 없음 (API-Sports 라이브 중 null 반환)
        let hasInningData = homeInnings.contains { $0 != nil } || awayInnings.contains { $0 != nil }

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date: Date? = isoFull.date(from: dateStr) ?? ISO8601DateFormatter().date(from: dateStr)

        return KBORawGame(
            id: gameID,
            date: date,
            statusShort: statusShort,
            stage: stage,
            homeID: homeID,
            awayID: awayID,
            homeName: homeName,
            awayName: awayName,
            homeLogoURL: homeLogo,
            awayLogoURL: awayLogo,
            homeTotal: homeTotal,
            awayTotal: awayTotal,
            homeInnings: hasInningData ? homeInnings : [],
            awayInnings: hasInningData ? awayInnings : []
        )
    }

    // MARK: - KBORawGame → MatchEvent (팀 관점 변환)

    private func convertToMatchEvent(_ game: KBORawGame, teamID: Int) -> MatchEvent? {
        let isHome = game.homeID == teamID
        let isAway = game.awayID == teamID
        guard isHome || isAway else { return nil }
        guard !game.isPostponedOrCancelled else { return nil }

        let opponentName   = isHome ? game.awayName    : game.homeName
        let opponentLogo   = isHome ? game.awayLogoURL : game.homeLogoURL
        let myScore: Int?  = game.isCompleted ? (isHome ? game.homeTotal : game.awayTotal) : nil
        let oppScore: Int? = game.isCompleted ? (isHome ? game.awayTotal : game.homeTotal) : nil

        return MatchEvent(
            id: "firestore-kbo:\(game.id)",
            opponentName: opponentName,
            isHome: isHome,
            myScore: myScore,
            opponentScore: oppScore,
            date: game.date,
            leagueName: "KBO",
            isCompleted: game.isCompleted,
            isLive: game.isLive,
            opponentLogoURL: opponentLogo,
            importedVenueSearchQuery: KBOTeamLogoAsset.homeStadium(forTeamName: game.homeName)
        )
    }
}
