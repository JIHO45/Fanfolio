//
//  ESPNPlayerService.swift
//  Fanfolio
//
//  Created by 박지호 on 2/24/26.
//
//  ESPN 비공식 Site API를 활용해 팀 로스터와 선수 헤드샷을 제공합니다.
//
//  ■ 팀 종목 (NFL·NBA·MLB·축구)
//    https://site.api.espn.com/apis/site/v2/sports/{sport}/{league}/teams/{teamId}/roster
//

import Foundation
import os.log

// MARK: - ESPN 서비스 에러 타입

enum ESPNServiceError: Error, LocalizedError {
    case unsupportedLeague(String)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedLeague(let code):
            return String(
                format: String(localized: "espn.error.unsupportedLeagueFormat", defaultValue: "ESPN이 ‘%@’ 리그를 지원하지 않습니다."),
                locale: .autoupdatingCurrent,
                code
            )
        case .networkError(let e):
            return String(
                format: String(localized: "api.error.networkErrorFormat", defaultValue: "네트워크 오류: %@"),
                locale: .autoupdatingCurrent,
                e.localizedDescription
            )
        case .decodingError(let e):
            return String(
                format: String(localized: "api.error.decodingFailedFormat", defaultValue: "데이터 파싱 오류: %@"),
                locale: .autoupdatingCurrent,
                e.localizedDescription
            )
        }
    }
}

// MARK: - 선수 모델 (티켓 공유 전용)

struct ESPNAthlete: Identifiable, Sendable {
    let id: String
    let name: String
    let position: String?
    let jerseyNumber: String?
    /// ESPN CDN 헤드샷 URL
    let headshotURL: String?

    /// 피커 라벨용 성(last name) 또는 닉네임
    var shortName: String {
        name.split(separator: " ").last.map(String.init) ?? name
    }
}

extension String {
    /// ESPN master JSON의 fake ID 여부 확인 ("kbo_1" 등)
    var isESPNFakeID: Bool { contains("_") }
}

// MARK: - ESPN API 응답 디코딩 (내부 전용)

private struct ESPNRosterResponse: Decodable, Sendable {
    var athletes: [ESPNAthleteRaw] = []

    enum CodingKeys: String, CodingKey {
        case athletes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 시도 1: 그룹으로 묶인 형태 (NFL 등 - items 배열이 있는 경우)
        if let grouped = try? container.decode([ESPNPositionGroup].self, forKey: .athletes) {
            self.athletes = grouped.flatMap { $0.items }
        }
        // 시도 2: 선수들이 바로 나열된 형태 (NBA, 축구 등 - items가 없는 경우)
        else if let flat = try? container.decode([ESPNAthleteRaw].self, forKey: .athletes) {
            self.athletes = flat
        }
    }
}

private struct ESPNPositionGroup: Decodable, Sendable {
    let items: [ESPNAthleteRaw]
}

private struct ESPNHeadshotRaw: Decodable, Sendable {
    let href: String?
}

private struct ESPNAthleteRaw: Decodable, Sendable {
    let id: String
    let displayName: String
    let jersey: String?
    let position: ESPNPositionRaw?
    let headshot: ESPNHeadshotRaw?

    func toAthlete() -> ESPNAthlete? {
        guard !id.isEmpty, !displayName.isEmpty else { return nil }
        return ESPNAthlete(
            id: id,
            name: displayName,
            position: position?.abbreviation,
            jerseyNumber: jersey,
            headshotURL: headshot?.href
        )
    }
}
private struct ESPNPositionRaw: Decodable, Sendable { let abbreviation: String? }

// MARK: - ESPN 선수 서비스

