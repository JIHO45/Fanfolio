//
//  PlayerInfo.swift
//  Fanfolio
//

import Foundation

// MARK: - 선수 통합 정보

struct PlayerInfo: Identifiable, Codable {
    let id: Int
    let name: String
    let position: String?
    let number: String?
    /// 선수 이미지 URL (ESPN CDN 헤드샷 또는 API-Sports 사진)
    let imageURL: String?
    let nationality: String?
    let age: Int?
    let teamName: String?

    init(
        id: Int,
        name: String,
        position: String? = nil,
        number: String? = nil,
        imageURL: String? = nil,
        nationality: String? = nil,
        age: Int? = nil,
        teamName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.number = number
        self.imageURL = imageURL
        self.nationality = nationality
        self.age = age
        self.teamName = teamName
    }
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

// MARK: - 포지션 그룹 (종목별 섹션 구분용)

enum SoccerPosition: Int, Comparable, CaseIterable, Hashable {
    case goalkeeper = 0
    case defender   = 1
    case midfielder = 2
    case forward    = 3

    static func < (lhs: SoccerPosition, rhs: SoccerPosition) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .goalkeeper: return String(localized: "player.position.soccer.goalkeeper", defaultValue: "골키퍼")
        case .defender:   return String(localized: "player.position.soccer.defender", defaultValue: "수비수")
        case .midfielder: return String(localized: "player.position.soccer.midfielder", defaultValue: "미드필더")
        case .forward:    return String(localized: "player.position.soccer.forward", defaultValue: "공격수")
        }
    }

    /// ESPN/API-Sports 포지션 문자열에서 매핑
    static func from(_ raw: String) -> SoccerPosition? {
        let s = raw.uppercased().trimmingCharacters(in: .whitespaces)

        // 골키퍼
        if ["GK", "G", "GOALKEEPER"].contains(s) { return .goalkeeper }
        if s.contains("GOALKEEPER") || s.contains("GOAL KEEPER") { return .goalkeeper }

        // 미드필더 — "Defensive Midfielder"처럼 D로 시작하는 케이스가 있어
        // 수비수 접두어 폴백보다 반드시 먼저 검사해야 함
        if ["MF", "M", "MID", "MIDFIELDER", "CM", "CDM", "CAM", "RM", "LM", "AM", "DM"].contains(s) { return .midfielder }
        if s.contains("MIDFIELD") { return .midfielder }

        // 수비수 — "Centre Back", "Center Back" 등 전체 이름 포함
        if ["DF", "D", "DEF", "DEFENDER", "CB", "RB", "LB", "RWB", "LWB", "CH"].contains(s) { return .defender }
        if s.contains("BACK") || s.contains("DEFENDER") || s == "SWEEPER" || s == "LIBERO" { return .defender }

        // 공격수
        if ["FW", "F", "ATT", "FORWARD", "ATTACKER", "ST", "CF", "RW", "LW"].contains(s) { return .forward }
        if s.contains("FORWARD") || s.contains("STRIKER") || s.contains("WING") || s.contains("ATTACKER") { return .forward }

        // 짧은 약어(3자 이하)에만 첫 글자 폴백 적용
        // 긴 문자열(예: "Manager")이 M 폴백에 걸리는 오분류를 방지
        guard s.count <= 3 else { return nil }
        if s.hasPrefix("G") { return .goalkeeper }
        if s.hasPrefix("D") { return .defender }
        if s.hasPrefix("M") { return .midfielder }
        if s.hasPrefix("F") || s.hasPrefix("A") || s.hasPrefix("S") { return .forward }
        return nil
    }
}

enum BaseballPosition: Int, Comparable, CaseIterable, Hashable {
    case pitcher   = 0
    case catcher   = 1
    case infielder = 2
    case outfielder = 3
    case designatedHitter = 4

