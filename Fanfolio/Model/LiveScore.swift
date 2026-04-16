//
//  LiveScore.swift
//  Fanfolio
//

import Foundation

// MARK: - String Catalog (런타임 키)

/// `LocalizedStringResource(stringLiteral:)` 동적 키는 카탈로그 매칭이 실패해 기본(ko)만 나오는 경우가 있어,
/// 언어별 `lproj` + `NSLocalizedString`으로 `Localizable`을 조회합니다.
private enum LiveScoreCatalogL10n {
    static func string(_ key: String, locale: Locale) -> String {
        let langCode = languageCode(for: locale)
        if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: "")
        }
        return NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "")
    }

    private static func languageCode(for locale: Locale) -> String {
        if let c = locale.language.languageCode?.identifier, c != "und" { return c }
        return Bundle.main.preferredLocalizations.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
            ?? "en"
    }
}

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
        if liveStatuses.contains(short) { return true }
        // ESPN MLB: `ESPNPlayerService.espnPeriodShort`가 이닝을 "7TH"가 아니라 로컬라이즈 문자열만 넣음(예: ko "7회", en "7").
        if short.hasSuffix("회"), short != "회" { return true }
        if let inning = Int(short), (1...18).contains(inning) { return true }
        // API-Sports KBO: "IN1"~"IN18" 형식 (예: "IN3" = 3이닝 진행 중)
        if short.hasPrefix("IN"), let n = Int(short.dropFirst(2)), (1...18).contains(n) { return true }
        return false
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
    
    /// 화면 표시용 텍스트 (앱 언어·지역 설정에 맞게 `Localizable`에서 로드)
    var displayText: String { displayText(for: .current) }

    func displayText(for locale: Locale) -> String {
        switch short {
        case "NS":
            return Self.localized("live.fixture.status.ns", locale: locale)
        case "1Q":
            return Self.localized("live.fixture.status.q1", locale: locale)
        case "2Q":
            return Self.localized("live.fixture.status.q2", locale: locale)
        case "3Q":
            return Self.localized("live.fixture.status.q3", locale: locale)
        case "4Q":
            return Self.localized("live.fixture.status.q4", locale: locale)
        case "OT":
            return Self.localized("live.fixture.status.ot", locale: locale)
        case "HT":
            return Self.localized("live.fixture.status.ht", locale: locale)
        case "1H":
            return Self.localized("scoreboard.period.firstHalf", locale: locale)
        case "2H":
            return Self.localized("scoreboard.period.secondHalf", locale: locale)
        case "FT", "F":
            return Self.localized("live.fixture.status.ft", locale: locale)
        case "AOT":
            return Self.localized("live.fixture.status.aot", locale: locale)
        default:
            // 야구 이닝(로컬 "%lld회" / 숫자만): 축구용 경과 분(′)은 MLB에 부적합
            if short.hasSuffix("회"), short != "회" { return short }
            if let n = Int(short), (1...18).contains(n) { return short }
            // API-Sports KBO: "IN1"~"IN18" — 이닝 라벨은 스코어보드와 동일 포맷 키 사용
            if short.hasPrefix("IN"), let n = Int(short.dropFirst(2)), (1...18).contains(n) {
                let format = Self.localized("scoreboard.inning.labelFormat", locale: locale)
                return String(format: format, locale: locale, Int64(n))
            }
            if let e = elapsed {
                let format = Self.localized("live.fixture.status.elapsedFormat", locale: locale)
                return String(format: format, locale: locale, Int64(e))
            }
            return short
        }
    }

    private static func localized(_ key: String, locale: Locale) -> String {
        LiveScoreCatalogL10n.string(key, locale: locale)
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
    /// 종목에 맞는 피리어드 레이블 생성 (`locale` 기준으로 `Localizable`에서 전반·후반·이닝·연장 등 로드)
    func periodLabels(count: Int, locale: Locale = .current) -> [String] {
        switch self {
        case .americanFootball:
            let base = ["1Q","2Q","3Q","4Q"]
            return count > 4 ? base + (1...(count-4)).map { "OT\($0)" } : Array(base.prefix(count))
        case .basketball:
            let base = ["1Q","2Q","3Q","4Q"]
            return count > 4 ? base + (1...(count-4)).map { "OT\($0)" } : Array(base.prefix(count))
        case .soccer:
            let first = Self.localizedCatalog("scoreboard.period.firstHalf", locale: locale)
            let second = Self.localizedCatalog("scoreboard.period.secondHalf", locale: locale)
            let halves = [first, second]
            guard count > 2 else { return halves }
            let otFormat = Self.localizedCatalog("live.fixture.periodLabels.soccer.otFormat", locale: locale)
            let extras = (1...(count - 2)).map { i in
                String(format: otFormat, locale: locale, Int64(i))
            }
            return halves + extras
        case .baseball:
            let hi = max(9, count)
            let format = Self.localizedCatalog("scoreboard.inning.labelFormat", locale: locale)
            return (1...hi).map { inning in
                String(format: format, locale: locale, Int64(inning))
            }
        default:
            return (1...count).map { "\($0)" }
        }
    }

    private static func localizedCatalog(_ key: String, locale: Locale) -> String {
        LiveScoreCatalogL10n.string(key, locale: locale)
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
    /// 스케줄·스코어보드 공통. TBD·누락·비정상 타입 시 nil (경기 전체 파싱은 유지).
    let venue: ESPNCompetitionVenue?

    enum CodingKeys: String, CodingKey {
        case status, competitors, venue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(ESPNLiveCompetitionStatus.self, forKey: .status)
        competitors = try container.decode([ESPNLiveCompetitor].self, forKey: .competitors)
        venue = try? container.decode(ESPNCompetitionVenue.self, forKey: .venue)
    }
}

// MARK: - ESPN 경기장 (지도 검색용)

struct ESPNCompetitionVenue: Decodable, Sendable {
    let id: String?
    let fullName: String?
    let displayName: String?
    let shortName: String?
    let address: ESPNCompetitionVenueAddress?
}

struct ESPNCompetitionVenueAddress: Decodable, Sendable {
    let city: String?
    let state: String?
    let country: String?
}

enum ESPNCompetitionVenueGeocodeQuery {
    /// `venue` → MKLocalSearch에 넣을 최선의 문자열. 불충분하면 nil(휴리스틱으로 폴백).
    static func mkLocalSearchQuery(from venue: ESPNCompetitionVenue?) -> String? {
        guard let venue else { return nil }
        let nameRaw = venue.fullName ?? venue.displayName ?? venue.shortName
        guard let name = nameRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        guard let address = venue.address else { return name }
        let city = address.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !city.isEmpty else { return name }
        let state = address.state?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !state.isEmpty {
            return "\(name), \(city), \(state)"
        }
        let country = address.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !country.isEmpty {
            return "\(name), \(city), \(Self.readableCountry(country))"
        }
        return "\(name), \(city)"
    }

    /// ESPN이 내려주는 ISO·약어 코드를 Apple MKLocalSearch가 잘 인식하는 국가명으로 변환합니다.
    /// 매핑에 없는 코드는 원본 그대로 사용합니다.
    private static func readableCountry(_ raw: String) -> String {
        switch raw.uppercased() {
        case "ENG":            return "England"
        case "GBR", "GB":     return "United Kingdom"
        case "SCO":            return "Scotland"
        case "WAL":            return "Wales"
        case "NIR":            return "Northern Ireland"
        case "ESP":            return "Spain"
        case "GER", "DEU":    return "Germany"
        case "ITA":            return "Italy"
        case "FRA":            return "France"
        case "NED", "NLD":    return "Netherlands"
        case "POR":            return "Portugal"
        case "TUR":            return "Turkey"
        case "BEL":            return "Belgium"
        case "GRE":            return "Greece"
        case "CZE":            return "Czech Republic"
        case "DEN", "DNK":    return "Denmark"
        case "USA", "US":     return "USA"
        case "MEX":            return "Mexico"
        case "BRA":            return "Brazil"
        case "ARG":            return "Argentina"
        case "JPN", "JP":     return "Japan"
        case "KOR":            return "South Korea"
        case "AUS":            return "Australia"
        case "CAN":            return "Canada"
        default:               return raw
        }
    }
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
    let inning_1: Int?
    let inning_2: Int?
    let inning_3: Int?
    let inning_4: Int?
    let inning_5: Int?
    let inning_6: Int?
    let inning_7: Int?
    let inning_8: Int?
    let inning_9: Int?
    let extra_innings: Int?
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
