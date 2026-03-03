//
//  LiveScore.swift
//  Fanfolio
//

import Foundation

// MARK: - 실시간 경기 정보 (API-Sports 응답 통합)

struct LiveFixture: Identifiable, Codable {
    let id: Int
    let homeTeam: LiveTeamInfo
    let awayTeam: LiveTeamInfo
    let score: LiveScore
    let status: LiveFixtureStatus
    let league: LiveLeagueInfo
    let startTime: Date?
    let periods: [PeriodScore]
    
    var isLive: Bool { status.isLive }
    var isUpcoming: Bool { status.isUpcoming }
}

struct LiveTeamInfo: Codable {
    let id: Int
    let name: String
    let logoURL: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case logoURL = "logo"
    }
}

struct LiveScore: Codable {
    let home: Int?
    let away: Int?
}

struct LiveFixtureStatus: Codable {
    let short: String  // "NS", "1Q", "HT", "FT", "LIVE" etc.
    let elapsed: Int?  // 경과 시간 (분 또는 이닝)
    let period: String? // 현재 쿼터/이닝/세트
    
    var isLive: Bool {
        let liveStatuses = ["1Q","2Q","3Q","4Q","OT","HT","1H","2H","LIVE","IN_PLAY","1ST","2ND","3RD","4TH","5TH","6TH","7TH","8TH","9TH"]
        return liveStatuses.contains(short)
    }
    
    var isUpcoming: Bool { short == "NS" || short == "TBD" }
    var isFinished: Bool { short == "FT" || short == "AOT" || short == "F" || short == "Final" }
    
    /// 화면 표시용 텍스트
    var displayText: String {
        switch short {
        case "NS": return "예정"
        case "1Q": return "1쿼터"
        case "2Q": return "2쿼터"
        case "3Q": return "3쿼터"
        case "4Q": return "4쿼터"
        case "OT": return "연장"
        case "HT": return "하프타임"
        case "1H": return "전반"
        case "2H": return "후반"
        case "FT", "F": return "종료"
        case "AOT": return "연장 종료"
        default:
            if let e = elapsed { return "\(e)'" }
            return short
        }
    }
}

struct LiveLeagueInfo: Codable {
    let id: Int
    let name: String
    let season: Int?
}

/// 쿼터/이닝/세트별 점수
struct PeriodScore: Identifiable, Codable {
    var id: String { period }
    let period: String   // "1Q", "2Q", "1회", "SET1" etc.
    let home: Int?
    let away: Int?
}

// MARK: - 종목별 피리어드 표기 헬퍼

extension SportType {
    /// 종목에 맞는 피리어드 레이블 생성
    func periodLabels(count: Int) -> [String] {
        switch self {
        case .americanFootball:
            let base = ["1Q","2Q","3Q","4Q"]
            return count > 4 ? base + (1...(count-4)).map { "OT\($0)" } : Array(base.prefix(count))
        case .basketball:
            let base = ["1Q","2Q","3Q","4Q"]
            return count > 4 ? base + (1...(count-4)).map { "OT\($0)" } : Array(base.prefix(count))
        case .soccer:
            return count > 2 ? ["전반","후반"] + (1...(count-2)).map { "연장\($0)" } : ["전반","후반"]
        case .baseball:
            return (1...max(9,count)).map { "\($0)회" }
        case .volleyball:
            return (1...max(5,count)).map { "\($0)세트" }
        case .hockey:
            let base = ["1P","2P","3P"]
            return count > 3 ? base + (1...(count-3)).map { "OT\($0)" } : Array(base.prefix(count))
        case .tennis:
            return (1...max(3,count)).map { "\($0)세트" }
        case .racing:
            return ["레이스"]
        default:
            return (1...count).map { "\($0)" }
        }
    }
}

// MARK: - API-Sports 응답 파싱용 원시 구조체

/// NFL API-Sports 응답
struct APISportsNFLResponse: Codable {
    let response: [APISportsNFLGame]
}

struct APISportsNFLGame: Codable {
    let game: APISportsNFLGameInfo
    let teams: APISportsNFLTeams
    let scores: APISportsNFLScores
}

struct APISportsNFLGameInfo: Codable {
    let id: Int
    let stage: String?
    let date: APISportsDate
    let status: APISportsNFLStatus
}

struct APISportsDate: Codable {
    let date: String?
    let time: String?
    let timestamp: Int?
}

struct APISportsNFLStatus: Codable {
    let short: String
    let timer: String?
    let quarter: Int?
}

struct APISportsNFLTeams: Codable {
    let home: APISportsTeam
    let away: APISportsTeam
}

struct APISportsTeam: Codable {
    let id: Int
    let name: String
    let logo: String?
}

struct APISportsNFLScores: Codable {
    let home: APISportsNFLTeamScore
    let away: APISportsNFLTeamScore
}

struct APISportsNFLTeamScore: Codable {
    let quarter_1: Int?
    let quarter_2: Int?
    let quarter_3: Int?
    let quarter_4: Int?
    let overtime: Int?
    let total: Int?
}

/// 축구 (Football) API-Sports 응답
struct APISportsSoccerResponse: Codable {
    let response: [APISportsSoccerFixture]
}

struct APISportsSoccerFixture: Codable {
    let fixture: APISportsSoccerFixtureInfo
    let league: APISportsSoccerLeague
    let teams: APISportsSoccerTeams
    let goals: APISportsSoccerGoals
    let score: APISportsSoccerScore
}

struct APISportsSoccerFixtureInfo: Codable {
    let id: Int
    let date: String?
    let timestamp: Int?
    let status: APISportsSoccerStatus
}

struct APISportsSoccerStatus: Codable {
    let short: String
    let elapsed: Int?
}

struct APISportsSoccerLeague: Codable {
    let id: Int
    let name: String
    let season: Int?
}

struct APISportsSoccerTeams: Codable {
    let home: APISportsTeam
    let away: APISportsTeam
}

struct APISportsSoccerGoals: Codable {
    let home: Int?
    let away: Int?
}

struct APISportsSoccerScore: Codable {
    let halftime: APISportsSoccerGoals
    let fulltime: APISportsSoccerGoals
}