    static func < (lhs: BaseballPosition, rhs: BaseballPosition) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .pitcher:           return String(localized: "player.position.baseball.pitcher", defaultValue: "투수")
        case .catcher:           return String(localized: "player.position.baseball.catcher", defaultValue: "포수")
        case .infielder:         return String(localized: "player.position.baseball.infielder", defaultValue: "내야수")
        case .outfielder:        return String(localized: "player.position.baseball.outfielder", defaultValue: "외야수")
        case .designatedHitter:  return String(localized: "player.position.baseball.designatedHitter", defaultValue: "지명타자")
        }
    }

    static func from(_ raw: String) -> BaseballPosition? {
        let s = raw.uppercased()
        if ["SP", "RP", "P", "PITCHER", "STARTING PITCHER", "RELIEF PITCHER", "투수"].contains(s) { return .pitcher }
        if ["C", "CATCHER", "포수"].contains(s) { return .catcher }
        if ["DH", "DESIGNATED HITTER", "지명타자"].contains(s) { return .designatedHitter }
        if ["1B", "2B", "3B", "SS", "IF", "INFIELDER", "FIRST BASE", "SECOND BASE", "THIRD BASE", "SHORTSTOP", "내야수"].contains(s) { return .infielder }
        if ["LF", "CF", "RF", "OF", "OUTFIELDER", "LEFT FIELD", "CENTER FIELD", "RIGHT FIELD", "외야수"].contains(s) { return .outfielder }
        return nil
    }
}

enum BasketballPosition: Int, Comparable, CaseIterable, Hashable {
    case guard_  = 0
    case forward = 1
    case center  = 2

    static func < (lhs: BasketballPosition, rhs: BasketballPosition) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .guard_:  return String(localized: "player.position.basketball.guard", defaultValue: "가드")
        case .forward: return String(localized: "player.position.basketball.forward", defaultValue: "포워드")
        case .center:  return String(localized: "player.position.basketball.center", defaultValue: "센터")
        }
    }

    static func from(_ raw: String) -> BasketballPosition? {
        let s = raw.uppercased().trimmingCharacters(in: .whitespaces)

        // "G-F", "F/C" 같은 콤보 포지션은 앞쪽 값만 사용
        let primary = String(s.split(whereSeparator: { $0 == "-" || $0 == "/" }).first ?? s[...])

        if ["PG", "SG", "G", "POINT GUARD", "SHOOTING GUARD", "GUARD", "가드"].contains(primary) { return .guard_ }
        if ["SF", "PF", "F", "SMALL FORWARD", "POWER FORWARD", "FORWARD", "포워드"].contains(primary) { return .forward }
        if ["C", "CENTER", "센터"].contains(primary) { return .center }

        // 첫 글자 폴백
        if primary.hasPrefix("G") { return .guard_ }
        if primary.hasPrefix("F") { return .forward }
        if primary.hasPrefix("C") { return .center }
        return nil
    }
}

/// NFL 1단계: 공격/수비/스페셜팀
enum NFLPhase: Int, Comparable, CaseIterable, Hashable {
    case offense      = 0
    case defense      = 1
    case specialTeams = 2

    static func < (lhs: NFLPhase, rhs: NFLPhase) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .offense:      return String(localized: "player.phase.nfl.offense", defaultValue: "공격")
        case .defense:      return String(localized: "player.phase.nfl.defense", defaultValue: "수비")
        case .specialTeams: return String(localized: "player.phase.nfl.specialTeams", defaultValue: "스페셜 팀")
        }
    }
}

/// NFL 2단계 세부 포지션
enum NFLDetailPosition: Int, Comparable, CaseIterable, Hashable {
    // 공격
    case qb  = 0
    case rb  = 1
    case wr  = 2
    case te  = 3
    case ol  = 4
    // 수비
    case dl  = 5
    case lb  = 6
    case db  = 7
    // 스페셜
    case special = 8