actor ESPNPlayerService {

    static let shared = ESPNPlayerService()
    private init() {}

    /// TTL 캐시: 로스터 30분
    private let rosterCache = TTLCache<String, [ESPNAthlete]>(ttl: 1800)

    // MARK: - 팀 종목: 로스터 조회

    /// ESPN 팀 ID로 로스터를 가져옵니다. (NFL·NBA·MLB·NHL·축구·F1)
    func fetchRoster(teamESPNId: String, leagueCode: String) async throws -> [ESPNAthlete] {
        let key = "roster:\(leagueCode):\(teamESPNId)"
        if let hit = rosterCache.get(key) { return hit }

        guard let (sport, league) = teamSportPath(for: leagueCode),
              let url = URL(string:
                "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(league)/teams/\(teamESPNId)/roster")
        else { throw ESPNServiceError.unsupportedLeague(leagueCode) }

        Logger.api.info("ESPN → roster: \(leagueCode)/\(teamESPNId)")

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw ESPNServiceError.networkError(error)
        }

        do {
            let response = try JSONDecoder().decode(ESPNRosterResponse.self, from: data)
            let athletes = response.athletes.compactMap { $0.toAthlete() }
            rosterCache.set(key, value: athletes)
            Logger.api.info("ESPN roster loaded: \(athletes.count) athletes for \(leagueCode)/\(teamESPNId)")
            return athletes
        } catch {
            throw ESPNServiceError.decodingError(error)
        }
    }

    // MARK: - 팀 스포츠 라이브 스코어보드 (NFL·NBA·MLB)

    /// ESPN 스코어보드에서 팀 스포츠의 오늘 경기 목록을 가져옵니다.
    /// 호출 제한이 없으므로 pull-to-refresh 시 자유롭게 호출 가능합니다.
    func fetchLiveScoreboard(leagueCode: String) async throws -> [LiveFixture] {
        guard let (sport, league) = teamSportPath(for: leagueCode),
              let url = URL(string:
                "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(league)/scoreboard")
        else { throw ESPNServiceError.unsupportedLeague(leagueCode) }

        Logger.api.info("ESPN → live scoreboard: \(leagueCode)")

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw ESPNServiceError.networkError(error)
        }

        do {
            let response = try JSONDecoder().decode(ESPNLiveScoreboardResponse.self, from: data)
            let fixtures = response.events.compactMap { parseESPNEvent($0, sport: sport, leagueCode: leagueCode) }
            Logger.api.info("ESPN scoreboard loaded: \(fixtures.count) fixtures for \(leagueCode)")
            return fixtures
        } catch {
            throw ESPNServiceError.decodingError(error)
        }
    }

    // MARK: - ESPN 이벤트 → LiveFixture 파싱

    private func parseESPNEvent(_ event: ESPNLiveEvent, sport: String, leagueCode: String) -> LiveFixture? {
        guard let competition = event.competitions.first else { return nil }

        let homeComp = competition.competitors.first { $0.homeAway == "home" }
        let awayComp = competition.competitors.first { $0.homeAway == "away" }
        guard let home = homeComp, let away = awayComp else { return nil }

        let homeScore = home.score.flatMap { Int($0) }
        let awayScore = away.score.flatMap { Int($0) }

        let period     = competition.status.period ?? 0
        let statusType = competition.status.type
        let statusName = statusType.name
        // `name`만으로는 종료 경기가 진행 중(쿼터 코드)으로 잘못 분류되는 경우가 있어
        // ESPN의 state/completed를 우선합니다. (예: state == "post")
        let statusShort: String
        if statusType.completed == true || statusType.state == "post" {
            statusShort = "FT"
        } else {
            statusShort = espnStatusShort(statusName: statusName, period: period, sport: sport)
        }
        let elapsed     = competition.status.clock.map { Int($0 / 60) }

        let status = LiveFixtureStatus(
            short: statusShort,
            elapsed: elapsed,
            period: statusShort
        )

        let periods = espnLineScorePeriods(home: home, away: away, sport: sport, statusShort: statusShort)

        // 시작 시간 파싱
        // ESPN은 초 없는 형식("2026-04-15T18:00Z")과 초 있는 형식("2026-04-15T18:00:00Z"),
        // 밀리초 형식("2026-04-15T18:00:00.000Z") 등 여러 형식을 혼용하므로 순차 시도
        let startDate: Date? = event.date.flatMap { Self.parseESPNDate($0) }

        let eventID = Int(event.id) ?? event.id.hashValue

        return LiveFixture(
            id: eventID,
            homeTeam: LiveTeamInfo(id: Int(home.team.id) ?? 0, name: home.team.displayName, logoURL: home.team.logo),
            awayTeam: LiveTeamInfo(id: Int(away.team.id) ?? 0, name: away.team.displayName, logoURL: away.team.logo),
            score: LiveScore(home: homeScore, away: awayScore),
            status: status,
            league: LiveLeagueInfo(id: 0, name: leagueCode, season: nil),
            startTime: startDate,
            periods: periods
        )
    }

    // MARK: - ESPN linescores → 피리어드 점수

    /// `parseESPNEvent`·일정 파싱 등에서 공통 사용 (actor 격리 없음).
    nonisolated private func espnLineScorePeriods(
        home: ESPNLiveCompetitor,
        away: ESPNLiveCompetitor,
        sport: String,
        statusShort: String
    ) -> [PeriodScore] {
        let periodLabels = espnPeriodLabels(sport: sport)
        let homeLines    = home.linescores ?? []
        let awayLines    = away.linescores ?? []
        var maxPeriods   = max(homeLines.count, awayLines.count)
        if sport == "baseball", statusShort == "FT" {
            maxPeriods = max(maxPeriods, 9)
        }

        var periods: [PeriodScore] = []
        for i in 0..<maxPeriods {
            let label      = i < periodLabels.count ? periodLabels[i] : "OT\(i - periodLabels.count + 1)"
            let hVal       = i < homeLines.count ? homeLines[i].value.map { Int($0) } : nil
            let aVal       = i < awayLines.count ? awayLines[i].value.map { Int($0) } : nil
            let includeRow = (hVal != nil || aVal != nil)
                || (sport == "baseball" && statusShort == "FT")
            if includeRow {
                periods.append(PeriodScore(period: label, home: hVal, away: aVal))
            }
        }
        return periods
    }

    // MARK: - ESPN 상태 코드 → LiveFixtureStatus.short 변환

    nonisolated private func espnStatusShort(statusName: String, period: Int, sport: String) -> String {
        switch statusName {
        case "STATUS_SCHEDULED", "STATUS_DELAYED", "STATUS_POSTPONED":
            return "NS"
        case "STATUS_HALFTIME":
            return "HT"
        case "STATUS_FINAL", "STATUS_FINAL_OT", "STATUS_FINAL_PEN", "STATUS_COMPLETE":
            return "FT"
        case "STATUS_IN_PROGRESS", "STATUS_END_PERIOD":
            return espnPeriodShort(period: period, sport: sport)
        default:
            return "NS"
        }
    }

    nonisolated private func espnPeriodShort(period: Int, sport: String) -> String {
        switch sport {
        case "football":    // NFL
            switch period {
            case 1: return "1Q"
            case 2: return "2Q"
            case 3: return "3Q"
            case 4: return "4Q"
            default: return "OT"
            }
        case "basketball":  // NBA
            switch period {
            case 1: return "1Q"
            case 2: return "2Q"
            case 3: return "3Q"
            case 4: return "4Q"
            default: return "OT"
            }
        case "hockey":      // NHL
            switch period {
            case 1: return "1P"
            case 2: return "2P"
            case 3: return "3P"
            default: return "OT"
            }
        case "baseball":    // MLB
            return String(
                format: String(localized: "scoreboard.inning.labelFormat", defaultValue: "%lld회"),
                locale: .autoupdatingCurrent,
                Int64(max(period, 1))
            )
        default:
            return period > 0 ? "\(period)Q" : "1Q"
        }
    }

    /// 종목별 피리어드 라벨 배열 (linescores 인덱스와 매핑)
    nonisolated private func espnPeriodLabels(sport: String) -> [String] {
        switch sport {
        case "football":   return ["1Q", "2Q", "3Q", "4Q"]
        case "basketball": return ["1Q", "2Q", "3Q", "4Q"]
        case "hockey":     return ["1P", "2P", "3P"]
        case "baseball":
            return (1...9).map {
                String(
                    format: String(localized: "scoreboard.inning.labelFormat", defaultValue: "%lld회"),
                    locale: .autoupdatingCurrent,
                    Int64($0)
                )
            }
        default:
            return [
                String(localized: "scoreboard.period.firstHalf", defaultValue: "전반"),
                String(localized: "scoreboard.period.secondHalf", defaultValue: "후반"),
            ]
        }
    }

    // MARK: - 팀 일정 조회 (종목 불문 완벽 통합본)

    /// - 미국 스포츠(NFL·NBA·MLB): 프리시즌(1) + 정규(2) + 포스트(3) × 과거/미래 2회 병렬 호출
    /// - 축구: seasontype 미사용(ESPN이 현재 시즌 자동 반환) + 챔피언스리그 추가 조회
    func fetchTeamSchedule(teamESPNId: String, leagueCode: String) async throws -> [MatchEvent] {
        guard let (sport, _) = teamSportPath(for: leagueCode) else {
            throw ESPNServiceError.unsupportedLeague(leagueCode)
        }

        Logger.api.info("ESPN → schedule (Ultimate Fetch): \(leagueCode)/\(teamESPNId)")

        // 축구는 seasontype을 지정하면 정규 리그 데이터가 무시되므로 nil(ESPN 기본값) 사용
        var targets: [(code: String, seasonType: Int?)]
        if sport == "soccer" {
            targets = [(leagueCode, nil)]
        } else {
            targets = [
                (leagueCode, 1),  // 프리시즌 / 시범경기
                (leagueCode, 2),  // 정규 시즌
                (leagueCode, 3),  // 포스트시즌 / 플레이오프 / 슈퍼볼
            ]
        }
        for cupCode in soccerCupLeagues(for: leagueCode) {
            targets.append((cupCode, nil))
        }

        let maxConcurrency = 8

        let allEvents = await withTaskGroup(of: [MatchEvent].self) { group in
            var inFlight = 0
            var all: [MatchEvent] = []

            for target in targets {
                guard let (sport, league) = self.teamSportPath(for: target.code) else { continue }
                let baseUrlStr = "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(league)/teams/\(teamESPNId)/schedule"

                // 타겟당 과거용(fixture=false) · 미래용(fixture=true) 두 번 호출
                for isFixture in [false, true] {
                    // 동시 요청 수 제한: 최대 8개 초과 시 하나 완료를 기다린 후 추가
                    if inFlight >= maxConcurrency {
                        if let batch = await group.next() {
                            all.append(contentsOf: batch)
                            inFlight -= 1
                        }
                    }

                    let capturedTarget = target
                    group.addTask {
                        guard var components = URLComponents(string: baseUrlStr) else { return [] }
                        var queryItems: [URLQueryItem] = []
                        if let st = capturedTarget.seasonType {
                            queryItems.append(URLQueryItem(name: "seasontype", value: "\(st)"))
                        }
                        if isFixture {
                            queryItems.append(URLQueryItem(name: "fixture", value: "true"))
                        }
                        if !queryItems.isEmpty { components.queryItems = queryItems }
                        guard let url = components.url else { return [] }
                        do {
                            let (data, _) = try await URLSession.shared.data(from: url)
                            let response  = try JSONDecoder().decode(ESPNLiveScoreboardResponse.self, from: data)
                            return response.events.compactMap {
                                self.parseESPNScheduleEvent($0, teamESPNId: teamESPNId, leagueCode: capturedTarget.code)
                            }
                        } catch {
                            // 일부 조합(챔스 프리시즌 등)은 존재하지 않아 에러가 나는 것이 정상 — 빈 배열 반환
                            return []
                        }
                    }
                    inFlight += 1
                }
            }

            for await batch in group { all.append(contentsOf: batch) }
            return all
        }

        // 중복 제거 후 날짜순 정렬
        var seen = Set<String>()
        return allEvents
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    /// 해당 리그 소속 팀이 참가할 수 있는 컵 대회 코드 목록 (축구 전용)
    /// 등록 리그 코드를 기준으로, 해당 팀이 실제로 뛸 수 있는 대회만 추가 조회합니다.
    /// 예) ENG.1(리버풀) → FA컵·리그컵·챔스·유로파만. 라리가·분데스 등은 시도하지 않습니다.
    /// UEFA 대회로만 등록된 팀은 소속 국내 리그를 알 수 없어 5대 리그 전체를 시도합니다.
    nonisolated private func soccerCupLeagues(for leagueCode: String) -> [String] {
        let uefa   = ["UEFA.CHAMPIONS", "UEFA.EUROPA"]
        let eng    = ["ENG.1", "ENG.FA", "ENG.LEAGUE_CUP"]
        let esp    = ["ESP.1", "ESP.COPA"]
        let ger    = ["GER.1", "GER.DFB"]
        let ita    = ["ITA.1", "ITA.COPPA"]
        let fra    = ["FRA.1", "FRA.COUPE_DE_FRANCE"]

        let bundle: [String]
        switch leagueCode {
        case "ENG.1", "ENG.FA", "ENG.LEAGUE_CUP":
            bundle = eng + uefa
        case "ESP.1", "ESP.COPA":
            bundle = esp + uefa
        case "GER.1", "GER.DFB":
            bundle = ger + uefa
        case "ITA.1", "ITA.COPPA":
            bundle = ita + uefa
        case "FRA.1", "FRA.COUPE_DE_FRANCE":
            bundle = fra + uefa
        case "NED.1":
            bundle = ["NED.1"] + uefa
        case "POR.1":
            bundle = ["POR.1"] + uefa
        case "TUR.1":
            bundle = ["TUR.1"] + uefa
        case "BEL.1":
            bundle = ["BEL.1"] + uefa
        case "GRE.1":
            bundle = ["GRE.1"] + uefa
        case "CZE.1":
            bundle = ["CZE.1"] + uefa
        case "DEN.1":
            bundle = ["DEN.1"] + uefa
        case "UEFA.CHAMPIONS", "UEFA.EUROPA":
            // 소속 국내 리그 불명 → 5대 리그 + 국내 컵 전체 시도 (부득이)
            bundle = eng + esp + ger + ita + fra + uefa
        default:
            return []
        }
        return bundle.filter { $0 != leagueCode }
    }

    nonisolated private func parseESPNScheduleEvent(
        _ event: ESPNLiveEvent,
        teamESPNId: String,
        leagueCode: String
    ) -> MatchEvent? {
        guard let competition = event.competitions.first else { return nil }

        // 취소·연기·몰수 경기는 열리지 않으므로 파싱 대상에서 제외
        let ghostStatuses: Set<String> = [
            "STATUS_POSTPONED", "STATUS_CANCELED",
            "STATUS_SUSPENDED", "STATUS_FORFEIT"
        ]
        guard !ghostStatuses.contains(competition.status.type.name) else { return nil }

        let homeComp = competition.competitors.first { $0.homeAway == "home" }
        let awayComp = competition.competitors.first { $0.homeAway == "away" }
        guard let home = homeComp, let away = awayComp else { return nil }

        let isHome      = home.team.id == teamESPNId
        let myComp      = isHome ? home : away
        let oppComp     = isHome ? away : home
        let isCompleted = competition.status.type.completed ?? false

        let liveStatuses: Set<String> = [
            "STATUS_IN_PROGRESS", "STATUS_HALFTIME",
            "STATUS_END_PERIOD",  "STATUS_PLAY_DELAY"
        ]
        let isLive = liveStatuses.contains(competition.status.type.name)

        let myScore     = myComp.score.flatMap { Int($0) }
        let oppScore    = oppComp.score.flatMap { Int($0) }
        let date        = event.date.flatMap { Self.parseESPNDate($0) }

        guard let (sport, _) = teamSportPath(for: leagueCode) else { return nil }

        let statusType = competition.status.type
        let periodNum  = competition.status.period ?? 0
        let statusShortForLines: String
        if statusType.completed == true || statusType.state == "post" {
            statusShortForLines = "FT"
        } else if isLive {
            statusShortForLines = espnStatusShort(statusName: statusType.name, period: periodNum, sport: sport)
        } else {
            statusShortForLines = "NS"
        }
        let periods: [PeriodScore] = (isCompleted || isLive)
            ? espnLineScorePeriods(home: home, away: away, sport: sport, statusShort: statusShortForLines)
            : []

        return MatchEvent(
            id: "espn:\(event.id)",
            opponentName: oppComp.team.displayName,
            isHome: isHome,
            myScore:      (isCompleted || isLive) ? myScore  : nil,
            opponentScore: (isCompleted || isLive) ? oppScore : nil,
            date: date,
            leagueName: leagueCode,
            isCompleted: isCompleted,
            isLive: isLive,
            periods: periods
        )
    }

    // MARK: - 분류 헬퍼

    /// 해당 리그 코드가 ESPN으로 라이브 스코어보드를 제공하는 팀 스포츠인지 여부
    nonisolated func supportsLiveScoreboard(_ leagueCode: String) -> Bool {
        teamSportPath(for: leagueCode) != nil
    }

    /// 라이브 스코어를 API-Sports로만 가져올 수 있는 리그에서 `API_SPORTS_KEY`가 비어 있을 때
    /// 안내 배너를 띄우거나 `fetchLiveScores`의 API-Sports 분기를 건너뛸 때 사용합니다.
    nonisolated func shouldPromptForMissingAPISportsKey(leagueCode: String) -> Bool {
        guard !supportsLiveScoreboard(leagueCode) else { return false }
        return APIConfig.apiSportsKey.isEmpty
    }

    // MARK: - 날짜 파싱 헬퍼

    /// ESPN API는 초 없는 형식("2026-04-15T18:00Z"), 초 있는 형식("T18:00:00Z"),
    /// 밀리초 형식("T18:00:00.000Z") 등을 혼용하므로 순차적으로 시도합니다.
    nonisolated static func parseESPNDate(_ dateStr: String) -> Date? {
        // 1순위: 밀리초 포함 (T18:00:00.000Z)
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: dateStr) { return d }

        // 2순위: 초 포함 (T18:00:00Z)
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: dateStr) { return d }

        // 3순위: 초 없음 (T18:00Z) — ESPN이 가장 자주 사용하는 형식
        let f3 = DateFormatter()
        f3.locale = Locale(identifier: "en_US_POSIX")
        f3.dateFormat = "yyyy-MM-dd'T'HH:mmX"
        return f3.date(from: dateStr)
    }

    // nonisolated: 순수 switch 함수로 actor 상태에 접근하지 않음
    nonisolated private func teamSportPath(for code: String) -> (String, String)? {
        switch code {
        case "NFL":  return ("football",   "nfl")
        case "NBA":  return ("basketball", "nba")
        case "MLB":  return ("baseball",   "mlb")
        // 5대 리그
        case "ENG.1":          return ("soccer", "eng.1")
        case "ESP.1":          return ("soccer", "esp.1")
        case "GER.1":          return ("soccer", "ger.1")
        case "ITA.1":          return ("soccer", "ita.1")
        case "FRA.1":          return ("soccer", "fra.1")
        case "USA.1":          return ("soccer", "usa.1")
        // 국내 컵 대회
        case "ENG.FA":              return ("soccer", "eng.fa")
        case "ENG.LEAGUE_CUP":      return ("soccer", "eng.league_cup")
        case "ESP.COPA":            return ("soccer", "esp.copa")
        case "GER.DFB":             return ("soccer", "ger.dfb")
        case "ITA.COPPA":           return ("soccer", "ita.coppa")
        case "FRA.COUPE_DE_FRANCE": return ("soccer", "fra.coupe_de_france")
        // 기타 유럽 리그
        case "NED.1":          return ("soccer", "ned.1")
        case "POR.1":          return ("soccer", "por.1")
        case "TUR.1":          return ("soccer", "tur.1")
        case "BEL.1":          return ("soccer", "bel.1")
        case "GRE.1":          return ("soccer", "gre.1")
        case "CZE.1":          return ("soccer", "cze.1")
        case "DEN.1":          return ("soccer", "den.1")
        // UEFA 대회
        case "UEFA.CHAMPIONS": return ("soccer", "uefa.champions")
        case "UEFA.EUROPA":    return ("soccer", "uefa.europa")
        case "KBO":            return nil
        default:               return nil
        }
    }
}
