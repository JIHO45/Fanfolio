//
//  ESPNTeamsData.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import Foundation
import SwiftUI

// MARK: - JSON 모델
struct ESPNTeam: Codable, Identifiable {
    let id: String
    let name_en: String
    let name_kr: String?
    let logo_url: String
    let color: String?
    let alternate_color: String?
    let league: String
}

// MARK: - 리그 정보 (종목별 매핑)
struct LeagueInfo: Identifiable {
    let id: String
    let code: String
    let displayName: String

    /// UI 표시용 로컬라이즈된 리그 이름
    var localizedDisplayName: String {
        Bundle.main.localizedString(forKey: "league.\(id)", value: displayName, table: nil)
    }

    /// 리그 코드 → 기본 표기 문자열(로컬라이즈 키로도 사용). 새 리그는 여기만 추가합니다.
    private static func leagueLabel(for code: String) -> String {
        switch code {
        case "ENG.1":               return "프리미어리그"
        case "ESP.1":               return "라리가"
        case "GER.1":               return "분데스리가"
        case "ITA.1":               return "세리에 A"
        case "FRA.1":               return "리그 1"
        case "USA.1":               return "MLS"
        case "MLB":                 return "MLB"
        case "KBO":                 return "KBO"
        case "NBA":                 return "NBA"
        case "NFL":                 return "NFL"
        case "NED.1":               return "에레디비시"
        case "POR.1":               return "프리메이라리가"
        case "TUR.1":               return "쉬페르리그"
        case "BEL.1":               return "주필러 프로리그"
        case "GRE.1":               return "슈퍼리그 그리스"
        case "CZE.1":               return "체코 포르스트리가"
        case "DEN.1":               return "수페르리가"
        case "ENG.FA":              return "FA컵"
        case "ENG.LEAGUE_CUP":      return "리그컵"
        case "ESP.COPA":            return "코파 델 레이"
        case "GER.DFB":             return "DFB-포칼"
        case "ITA.COPPA":           return "코파 이탈리아"
        case "FRA.COUPE_DE_FRANCE": return "쿠프 드 프랑스"
        case "UEFA.CHAMPIONS":      return "챔피언스리그"
        case "UEFA.EUROPA":         return "유로파리그"
        default:                    return code
        }
    }

    /// `Text` 등 SwiftUI용
    static func displayName(for code: String) -> LocalizedStringKey {
        LocalizedStringKey(leagueLabel(for: code))
    }

    /// 평문 `String`이 필요할 때 (예: `LiveFixture` 메타데이터)
    static func displayNameString(for code: String) -> String {
        let label = leagueLabel(for: code)
        return Bundle.main.localizedString(forKey: label, value: label, table: nil)
    }
}

// MARK: - 종목별 리그 매핑
extension SportType {
    /// 팀 선택이 필요 없는 종목
    var requiresTeamSelection: Bool {
        switch self {
        case .other: return false
        default: return true
        }
    }

    /// 팀 선택이 없는 종목의 폴더 이름 힌트
    var noTeamNameHint: LocalizedStringKey {
        switch self {
        case .other: return "예: 테니스 직관, 복싱 경기"
        default:     return "예: LG 트윈스, FC서울"
        }
    }