    static func < (lhs: NFLDetailPosition, rhs: NFLDetailPosition) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .qb:      return "QB"
        case .rb:      return "RB / FB"
        case .wr:      return "WR"
        case .te:      return "TE"
        case .ol:      return "OL"
        case .dl:      return "DL"
        case .lb:      return "LB"
        case .db:      return "DB"
        case .special: return String(localized: "player.position.nfl.special", defaultValue: "스페셜")
        }
    }

    var phase: NFLPhase {
        switch self {
        case .qb, .rb, .wr, .te, .ol: return .offense
        case .dl, .lb, .db:            return .defense
        case .special:                 return .specialTeams
        }
    }

    static func from(_ raw: String) -> NFLDetailPosition? {
        let s = raw.uppercased().trimmingCharacters(in: .whitespaces)
        switch s {
        case "QB", "QUARTERBACK":                                                           return .qb
        case "RB", "FB", "HB", "RUNNING BACK", "FULLBACK", "HALFBACK":                    return .rb
        case "WR", "WIDE RECEIVER":                                                         return .wr
        case "TE", "TIGHT END":                                                             return .te
        case "OL", "OT", "OG", "C", "T", "G", "OFFENSIVE LINE",
             "CENTER", "GUARD", "TACKLE":                                                   return .ol
        case "DE", "DT", "DL", "NT", "IDL", "DEFENSIVE LINE", "NOSE TACKLE", "EDGE":      return .dl
        case "LB", "MLB", "OLB", "ILB", "LINEBACKER":                                     return .lb
        case "CB", "S", "DB", "FS", "SS", "DEFENSIVE BACK", "SAFETY", "CORNERBACK":       return .db
        case "K", "P", "LS", "PR", "KR", "PK", "KICKER", "PUNTER", "LONG SNAPPER":       return .special
        default:                                                                             return nil
        }
    }
}

/// 종목을 초월한 통합 포지션 그룹 (섹션 헤더/필터 칩에서 사용)
enum PositionGroup: Equatable, Hashable {
    case soccer(SoccerPosition)
    case baseball(BaseballPosition)
    case basketball(BasketballPosition)
    case nfl(NFLDetailPosition)
    case unknown

    var displayName: String {
        switch self {
        case .soccer(let p):     return p.displayName
        case .baseball(let p):   return p.displayName
        case .basketball(let p): return p.displayName
        case .nfl(let p):        return p.displayName
        case .unknown:           return String(localized: "player.position.unknown", defaultValue: "기타")
        }
    }

    /// 섹션 정렬용 숫자
    var sortOrder: Int {
        switch self {
        case .soccer(let p):     return p.rawValue
        case .baseball(let p):   return p.rawValue
        case .basketball(let p): return p.rawValue
        case .nfl(let p):        return p.rawValue
        case .unknown:           return 999
        }
    }

    /// NFL 포지션의 1단계(Phase) 반환 (비NFL이면 nil)
    var nflPhase: NFLPhase? {
        if case .nfl(let p) = self { return p.phase }
        return nil
    }
}

extension SportType {
    /// 원시 포지션 문자열을 종목별 PositionGroup으로 변환
    func positionGroup(for rawPosition: String?) -> PositionGroup {
        guard let raw = rawPosition, !raw.isEmpty else { return .unknown }
        switch self {
        case .soccer:
            return SoccerPosition.from(raw).map { .soccer($0) } ?? .unknown
        case .baseball:
            return BaseballPosition.from(raw).map { .baseball($0) } ?? .unknown
        case .basketball:
            return BasketballPosition.from(raw).map { .basketball($0) } ?? .unknown
        case .americanFootball:
            return NFLDetailPosition.from(raw).map { .nfl($0) } ?? .unknown
        case .other:
            return .unknown
        }
    }

    /// 종목별 전체 포지션 그룹 순서 (필터 칩 생성용)
    var allPositionGroups: [PositionGroup] {
        switch self {
        case .soccer:
            return SoccerPosition.allCases.map { .soccer($0) }
        case .baseball:
            return BaseballPosition.allCases.map { .baseball($0) }
        case .basketball:
            return BasketballPosition.allCases.map { .basketball($0) }
        case .americanFootball:
            return NFLDetailPosition.allCases.map { .nfl($0) }
        case .other:
            return []
        }
    }

    /// NFL 1단계 Phase별 세부 포지션 그룹 반환
    func nflDetailGroups(for phase: NFLPhase) -> [PositionGroup] {
        NFLDetailPosition.allCases
            .filter { $0.phase == phase }
            .map { .nfl($0) }
    }
}

/// [PlayerInfo]를 포지션 그룹별로 정렬하는 헬퍼
func groupedByPosition(
    _ players: [PlayerInfo],
    sport: SportType
) -> [(group: PositionGroup, players: [PlayerInfo])] {
    let grouped = Dictionary(grouping: players) { sport.positionGroup(for: $0.position) }
    return grouped
        .sorted { $0.key.sortOrder < $1.key.sortOrder }
        .map { key, value in
            (group: key, players: value.sorted { $0.name.localizedCompare($1.name) == .orderedAscending })
        }
}
