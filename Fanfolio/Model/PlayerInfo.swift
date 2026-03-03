//
//  PlayerInfo.swift
//  Fanfolio
//

import Foundation

// MARK: - 선수 통합 정보 (API-Sports + TheSportsDB 결합)

struct PlayerInfo: Identifiable, Codable {
    let id: Int
    let name: String
    let position: String?
    let number: String?
    /// TheSportsDB strCutout - 투명 배경 이미지 URL (무료 키: 워터마크 있음)
    let cutoutImageURL: String?
    /// 일반 선수 사진 URL (TheSportsDB strThumb)
    let photoURL: String?
    let nationality: String?
    let age: Int?
    let teamName: String?
    var stats: PlayerSeasonStats?
}

// MARK: - 시즌 스텟 (종목 범용)

struct PlayerSeasonStats: Codable {
    // 공통
    let gamesPlayed: Int?
    
    // 미식축구 (NFL)
    let passingTouchdowns: Int?
    let passingYards: Int?
    let rushingTouchdowns: Int?
    let rushingYards: Int?
    let receptions: Int?
    let receivingYards: Int?
    let receivingTouchdowns: Int?
    let sacks: Double?
    let interceptions: Int?
    
    // 축구
    let goals: Int?
    let assists: Int?
    let yellowCards: Int?
    let redCards: Int?
    let minutesPlayed: Int?
    let shotsOnTarget: Int?
    
    // 농구 (NBA)
    let points: Double?
    let rebounds: Double?
    let basketballAssists: Double?
    let steals: Double?
    let blocks: Double?
    
    // 야구
    let battingAvg: Double?
    let homeRuns: Int?
    let rbi: Int?
    let era: Double?
    let strikeouts: Int?
    let wins: Int?
    
    // F1
    let raceWins: Int?
    let podiums: Int?
    let championshipPoints: Int?
    let polePositions: Int?
    
    /// 종목별 핵심 스텟 2~3개를 [(레이블, 값)] 형태로 반환
    func highlights(for sport: SportType) -> [(String, String)] {
        switch sport {
        case .americanFootball:
            var result: [(String, String)] = []
            if let td = passingTouchdowns { result.append(("패스 TD", "\(td)")) }
            if let yds = passingYards { result.append(("패스 야드", "\(yds)")) }
            if let sc = sacks { result.append(("색", String(format: "%.1f", sc))) }
            if let rtd = rushingTouchdowns { result.append(("러시 TD", "\(rtd)")) }
            return Array(result.prefix(3))
        case .soccer:
            var result: [(String, String)] = []
            if let g = goals { result.append(("골", "\(g)")) }
            if let a = assists { result.append(("어시스트", "\(a)")) }
            if let m = minutesPlayed { result.append(("출전 시간", "\(m)'")) }
            return Array(result.prefix(3))
        case .basketball:
            var result: [(String, String)] = []
            if let p = points { result.append(("득점", String(format: "%.1f", p))) }
            if let r = rebounds { result.append(("리바운드", String(format: "%.1f", r))) }
            if let a = basketballAssists { result.append(("어시스트", String(format: "%.1f", a))) }
            return result
        case .baseball:
            var result: [(String, String)] = []
            if let avg = battingAvg { result.append(("타율", String(format: "%.3f", avg))) }
            if let hr = homeRuns { result.append(("홈런", "\(hr)")) }
            if let r = rbi { result.append(("타점", "\(r)")) }
            if let e = era { result.append(("ERA", String(format: "%.2f", e))) }
            return Array(result.prefix(3))
        case .racing:
            var result: [(String, String)] = []
            if let w = raceWins { result.append(("우승", "\(w)")) }
            if let pd = podiums { result.append(("포디움", "\(pd)")) }
            if let pts = championshipPoints { result.append(("포인트", "\(pts)")) }
            return result
        default:
            return []
        }
    }
}

// MARK: - TheSportsDB 응답 파싱용 구조체

struct TheSportsDBPlayerResponse: Codable {
    let player: [TheSportsDBPlayer]?
}

struct TheSportsDBPlayer: Codable {
    let idPlayer: String?
    let strPlayer: String?
    let strPosition: String?
    let strNumber: String?
    let strCutout: String?
    let strThumb: String?
    let strNationality: String?
    let dateBorn: String?
    let strTeam: String?
    
    func toPlayerInfo(apiSportsId: Int? = nil) -> PlayerInfo {
        let id = Int(idPlayer ?? "") ?? (apiSportsId ?? 0)
        let age: Int? = {
            guard let born = dateBorn else { return nil }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: born) else { return nil }
            return Calendar.current.dateComponents([.year], from: date, to: Date()).year
        }()
        return PlayerInfo(
            id: id,
            name: strPlayer ?? "",
            position: strPosition,
            number: strNumber,
            cutoutImageURL: strCutout,
            photoURL: strThumb,
            nationality: strNationality,
            age: age,
            teamName: strTeam,
            stats: nil
        )
    }
}

/// TheSportsDB 팀 전체 선수 응답
struct TheSportsDBSquadResponse: Codable {
    let player: [TheSportsDBPlayer]?
}

// MARK: - API-Sports 선수 스텟 응답 (NFL 예시)

struct APISportsPlayerStatsResponse: Codable {
    let response: [APISportsPlayerStatItem]
}

struct APISportsPlayerStatItem: Codable {
    let player: APISportsPlayerInfo
    let statistics: [APISportsStatistics]
}

struct APISportsPlayerInfo: Codable {
    let id: Int
    let name: String
    let number: Int?
    let position: String?
    let nationality: String?
    let age: Int?
    let photo: String?
}

struct APISportsStatistics: Codable {
    let team: APISportsTeam
    let games: APISportsGamesStats?
    // NFL
    let passing: APISportsPassingStats?
    let rushing: APISportsRushingStats?
    let receiving: APISportsReceivingStats?
    let defensive: APISportsDefensiveStats?
    // Soccer
    let goals: APISportsSoccerPlayerGoals?
    let tackles: APISportsTackles?
    let cards: APISportsCards?
    // Basketball
    let points: APISportsBasketballPoints?
}

struct APISportsGamesStats: Codable {
    let played: Int?
    let started: Int?
    let minutes: Int?
}

struct APISportsPassingStats: Codable {
    let touchdowns: Int?
    let yards: Int?
}

struct APISportsRushingStats: Codable {
    let touchdowns: Int?
    let yards: Int?
}

struct APISportsReceivingStats: Codable {
    let touchdowns: Int?
    let yards: Int?
    let receptions: Int?
}

struct APISportsDefensiveStats: Codable {
    let sacks: Double?
    let interceptions: Int?
}

struct APISportsSoccerPlayerGoals: Codable {
    let total: Int?
    let assists: Int?
}

struct APISportsTackles: Codable {
    let total: Int?
}

struct APISportsCards: Codable {
    let yellow: Int?
    let red: Int?
}

struct APISportsBasketballPoints: Codable {
    let total: Double?
}

// MARK: - API-Sports 팀 로스터 응답

struct APISportsSquadResponse: Codable {
    let response: [APISportsSquadItem]
}

struct APISportsSquadItem: Codable {
    let team: APISportsTeam
    let players: [APISportsSquadPlayer]
}

struct APISportsSquadPlayer: Codable {
    let id: Int
    let name: String
    let age: Int?
    let number: Int?
    let position: String?
    let photo: String?
}
