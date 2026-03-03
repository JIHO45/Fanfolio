//
//  ESPNPlayerService.swift
//  Fanfolio
//
//  Created by 박지호 on 2/24/26.
//
//  ESPN 비공식 Site API를 활용해 팀 로스터와 선수/드라이버/파이터 헤드샷을 제공합니다.
//
//  ■ 팀 종목 (NFL·NBA·MLB·NHL·축구·F1)
//    https://site.api.espn.com/apis/site/v2/sports/{sport}/{league}/teams/{teamId}/roster
//
//  ■ 개인 종목 (UFC·ATP·WTA·PGA) — 스코어보드에서 현재 대회 선수 추출
//    https://site.api.espn.com/apis/site/v2/sports/{sport}/{league}/scoreboard
//    → events[].competitions[].competitors[].id  (ESPN 선수 ID)
//    → 헤드샷: https://a.espncdn.com/i/headshots/{sport}/players/full/{id}.png
//

import Foundation
import os.log

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

// MARK: - 리그 분류

/// 스코어보드 기반으로 선수를 가져오는 개인 종목 리그 코드
private let individualLeagues: Set<String> = ["UFC", "ATP", "WTA", "PGA"]

extension String {
    /// ESPN master JSON의 fake ID 여부 확인 ("kbo_1", "kleague_2" 등)
    var isESPNFakeID: Bool { contains("_") }
}

// MARK: - ESPN API 응답 디코딩 (내부 전용)

private struct ESPNRosterResponse: Decodable, Sendable {
    let athletes: [ESPNPositionGroup]
}
private struct ESPNPositionGroup: Decodable, Sendable {
    let items: [ESPNAthleteRaw]
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
private struct ESPNHeadshotRaw: Decodable, Sendable  { let href: String }

/// 스코어보드 응답 (개인 종목)
private struct ESPNScoreboardResponse: Decodable, Sendable {
    let events: [ESPNScoreEvent]
}
private struct ESPNScoreEvent: Decodable, Sendable {
    let competitions: [ESPNScoreCompetition]
}
private struct ESPNScoreCompetition: Decodable, Sendable {
    let competitors: [ESPNScoreCompetitor]
}
private struct ESPNScoreCompetitor: Decodable, Sendable {
    let id: String
    let athlete: ESPNScoreAthlete?
}
private struct ESPNScoreAthlete: Decodable, Sendable {
    let displayName: String?
    let shortName: String?
    let flag: ESPNAthleteFlag?
}
private struct ESPNAthleteFlag: Decodable, Sendable {
    let alt: String?
}

// MARK: - ESPN 선수 서비스

actor ESPNPlayerService {

    static let shared = ESPNPlayerService()
    private init() {}

    /// TTL 캐시: 로스터 30분 / 개인 종목 스코어보드 10분
    private let rosterCache = TTLCache<String, [ESPNAthlete]>(ttl: 1800)
    private let leagueCache  = TTLCache<String, [ESPNAthlete]>(ttl: 600)

    // MARK: - 팀 종목: 로스터 조회

    /// ESPN 팀 ID로 로스터를 가져옵니다. (NFL·NBA·MLB·NHL·축구·F1)
    func fetchRoster(teamESPNId: String, leagueCode: String) async -> [ESPNAthlete] {
        let key = "roster:\(leagueCode):\(teamESPNId)"
        if let hit = rosterCache.get(key) { return hit }

        guard let (sport, league) = teamSportPath(for: leagueCode),
              let url = URL(string:
                "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(league)/teams/\(teamESPNId)/roster")
        else { return [] }

        Logger.api.info("ESPN → roster: \(leagueCode)/\(teamESPNId)")

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response  = try JSONDecoder().decode(ESPNRosterResponse.self, from: data)
            let athletes  = response.athletes.flatMap { $0.items }.compactMap { $0.toAthlete() }
            rosterCache.set(key, value: athletes)
            Logger.api.info("ESPN roster loaded: \(athletes.count) athletes for \(leagueCode)/\(teamESPNId)")
            return athletes
        } catch {
            Logger.api.error("ESPN roster fetch failed (\(leagueCode)/\(teamESPNId)): \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - 개인 종목: 스코어보드에서 현재 선수 추출

    /// 스코어보드의 현재 이벤트에서 출전 선수를 가져옵니다.
    /// (UFC·ATP·WTA·PGA — 대회 없는 기간에는 빈 배열 반환)
    func fetchLeagueAthletes(leagueCode: String) async -> [ESPNAthlete] {
        let key = "league:\(leagueCode)"
        if let hit = leagueCache.get(key) { return hit }

        guard let (sport, league) = individualSportPath(for: leagueCode),
              let url = URL(string:
                "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(league)/scoreboard")
        else { return [] }

        Logger.api.info("ESPN → scoreboard: \(leagueCode)")

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response  = try JSONDecoder().decode(ESPNScoreboardResponse.self, from: data)

            var seen = Set<String>()
            var athletes: [ESPNAthlete] = []

            for event in response.events {
                for comp in event.competitions {
                    for competitor in comp.competitors {
                        guard !competitor.id.isEmpty,
                              !seen.contains(competitor.id) else { continue }
                        seen.insert(competitor.id)

                        let name = competitor.athlete?.displayName ?? competitor.athlete?.shortName ?? ""
                        guard !name.isEmpty else { continue }

                        let headshotURL = "https://a.espncdn.com/i/headshots/\(sport)/players/full/\(competitor.id).png"

                        athletes.append(ESPNAthlete(
                            id: competitor.id,
                            name: name,
                            position: nil,
                            jerseyNumber: nil,
                            headshotURL: headshotURL
                        ))
                    }
                }
            }

            leagueCache.set(key, value: athletes)
            Logger.api.info("ESPN scoreboard loaded: \(athletes.count) athletes for \(leagueCode)")
            return athletes
        } catch {
            Logger.api.error("ESPN scoreboard fetch failed (\(leagueCode)): \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - 캐시 초기화

    func clearCache() {
        rosterCache.removeAll()
        leagueCache.removeAll()
    }

    func purgeExpiredCache() {
        rosterCache.purgeExpired()
        leagueCache.purgeExpired()
    }

    // MARK: - 분류 헬퍼

    /// 해당 리그 코드가 개인 종목인지 여부 (스코어보드 방식 사용)
    nonisolated func isIndividualSport(_ leagueCode: String) -> Bool {
        individualLeagues.contains(leagueCode)
    }

    // MARK: - ESPN API 경로 매핑

    private func teamSportPath(for code: String) -> (String, String)? {
        switch code {
        case "NFL":  return ("football",   "nfl")
        case "NBA":  return ("basketball", "nba")
        case "MLB":  return ("baseball",   "mlb")
        case "NHL":  return ("hockey",     "nhl")
        case "ENG.1":          return ("soccer", "eng.1")
        case "ESP.1":          return ("soccer", "esp.1")
        case "GER.1":          return ("soccer", "ger.1")
        case "ITA.1":          return ("soccer", "ita.1")
        case "FRA.1":          return ("soccer", "fra.1")
        case "USA.1":          return ("soccer", "usa.1")
        case "UEFA.CHAMPIONS": return ("soccer", "uefa.champions")
        case "F1":             return ("racing", "f1")
        case "KBO", "KOR.1":   return nil
        default:               return nil
        }
    }

    private func individualSportPath(for code: String) -> (String, String)? {
        switch code {
        case "UFC": return ("mma",    "ufc")
        case "ATP": return ("tennis", "atp")
        case "WTA": return ("tennis", "wta")
        case "PGA": return ("golf",   "pga")
        default:    return nil
        }
    }
}
