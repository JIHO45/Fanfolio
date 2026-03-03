//
//  APISportsService.swift
//  Fanfolio
//
//  API-Sports 네트워킹 서비스
//  주의: 무료 티어 하루 100회 호출 제한 - Timer 자동 새로고침 절대 사용 금지!
//  오직 .refreshable { } 클로저 내에서만 호출하세요.
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
        case .invalidURL: return "잘못된 API URL입니다."
        case .noAPIKey: return "API 키가 설정되지 않았습니다. Info.plist에 API_SPORTS_KEY를 추가하세요."
        case .rateLimitExceeded: return "오늘 API 호출 한도(100회)를 초과했습니다. 내일 다시 시도해주세요."
        case .decodingFailed(let msg): return "데이터 파싱 오류: \(msg)"
        case .networkError(let err): return "네트워크 오류: \(err.localizedDescription)"
        case .noData: return "데이터가 없습니다."
        }
    }
}

// MARK: - API-Sports 서비스

@MainActor
final class APISportsService {
    
    static let shared = APISportsService()
    private init() {}
    
    private let session = URLSession.shared
    
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
        // RateLimiter 확인
        guard APIRateLimiter.shared.consume() else {
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
    
    // MARK: - NFL 실시간/오늘 경기
    
    /// NFL 팀의 오늘 경기 또는 실시간 경기를 가져옵니다.
    func fetchNFLGames(teamID: Int) async throws -> [LiveFixture] {
        guard let request = makeRequest(
            baseURL: APIConfig.apiSportsURLs["NFL"] ?? "",
            path: "/games",
            params: [
                "team": "\(teamID)",
                "season": currentSeason(),
            ]
        ) else { throw APISportsError.noAPIKey }
        
        let response = try await fetch(APISportsNFLResponse.self, request: request)
        return response.response.compactMap { parsedNFLGame($0) }
    }
    
    /// NFL 팀의 오늘 경기만 가져옵니다.
    func fetchNFLLiveOrTodayGames(teamID: Int) async throws -> [LiveFixture] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        
        guard let request = makeRequest(
            baseURL: APIConfig.apiSportsURLs["NFL"] ?? "",
            path: "/games",
            params: ["team": "\(teamID)", "date": today]
        ) else { throw APISportsError.noAPIKey }
        
        let response = try await fetch(APISportsNFLResponse.self, request: request)
        return response.response.compactMap { parsedNFLGame($0) }
    }
    
    private func parsedNFLGame(_ game: APISportsNFLGame) -> LiveFixture? {
        let status = LiveFixtureStatus(
            short: game.game.status.short,
            elapsed: Int(game.game.status.timer ?? ""),
            period: game.game.status.quarter.map { "Q\($0)" }
        )
        
        var periods: [PeriodScore] = []
        let hs = game.scores.home
        let as_ = game.scores.away
        if hs.quarter_1 != nil || as_.quarter_1 != nil {
            periods.append(PeriodScore(period: "1Q", home: hs.quarter_1, away: as_.quarter_1))
        }
        if hs.quarter_2 != nil || as_.quarter_2 != nil {
            periods.append(PeriodScore(period: "2Q", home: hs.quarter_2, away: as_.quarter_2))
        }
        if hs.quarter_3 != nil || as_.quarter_3 != nil {
            periods.append(PeriodScore(period: "3Q", home: hs.quarter_3, away: as_.quarter_3))
        }
        if hs.quarter_4 != nil || as_.quarter_4 != nil {
            periods.append(PeriodScore(period: "4Q", home: hs.quarter_4, away: as_.quarter_4))
        }
        if hs.overtime != nil || as_.overtime != nil {
            periods.append(PeriodScore(period: "OT", home: hs.overtime, away: as_.overtime))
        }
        
        let ts = game.game.date.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        
        return LiveFixture(
            id: game.game.id,
            homeTeam: LiveTeamInfo(id: game.teams.home.id, name: game.teams.home.name, logoURL: game.teams.home.logo),
            awayTeam: LiveTeamInfo(id: game.teams.away.id, name: game.teams.away.name, logoURL: game.teams.away.logo),
            score: LiveScore(home: game.scores.home.total, away: game.scores.away.total),
            status: status,
            league: LiveLeagueInfo(id: 1, name: "NFL", season: Int(currentSeason())),
            startTime: ts,
            periods: periods
        )
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
            periods.append(PeriodScore(period: "전반", home: ht.home, away: ht.away))
        }
        if ft.home != nil || ft.away != nil {
            let secondHalfHome = ft.home.flatMap { fh in ht.home.map { fh - $0 } }
            let secondHalfAway = ft.away.flatMap { fa in ht.away.map { fa - $0 } }
            periods.append(PeriodScore(period: "후반", home: secondHalfHome, away: secondHalfAway))
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
        return response.response.first?.players ?? []
    }
    
    // MARK: - 선수 시즌 스텟
    
    func fetchPlayerStats(sportType: SportType, playerID: Int) async throws -> PlayerSeasonStats? {
        let baseURL: String
        let path: String
        let params: [String: String] = [
            "id": "\(playerID)",
            "season": currentSeason(),
        ]
        
        switch sportType {
        case .americanFootball:
            baseURL = APIConfig.apiSportsURLs["NFL"] ?? ""
            path = "/players/statistics"
        case .soccer:
            baseURL = APIConfig.apiSportsURLs["soccer"] ?? ""
            path = "/players"
        case .basketball:
            baseURL = APIConfig.apiSportsURLs["NBA"] ?? ""
            path = "/players/statistics"
        default:
            return nil
        }
        
        guard let request = makeRequest(baseURL: baseURL, path: path, params: params) else {
            throw APISportsError.noAPIKey
        }
        
        let response = try await fetch(APISportsPlayerStatsResponse.self, request: request)
        guard let item = response.response.first,
              let stats = item.statistics.first else { return nil }
        
        return parseStats(stats, sport: sportType)
    }
    
    private func parseStats(_ stats: APISportsStatistics, sport: SportType) -> PlayerSeasonStats {
        PlayerSeasonStats(
            gamesPlayed: stats.games?.played,
            passingTouchdowns: stats.passing?.touchdowns,
            passingYards: stats.passing?.yards,
            rushingTouchdowns: stats.rushing?.touchdowns,
            rushingYards: stats.rushing?.yards,
            receptions: stats.receiving?.receptions,
            receivingYards: stats.receiving?.yards,
            receivingTouchdowns: stats.receiving?.touchdowns,
            sacks: stats.defensive?.sacks,
            interceptions: stats.defensive?.interceptions,
            goals: stats.goals?.total,
            assists: stats.goals?.assists,
            yellowCards: stats.cards?.yellow,
            redCards: stats.cards?.red,
            minutesPlayed: stats.games?.minutes,
            shotsOnTarget: nil,
            points: stats.points?.total,
            rebounds: nil,
            basketballAssists: nil,
            steals: nil,
            blocks: nil,
            battingAvg: nil,
            homeRuns: nil,
            rbi: nil,
            era: nil,
            strikeouts: nil,
            wins: nil,
            raceWins: nil,
            podiums: nil,
            championshipPoints: nil,
            polePositions: nil
        )
    }
    
    // MARK: - 헬퍼
    
    private func currentSeason() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let month = Calendar.current.component(.month, from: Date())
        // NFL/NBA는 시즌이 전년도 가을 시작
        return month >= 3 ? "\(year)" : "\(year - 1)"
    }
    
    private func currentSoccerSeason() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let month = Calendar.current.component(.month, from: Date())
        return month >= 8 ? "\(year)" : "\(year - 1)"
    }
}
