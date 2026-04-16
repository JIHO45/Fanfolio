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

    /// UI 표시용 로컬라이즈된 리그 이름 (`Localizable` 키 `league.<id>`)
    var localizedDisplayName: String {
        Bundle.main.localizedString(
            forKey: "league.\(id)",
            value: Self.englishDisplayName(forLeagueId: id),
            table: nil
        )
    }

    /// 리그 선택 ID → 영문 기본 표기 (`league.<id>` 폴백). 새 리그는 여기와 `supportedLeagues`만 추가합니다.
    private static func englishDisplayName(forLeagueId id: String) -> String {
        switch id {
        case "mlb":        return "MLB"
        case "kbo":        return "KBO"
        case "epl":        return "Premier League"
        case "laliga":     return "La Liga"
        case "bundesliga": return "Bundesliga"
        case "seriea":     return "Serie A"
        case "ligue1":     return "Ligue 1"
        case "mls":        return "MLS"
        case "eredivisie": return "Eredivisie"
        case "primeiralg": return "Primeira Liga"
        case "superlig":   return "Süper Lig"
        case "proleague":  return "Belgian Pro League"
        case "superleagr": return "Super League Greece"
        case "firstliga":  return "Czech First League"
        case "superliga":  return "Danish Superliga"
        case "nba":        return "NBA"
        case "nfl":        return "NFL"
        default:           return id
        }
    }

    /// 리그 코드 → 영문 기본 표기 (`Localizable` 키 `league.code.<code>`)
    private static func englishLeagueLabel(for code: String) -> String {
        switch code {
        case "ENG.1":               return "Premier League"
        case "ESP.1":               return "La Liga"
        case "GER.1":               return "Bundesliga"
        case "ITA.1":               return "Serie A"
        case "FRA.1":               return "Ligue 1"
        case "USA.1":               return "MLS"
        case "MLB":                 return "MLB"
        case "KBO":                 return "KBO"
        case "NBA":                 return "NBA"
        case "NFL":                 return "NFL"
        case "NED.1":               return "Eredivisie"
        case "POR.1":               return "Primeira Liga"
        case "TUR.1":               return "Süper Lig"
        case "BEL.1":               return "Belgian Pro League"
        case "GRE.1":               return "Super League Greece"
        case "CZE.1":               return "Czech First League"
        case "DEN.1":               return "Danish Superliga"
        case "ENG.FA":              return "FA Cup"
        case "ENG.LEAGUE_CUP":      return "League Cup"
        case "ESP.COPA":            return "Copa del Rey"
        case "GER.DFB":             return "DFB-Pokal"
        case "ITA.COPPA":           return "Coppa Italia"
        case "FRA.COUPE_DE_FRANCE": return "Coupe de France"
        case "UEFA.CHAMPIONS":      return "Champions League"
        case "UEFA.EUROPA":         return "Europa League"
        default:                    return code
        }
    }

    /// 평문 `String`이 필요할 때 (경기 목록·메타데이터)
    static func displayNameString(for code: String) -> String {
        let key = "league.code.\(code)"
        let fallback = englishLeagueLabel(for: code)
        return Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
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
                LeagueInfo(id: "epl",        code: "ENG.1",  displayName: "Premier League"),
                LeagueInfo(id: "laliga",     code: "ESP.1",  displayName: "La Liga"),
                LeagueInfo(id: "bundesliga", code: "GER.1",  displayName: "Bundesliga"),
                LeagueInfo(id: "seriea",     code: "ITA.1",  displayName: "Serie A"),
                LeagueInfo(id: "ligue1",     code: "FRA.1",  displayName: "Ligue 1"),
                LeagueInfo(id: "mls",        code: "USA.1",  displayName: "MLS"),
                LeagueInfo(id: "eredivisie", code: "NED.1",  displayName: "Eredivisie"),
                LeagueInfo(id: "primeiralg", code: "POR.1",  displayName: "Primeira Liga"),
                LeagueInfo(id: "superlig",   code: "TUR.1",  displayName: "Süper Lig"),
                LeagueInfo(id: "proleague",  code: "BEL.1",  displayName: "Belgian Pro League"),
                LeagueInfo(id: "superleagr", code: "GRE.1",  displayName: "Super League Greece"),
                LeagueInfo(id: "firstliga",  code: "CZE.1",  displayName: "Czech First League"),
                LeagueInfo(id: "superliga",  code: "DEN.1",  displayName: "Danish Superliga"),
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
        case .baseball:         return ["MLB": 1, "KBO": 5]
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
