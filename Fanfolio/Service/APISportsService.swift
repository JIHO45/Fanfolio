//
//  APISportsService.swift
//  Fanfolio
//
//  API-Sports 네트워킹 서비스 - 비미국 리그 전담 서브 엔진
//
//  ⚠️ 비용 방어 규칙 (필독):
//  - 무료 티어 하루 100회 호출 제한 - Timer 자동 새로고침 절대 금지!
//  - 오직 .refreshable { } 또는 사용자 명시 액션에서만 호출
//
//  ✅ 담당 리그: KBO·EPL·라리가·분데스리가·세리에A·리그1 등 비미국 리그
//  ❌ 미국 4대 스포츠(NFL·NBA·MLB·NHL)는 ESPN API 사용 (무제한 무료)
//

import Foundation
import os.log

// MARK: - 에러 타입

enum APISportsError: Error, LocalizedError {
    case invalidURL
    case noAPIKey
    case rateLimitExceeded
    case decodingFailed(String)
    case networkError(Error)
    case noData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "api.error.invalidURL", defaultValue: "잘못된 API URL입니다.")
        case .noAPIKey:
            return String(localized: "api.error.noAPIKey", defaultValue: "API 키가 설정되지 않았습니다. 프로젝트 루트에서 APIKeys.xcconfig.example을 복사해 APIKeys.xcconfig를 만들고 API_SPORTS_KEY를 넣은 뒤 다시 빌드하세요.")
        case .rateLimitExceeded:
            return String(localized: "api.error.dailyLimitExceeded", defaultValue: "오늘 API 호출 한도(100회)를 초과했습니다. 내일 다시 시도해주세요.")
        case .decodingFailed(let msg):
            return String(
                format: String(localized: "api.error.decodingFailedFormat", defaultValue: "데이터 파싱 오류: %@"),
                locale: .autoupdatingCurrent,
                msg
            )
        case .networkError(let err):
            return String(
                format: String(localized: "api.error.networkErrorFormat", defaultValue: "네트워크 오류: %@"),
                locale: .autoupdatingCurrent,
                err.localizedDescription
            )
        case .noData:
            return String(localized: "api.error.noData", defaultValue: "데이터가 없습니다.")
        }
    }
}

// MARK: - API-Sports 서비스