    /// 이 종목에 해당하는 리그 목록 (JSON의 league 필드와 매칭)
    var supportedLeagues: [LeagueInfo] {
        switch self {
        case .baseball:
            return [
                LeagueInfo(id: "mlb",  code: "MLB", displayName: "MLB"),
                LeagueInfo(id: "kbo",  code: "KBO", displayName: "KBO"),
            ]
        case .soccer:
            return [
                LeagueInfo(id: "epl",        code: "ENG.1",  displayName: "EPL"),
                LeagueInfo(id: "laliga",     code: "ESP.1",  displayName: "라리가"),
                LeagueInfo(id: "bundesliga", code: "GER.1",  displayName: "분데스리가"),
                LeagueInfo(id: "seriea",     code: "ITA.1",  displayName: "세리에 A"),
                LeagueInfo(id: "ligue1",     code: "FRA.1",  displayName: "리그 1"),
                LeagueInfo(id: "mls",        code: "USA.1",  displayName: "MLS"),
                LeagueInfo(id: "eredivisie", code: "NED.1",  displayName: "에레디비시"),
                LeagueInfo(id: "primeiralg", code: "POR.1",  displayName: "프리메이라리가"),
                LeagueInfo(id: "superlig",   code: "TUR.1",  displayName: "쉬페르리그"),
                LeagueInfo(id: "proleague",  code: "BEL.1",  displayName: "주필러 프로리그"),
                LeagueInfo(id: "superleagr", code: "GRE.1",  displayName: "슈퍼리그 그리스"),
                LeagueInfo(id: "firstliga",  code: "CZE.1",  displayName: "체코 포르스트리가"),
                LeagueInfo(id: "superliga",  code: "DEN.1",  displayName: "수페르리가"),
            ]
        case .basketball:
            return [LeagueInfo(id: "nba", code: "NBA", displayName: "NBA")]
        case .americanFootball:
            return [LeagueInfo(id: "nfl", code: "NFL", displayName: "NFL")]
        case .other:
            return []
        }
    }
    
    /// API-Sports 리그 ID 매핑
    var apiSportsLeagueIDs: [String: Int] {
        switch self {
        case .americanFootball: return ["NFL": 1]
        case .basketball:       return ["NBA": 12]
        case .baseball:         return ["MLB": 1, "KBO": 10]
        case .soccer:           return [
            "ENG.1": 39, "ESP.1": 140, "GER.1": 78, "ITA.1": 135, "FRA.1": 61, "USA.1": 253,
            "NED.1": 88, "POR.1": 94, "TUR.1": 203, "BEL.1": 144, "GRE.1": 197, "CZE.1": 345, "DEN.1": 119,
        ]
        case .other:            return [:]
        }
    }
}

// MARK: - Hex → Color 변환
extension Color {
    /// hex 문자열 (예: "aa182c") → Color
    static func from(hex: String?) -> Color? {
        guard let hex = hex?.trimmingCharacters(in: CharacterSet(charactersIn: "#")),
              hex.count == 6 else { return nil }
        let r = Int(hex.prefix(2), radix: 16).map { Double($0) / 255 } ?? 0
        let g = Int(hex.dropFirst(2).prefix(2), radix: 16).map { Double($0) / 255 } ?? 0
        let b = Int(hex.suffix(2), radix: 16).map { Double($0) / 255 } ?? 0
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - 팀 그라디언트
extension ESPNTeam {
    var gradientColors: [Color] {
        let primary = Color.from(hex: color) ?? Color.gray
        let secondary = Color.from(hex: alternate_color) ?? primary.opacity(0.7)
        return [primary, secondary]
    }
}

// MARK: - 팀 데이터 로더
enum ESPNTeamsLoader {
    private static var cachedTeams: [ESPNTeam]?
    
    static func loadTeams() -> [ESPNTeam] {
        if let cached = cachedTeams { return cached }
        
        guard let url = Bundle.main.url(forResource: "espn_teams_master", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let teams = try? JSONDecoder().decode([ESPNTeam].self, from: data) else {
            return []
        }
        
        cachedTeams = teams
        return teams
    }
    
    static func teams(for leagueCode: String) -> [ESPNTeam] {
        loadTeams().filter { $0.league == leagueCode }
    }
    
    /// 팀 이름으로 팀 찾기 (리그가 있으면 해당 리그 내에서만 검색)
    /// name_en(영문) 또는 name_kr(한국어) 모두 매칭
    static func team(name: String, leagueCode: String?) -> ESPNTeam? {
        let list = leagueCode.map { teams(for: $0) } ?? loadTeams()
        return list.first { $0.name_en == name || $0.name_kr == name }
    }
}

// MARK: - 폴더 그라디언트
extension SportsFanFolder {
    var gradientColors: [Color] {
        let primary = Color.from(hex: teamColor) ?? Color.gray
        let secondary = Color.from(hex: teamAlternateColor) ?? primary.opacity(0.7)
        return [primary, secondary]
    }
}
