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
}

// MARK: - 종목별 리그 매핑
extension SportType {
    /// 팀 선택이 필요 없는 종목 (테니스, 골프, UFC)
    var requiresTeamSelection: Bool {
        switch self {
        case .tennis, .golf, .mma: return false
        default: return true
        }
    }

    /// 팀 선택이 없는 종목의 폴더 이름 힌트
    var noTeamNameHint: String {
        switch self {
        case .tennis: return "예: 나달, 페더러, 정현"
        case .golf:   return "예: 타이거 우즈, 임성재"
        case .mma:    return "예: UFC 관람, 이정현"
        default:      return "예: LG 트윈스, FC서울"
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
                LeagueInfo(id: "epl",        code: "ENG.1",          displayName: "EPL"),
                LeagueInfo(id: "laliga",     code: "ESP.1",          displayName: "라리가"),
                LeagueInfo(id: "bundesliga", code: "GER.1",          displayName: "분데스리가"),
                LeagueInfo(id: "seriea",     code: "ITA.1",          displayName: "세리에 A"),
                LeagueInfo(id: "ligue1",     code: "FRA.1",          displayName: "리그 1"),
                LeagueInfo(id: "mls",        code: "USA.1",          displayName: "MLS"),
                LeagueInfo(id: "ucl",        code: "UEFA.CHAMPIONS", displayName: "챔피언스리그"),
                LeagueInfo(id: "kleague",    code: "KOR.1",          displayName: "K리그1"),
            ]
        case .basketball:
            return [LeagueInfo(id: "nba", code: "NBA", displayName: "NBA")]
        case .americanFootball:
            return [LeagueInfo(id: "nfl", code: "NFL", displayName: "NFL")]
        case .hockey:
            return [LeagueInfo(id: "nhl", code: "NHL", displayName: "NHL")]
        case .racing:
            return [LeagueInfo(id: "f1",  code: "F1",  displayName: "F1")]
        case .mma:
            return [LeagueInfo(id: "ufc", code: "UFC", displayName: "UFC")]
        case .tennis:
            return [
                LeagueInfo(id: "atp", code: "ATP", displayName: "ATP"),
                LeagueInfo(id: "wta", code: "WTA", displayName: "WTA"),
            ]
        case .golf:
            return [LeagueInfo(id: "pga", code: "PGA", displayName: "PGA Tour")]
        case .volleyball, .eSports, .other:
            return []
        }
    }
    
    /// API-Sports 리그 ID 매핑
    var apiSportsLeagueIDs: [String: Int] {
        switch self {
        case .americanFootball: return ["NFL": 1]
        case .basketball:       return ["NBA": 12]
        case .baseball:         return ["MLB": 1, "KBO": 10]
        case .hockey:           return ["NHL": 57]
        case .soccer:           return ["ENG.1": 39, "ESP.1": 140, "GER.1": 78, "ITA.1": 135, "FRA.1": 61, "USA.1": 253, "UEFA.CHAMPIONS": 2, "KOR.1": 292]
        case .racing:           return ["F1": 1]
        case .volleyball, .mma, .tennis, .golf, .eSports, .other: return [:]
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