actor APISportsService {
    
    static let shared = APISportsService()
    private init() {}

    /// ESPN이 지원하지 않는 비미국 전담 리그 코드 집합
    /// 이 목록에 포함된 리그만 API-Sports로 라이브 스코어를 조회한다.
    static let nonESPNLeagues: Set<String> = [
        "KBO",    // 한국 야구
        "KBL",    // 한국 농구
        "ENG.1",  // EPL
        "ESP.1",  // 라리가
        "GER.1",  // 분데스리가
        "ITA.1",  // 세리에 A
        "FRA.1",  // 리그 1
        "USA.1",  // MLS
        "NED.1",  // 에레디비시
        "POR.1",  // 프리메이라리가
        "TUR.1",  // 쉬페르리그
        "BEL.1",  // 주필러 프로리그
        "GRE.1",  // 슈퍼리그 그리스
        "CZE.1",  // 체코 포르스트리가
        "DEN.1",  // 수페르리가
    ]

    private let session = URLSession.shared

    /// 팀 로스터 캐시 (30분 TTL)
    private let squadCache    = TTLCache<String, [APISportsSquadPlayer]>(ttl: APIConfig.CacheTTL.roster)
    /// KBO 일정 캐시 (1시간 TTL)
    private let scheduleCache = TTLCache<String, [MatchEvent]>(ttl: APIConfig.CacheTTL.schedule)
    
    // MARK: - 공통 요청 헬퍼
    
    private func makeRequest(baseURL: String, path: String, params: [String: String]) -> URLRequest? {
        guard !APIConfig.apiSportsKey.isEmpty else { return nil }
        
        var components = URLComponents(string: baseURL + path)
        components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(APIConfig.apiSportsKey, forHTTPHeaderField: "x-apisports-key")
        request.timeoutInterval = 15
        return request
    }
    
    private func fetch<T: Decodable>(_ type: T.Type, request: URLRequest) async throws -> T {
        // RateLimiter 확인 (APIRateLimiter는 @MainActor이므로 await 필요)
        guard await APIRateLimiter.shared.consume() else {
            throw APISportsError.rateLimitExceeded
        }

        Logger.api.info("API-Sports → \(request.url?.path ?? "unknown")")

        return try await withRetry(maxAttempts: 3) {
            let (data, response) = try await self.session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 429:
                    throw APISportsError.rateLimitExceeded
                case 400..<500:
                    throw APISportsError.invalidURL
                default:
                    break
                }
            }

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APISportsError.decodingFailed(error.localizedDescription)
            }
        } shouldRetry: { error in
            // 아래 에러는 재시도해도 의미 없으므로 즉시 실패
            switch error {
            case APISportsError.rateLimitExceeded,
                 APISportsError.noAPIKey,
                 APISportsError.decodingFailed,
                 APISportsError.invalidURL:
                return false
            default:
                return true
            }
        }
    }
    
    // MARK: - 축구 실시간/오늘 경기
    
    func fetchSoccerGames(leagueID: Int, teamID: Int) async throws -> [LiveFixture] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        
        guard let request = makeRequest(
            baseURL: APIConfig.apiSportsURLs["soccer"] ?? "",
            path: "/fixtures",
            params: [
                "league": "\(leagueID)",
                "team": "\(teamID)",
                "date": today,
                "season": currentSoccerSeason(),
            ]
        ) else { throw APISportsError.noAPIKey }
        
        let response = try await fetch(APISportsSoccerResponse.self, request: request)
        return response.response.compactMap { parsedSoccerFixture($0) }
    }
    
    private func parsedSoccerFixture(_ fixture: APISportsSoccerFixture) -> LiveFixture? {
        let status = LiveFixtureStatus(
            short: fixture.fixture.status.short,
            elapsed: fixture.fixture.status.elapsed,
            period: nil
        )
        
        var periods: [PeriodScore] = []
        let ht = fixture.score.halftime
        let ft = fixture.score.fulltime
        if ht.home != nil || ht.away != nil {
            periods.append(PeriodScore(period: String(localized: "scoreboard.period.firstHalf", defaultValue: "전반"), home: ht.home, away: ht.away))
        }
        if ft.home != nil || ft.away != nil {
            let secondHalfHome = ft.home.flatMap { fh in ht.home.map { fh - $0 } }
            let secondHalfAway = ft.away.flatMap { fa in ht.away.map { fa - $0 } }
            periods.append(PeriodScore(period: String(localized: "scoreboard.period.secondHalf", defaultValue: "후반"), home: secondHalfHome, away: secondHalfAway))
        }
        
        let ts = fixture.fixture.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        
        return LiveFixture(
            id: fixture.fixture.id,
            homeTeam: LiveTeamInfo(id: fixture.teams.home.id, name: fixture.teams.home.name, logoURL: fixture.teams.home.logo),
            awayTeam: LiveTeamInfo(id: fixture.teams.away.id, name: fixture.teams.away.name, logoURL: fixture.teams.away.logo),
            score: LiveScore(home: fixture.goals.home, away: fixture.goals.away),
            status: status,
            league: LiveLeagueInfo(id: fixture.league.id, name: fixture.league.name, season: fixture.league.season),
            startTime: ts,
            periods: periods
        )
    }
    
    // MARK: - 팀 로스터 (Squad)
    
    /// API-Sports에서 팀 로스터를 가져옵니다.
    func fetchSquad(sportType: SportType, teamID: Int) async throws -> [APISportsSquadPlayer] {
        let cacheKey = "squad:\(sportType):\(teamID)"
        if let cached = squadCache.get(cacheKey) { return cached }

        let baseURL: String
        let path: String
        var params: [String: String] = ["team": "\(teamID)"]
        
        switch sportType {
        case .americanFootball:
            baseURL = APIConfig.apiSportsURLs["NFL"] ?? ""
            path = "/players/squads"
        case .soccer:
            baseURL = APIConfig.apiSportsURLs["soccer"] ?? ""
            path = "/players/squads"
        case .basketball:
            baseURL = APIConfig.apiSportsURLs["NBA"] ?? ""
            path = "/players"
            params["season"] = currentSeason()
        case .baseball:
            baseURL = APIConfig.apiSportsURLs["MLB"] ?? ""
            path = "/players"
            params["season"] = currentSeason()
        default:
            throw APISportsError.noData
        }
        
        guard let request = makeRequest(baseURL: baseURL, path: path, params: params) else {
            throw APISportsError.noAPIKey
        }
        
        let response = try await fetch(APISportsSquadResponse.self, request: request)
        let players = response.response.first?.players ?? []
        squadCache.set(cacheKey, value: players)
        return players
    }
    
    // MARK: - KBO 경기 일정 (지난 경기 + 예정 경기)

    /// KBO 팀의 시즌 전체 경기 일정을 가져옵니다 (완료 + 예정 혼합).
    func fetchKBOSchedule(teamID: Int) async throws -> [MatchEvent] {
        let year = Calendar.current.component(.year, from: Date())
        let cacheKey = "kbo_schedule:\(teamID):\(year)"
        if let cached = scheduleCache.get(cacheKey) { return cached }

        guard let request = makeRequest(
            baseURL: APIConfig.apiSportsURLs["KBO"] ?? "",
            path: "/games",
            params: ["team": "\(teamID)", "league": "\(APIConfig.LeagueIDs.kbo)", "season": "\(year)"]
        ) else { throw APISportsError.noAPIKey }

        let response = try await fetch(APISportsBaseballGamesResponse.self, request: request)
        let events = response.response.compactMap { parseKBOGame($0, teamID: teamID) }
        scheduleCache.set(cacheKey, value: events)
        return events
    }

    private func parseKBOGame(_ game: APISportsBaseballGame, teamID: Int) -> MatchEvent? {
        let isHome  = game.teams.home.id == teamID
        let oppTeam = isHome ? game.teams.away : game.teams.home
        let isCompleted = game.status.short == "FT" || game.status.short == "F"
        let myScore  = isHome ? game.scores?.home?.total : game.scores?.away?.total
        let oppScore = isHome ? game.scores?.away?.total : game.scores?.home?.total

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date: Date? = game.date.flatMap {
            isoFull.date(from: $0) ?? ISO8601DateFormatter().date(from: $0)
        }

        return MatchEvent(
            id: "api-sports:\(game.id)",
            opponentName: oppTeam.name,
            isHome: isHome,
            myScore:      isCompleted ? myScore  : nil,
            opponentScore: isCompleted ? oppScore : nil,
            date: date,
            leagueName: "KBO",
            isCompleted: isCompleted
        )
    }

    // MARK: - 헬퍼
    
    private func currentSeason() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let month = Calendar.current.component(.month, from: Date())
        return month >= APIConfig.SeasonBoundary.generalStartMonth ? "\(year)" : "\(year - 1)"
    }
    
    private func currentSoccerSeason() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let month = Calendar.current.component(.month, from: Date())
        return month >= APIConfig.SeasonBoundary.soccerStartMonth ? "\(year)" : "\(year - 1)"
    }
}
