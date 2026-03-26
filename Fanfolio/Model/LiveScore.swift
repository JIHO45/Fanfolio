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
    /// API-Sports 축구 등에서 쓰는 종료 코드 포함 (진행 중으로 오인 방지)
    var isFinished: Bool {
        switch short {
        case "FT", "AOT", "F", "Final", "PEN", "AET", "AWD", "WO":
            return true
        default:
            return false
        }
    }
    
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
            if let e = elapsed {
                return "\(e)′"
            }
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

// MARK: - ESPN 팀 스포츠 스코어보드 디코딩 구조체
// https://site.api.espn.com/apis/site/v2/sports/{sport}/{league}/scoreboard

struct ESPNLiveScoreboardResponse: Decodable {
    let events: [ESPNLiveEvent]
}

struct ESPNLiveEvent: Decodable {
    let id: String
    let name: String?
    let date: String?
    let competitions: [ESPNLiveCompetition]
}

struct ESPNLiveCompetition: Decodable {
    let status: ESPNLiveCompetitionStatus
    let competitors: [ESPNLiveCompetitor]
}

struct ESPNLiveCompetitionStatus: Decodable {
    let clock: Double?
    let displayClock: String?
    let period: Int?
    let type: ESPNLiveStatusType
}

struct ESPNLiveStatusType: Decodable {
    let name: String        // "STATUS_SCHEDULED", "STATUS_IN_PROGRESS", "STATUS_FINAL" 등
    let state: String?      // "pre", "in", "post" — 스케줄 API에서 누락될 수 있음
    let completed: Bool?    // 예정 경기는 이 값 자체가 없을 수 있음
    let shortDetail: String?
}

// score가 "24"(String) 또는 {"value":0,"displayValue":"0"}(Dictionary)로 혼용되어 내려오므로 보조 구조체로 방어
struct ESPNScoreDict: Decodable {
    let value: Double?
    let displayValue: String?
}

struct ESPNLiveCompetitor: Decodable {
    let id: String?
    let homeAway: String?
    var score: String?
    let team: ESPNLiveTeam
    let linescores: [ESPNLiveLineScore]?

    enum CodingKeys: String, CodingKey {
        case id, homeAway, score, team, linescores
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id         = try container.decodeIfPresent(String.self, forKey: .id)
        self.homeAway   = try container.decodeIfPresent(String.self, forKey: .homeAway)
        self.team       = try container.decode(ESPNLiveTeam.self, forKey: .team)
        self.linescores = try container.decodeIfPresent([ESPNLiveLineScore].self, forKey: .linescores)

        // Case A: 라이브/종료 경기 → score가 String으로 내려오는 경우
        if let strScore = try? container.decode(String.self, forKey: .score) {
            self.score = strScore
        // Case B: 예정된 경기 → score가 Dictionary로 내려오는 경우
        } else if let dictScore = try? container.decode(ESPNScoreDict.self, forKey: .score) {
            self.score = dictScore.displayValue ?? dictScore.value.map { String(Int($0)) }
        // Case C: score 키 자체가 없는 경우
        } else {
            self.score = nil
        }
    }
}

struct ESPNLiveTeam: Decodable {
    let id: String
    let displayName: String
    let abbreviation: String?
    let logo: String?
    let color: String?
    let alternateColor: String?
}

struct ESPNLiveLineScore: Decodable {
    let value: Double?
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

// MARK: - API-Sports 야구 경기 일정 응답 (KBO 전용)

struct APISportsBaseballGamesResponse: Codable {
    let response: [APISportsBaseballGame]
}

struct APISportsBaseballGame: Codable {
    let id: Int
    let date: String?
    let teams: APISportsBaseballTeams
    let scores: APISportsBaseballScores?
    let status: APISportsBaseballGameStatus
}

struct APISportsBaseballTeams: Codable {
    let home: APISportsTeam
    let away: APISportsTeam
}

struct APISportsBaseballScores: Codable {
    let home: APISportsBaseballTeamScore?
    let away: APISportsBaseballTeamScore?
}

struct APISportsBaseballTeamScore: Codable {
    let total: Int?
}

struct APISportsBaseballGameStatus: Codable {
    let short: String?
}

// MARK: - 아카이브 경기 상세 (불러오기 피리어드 점수)

extension LiveFixture {
    /// 저장된 `importedPeriodScoresData`가 있을 때만, 라이브 스코어보드 카드와 동일한 레이아웃용 모델을 만듭니다.
    static func fromImportedArchive(
        match: SportsModel,
        sportType: SportType,
        leagueDisplayName: String,
        homeLogoURL: String?,
        awayLogoURL: String?
    ) -> LiveFixture? {
        let periods = match.importedPeriodScores
        guard !periods.isEmpty else { return nil }

        let homeName = match.isHomeGame ? match.team1Display : match.opponentTeam
        let awayName = match.isHomeGame ? match.opponentTeam : match.team1Display
        let homeTotal = match.isHomeGame ? match.myTeamScore : match.opponentScore
        let awayTotal = match.isHomeGame ? match.opponentScore : match.myTeamScore

        let eventHash = match.externalEventID?.hashValue ?? match.title.hashValue
        return LiveFixture(
            id: abs(eventHash),
            homeTeam: LiveTeamInfo(id: 0, name: homeName, logoURL: homeLogoURL),
            awayTeam: LiveTeamInfo(id: 0, name: awayName, logoURL: awayLogoURL),
            score: LiveScore(home: homeTotal, away: awayTotal),
            status: LiveFixtureStatus(short: "FT", elapsed: nil, period: nil),
            league: LiveLeagueInfo(id: 0, name: leagueDisplayName, season: nil),
            startTime: match.date,
            periods: periods
        )
    }
}
