//
//  ArchiveItem.swift
//  Fanfolio
//
//  Created by 박지호 on 12/14/25.
//

import SwiftUI
import SwiftData

// MARK: - Common Protocol
protocol ArchiveItemProtocol {
    var title: String { get set }
    var date: Date? { get set }
    var memo: String? { get set }
    var orderIndex: Int { get set }
}

// MARK: - Category
enum ArchiveCategory: String, Identifiable, CaseIterable {
    case sports  = "sports"
    case culture = "culture"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .sports:  return String(localized: "sports.label",  defaultValue: "스포츠")
        case .culture: return String(localized: "culture.label", defaultValue: "문화")
        }
    }
    
    var iconName: String {
        switch self {
        case .sports:  return "sportscourt"
        case .culture: return "theatermasks"
        }
    }
}

// MARK: - Sports Type
enum SportType: String, Codable, CaseIterable, Identifiable {
    case baseball        = "baseball"
    case soccer          = "soccer"
    case basketball      = "basketball"
    case americanFootball = "american_football"
    case other           = "other"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .baseball:         return String(localized: "sport.baseball",          defaultValue: "야구")
        case .soccer:           return String(localized: "sport.soccer",            defaultValue: "축구")
        case .basketball:       return String(localized: "sport.basketball",        defaultValue: "농구")
        case .americanFootball: return String(localized: "sport.americanFootball",  defaultValue: "미식축구")
        case .other:            return String(localized: "sport.other",             defaultValue: "기타")
        }
    }
    
    var iconName: String {
        switch self {
        case .baseball:         return "figure.baseball"
        case .soccer:           return "figure.soccer"
        case .basketball:       return "figure.basketball"
        case .americanFootball: return "figure.american.football"
        case .other:            return "sportscourt"
        }
    }
}

// MARK: - Match Status
enum MatchStatus: String, Codable, CaseIterable, Identifiable {
    case upcoming  = "upcoming"
    case live      = "live"
    case completed = "completed"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .upcoming:  return String(localized: "matchStatus.upcoming",  defaultValue: "경기 예정")
        case .live:      return String(localized: "matchStatus.live",      defaultValue: "진행 중")
        case .completed: return String(localized: "matchStatus.completed", defaultValue: "완료")
        }
    }
    
    var color: Color {
        switch self {
        case .upcoming:  return .blue
        case .live:      return .red
        case .completed: return .secondary
        }
    }
    
    var iconName: String {
        switch self {
        case .upcoming:  return "clock"
        case .live:      return "circle.fill"
        case .completed: return "checkmark.circle"
        }
    }
}

// MARK: - MatchEvent (API에서 불러온 경기 일정 임시 데이터)

struct MatchEvent: Identifiable {
    let id: String              // "espn:{eventID}" / "api-sports:{gameID}"
    let opponentName: String
    let isHome: Bool
    let myScore: Int?           // 완료·진행 중 경기에만 존재
    let opponentScore: Int?
    let date: Date?
    let leagueName: String?
    let isCompleted: Bool
    var isLive: Bool = false    // 현재 진행 중인 경기
    /// ESPN 등에서 내려준 홈·원정 기준 쿼터/이닝 점수 (없으면 빈 배열)
    var periods: [PeriodScore] = []

    var result: MatchResult? {
        guard isCompleted, let my = myScore, let opp = opponentScore else { return nil }
        if my > opp { return .win }
        if my < opp { return .loss }
        return .draw
    }
}

// MARK: - Match Result
enum MatchResult: String, Codable, CaseIterable, Identifiable {
    case win  = "win"
    case loss = "loss"
    case draw = "draw"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .win:  return String(localized: "matchResult.win",  defaultValue: "승리")
        case .loss: return String(localized: "matchResult.loss", defaultValue: "패배")
        case .draw: return String(localized: "matchResult.draw", defaultValue: "무승부")
        }
    }
    
    var color: Color {
        switch self {
        case .win:  return .green
        case .loss: return .red
        case .draw: return .orange
        }
    }
}

// MARK: - Sports Fan Folder
/// 팬이 팔로우하는 팀/관심사 단위의 폴더.
/// 사이드바에 표시되며, 내부에 경기 기록(SportsModel)을 담는다.
@Model
class SportsFanFolder {
    var name: String
    var sportType: SportType
    var orderIndex: Int
    /// 폴더별 최애를 분리 저장하기 위한 고유 식별자 (생성 시 자동 부여, 불변)
    var folderID: UUID
    @Relationship(deleteRule: .cascade, inverse: \SportsModel.folder)
    var matches: [SportsModel]
    
    /// JSON 팀 선택 시 저장 (상대팀 선택, 그라디언트 등에 사용)
    var leagueCode: String?
    var teamLogoUrl: String?
    var teamColor: String?
    var teamAlternateColor: String?
    
    /// team nickname  Ex) "San Francisco 49ers" → "49ers"
    var teamNickname: String?

    /// API-Sports 팀 고유 ID (비미국 리그 라이브 스코어 조회용)
    /// K리그·KBO 등 ESPN이 지원하지 않는 리그에서만 사용
    var apiSportsTeamID: Int?

    /// 기타 카테고리 전용 — 상대팀 유무 (폴더 생성 시 결정, 이후 변경 불가)
    /// 팀 스포츠에서는 항상 true
    var matchHasOpponent: Bool
    
    init(name: String, sportType: SportType, orderIndex: Int = 0, matchHasOpponent: Bool = true) {
        self.name = name
        self.sportType = sportType
        self.orderIndex = orderIndex
        self.folderID = UUID()
        self.matches = []
        self.matchHasOpponent = matchHasOpponent
    }
    
    /// 화면 표시용 이름. 애칭이 있으면 애칭, 없으면 공식 이름(name)
    var displayName: String {
        let nick = teamNickname?.trimmingCharacters(in: .whitespaces)
        if let nick, !nick.isEmpty { return nick }
        return name
    }
}

// MARK: - Sports Model
@Model
class SportsModel: ArchiveItemProtocol {
    // 공통 속성 (프로토콜)
    var title: String
    var date: Date?
    var memo: String?
    var orderIndex: Int
    
    // 스포츠 전용 속성
    var opponentTeam: String
    var myTeamScore: Int
    /// 응원 팀 없을 때(리그만 선택) 첫 번째 팀. 있으면 nil이고 folder.name이 내 팀
    var team1: String?
    var opponentScore: Int
    var matchResult: MatchResult
    var matchStatus: MatchStatus
    var isHomeGame: Bool
    var location: String?
    var qrCodeImageData: Data?
    
    /// 외부 API 이벤트 고유 ID, 형식: "source:id" (예: "espn:401671704", "api-sports:1234")
    /// 중복 아카이브 방지용
    var externalEventID: String?

    /// 경기 불러오기 시 API에서 받은 이닝·쿼터별 점수(JSON 인코딩된 `[PeriodScore]`)
    var importedPeriodScoresData: Data?
    
    /// 직관 사진 (여러 장) — 레거시. 신규는 photoPaths 사용.
    var photosData: [Data]?
    /// 직관 사진 상대 경로 (Document 기준). 저장·표시 시 이 값 사용.
    var photoPaths: [String]?
    
    // 폴더 관계 (sportType, myTeam은 folder에서 상속)
    var folder: SportsFanFolder?
    @Relationship(deleteRule: .cascade, inverse: \SavedTicket.match)
    var savedTickets: [SavedTicket]
    
    init(
        title: String,
        opponentTeam: String,
        myTeamScore: Int = 0,
        opponentScore: Int = 0,
        matchResult: MatchResult = .draw,
        matchStatus: MatchStatus = .upcoming,
        isHomeGame: Bool = true,
        date: Date? = nil,
        location: String? = nil,
        memo: String? = nil,
        qrCodeImageData: Data? = nil,
        photosData: [Data]? = nil,
        photoPaths: [String]? = nil,
        orderIndex: Int = 0,
        externalEventID: String? = nil,
        importedPeriodScoresData: Data? = nil
    ) {
        self.title = title
        self.opponentTeam = opponentTeam
        self.myTeamScore = myTeamScore
        self.opponentScore = opponentScore
        self.matchResult = matchResult
        self.matchStatus = matchStatus
        self.isHomeGame = isHomeGame
        self.date = date
        self.location = location
        self.memo = memo
        self.qrCodeImageData = qrCodeImageData
        self.photosData = photosData
        self.photoPaths = photoPaths
        self.savedTickets = []
        self.orderIndex = orderIndex
        self.externalEventID = externalEventID
        self.importedPeriodScoresData = importedPeriodScoresData
    }
}

extension SportsModel {
    /// 불러오기 시 저장된 이닝·쿼터별 점수(홈·원정 순서). 없거나 파싱 실패 시 빈 배열.
    var importedPeriodScores: [PeriodScore] {
        guard let importedPeriodScoresData, !importedPeriodScoresData.isEmpty,
              let decoded = try? JSONDecoder().decode([PeriodScore].self, from: importedPeriodScoresData) else {
            return []
        }
        return decoded
    }

    /// 첫 번째 팀 (응원팀 있으면 folder, 없으면 team1)
    var team1Display: String {
        team1 ?? folder?.displayName ?? String(localized: "myTeam.label", defaultValue: "내 팀")
    }
    /// 두 번째 팀 (항상 opponentTeam)
    var team2Display: String { opponentTeam }
    var hasFavoriteTeam: Bool { folder?.teamLogoUrl != nil }
    var savedTicketPaths: [String] {
        savedTickets.flatMap { [$0.imagePath, $0.thumbnailPath] }
    }

    /// 경기 상세에서 완료 처리·폴더 변경 시 로스터 `.task`를 다시 실행
    var fanfolioMatchSquadTaskToken: Int {
        var h = Hasher()
        h.combine(String(describing: persistentModelID))
        h.combine(matchStatus)
        h.combine(team1Display)
        h.combine(opponentTeam)
        if let f = folder {
            h.combine(f.sportType)
            h.combine(f.leagueCode)
            h.combine(f.name)
            h.combine(f.apiSportsTeamID)
            h.combine(f.teamLogoUrl)
        }
        return h.finalize()
    }

    /// 티켓 공유 화면 로고 로드 `.task` 재실행용
    var fanfolioTicketShareStaticToken: Int {
        var h = Hasher()
        h.combine(String(describing: persistentModelID))
        h.combine(team1Display)
        h.combine(opponentTeam)
        h.combine(folder?.teamLogoUrl)
        h.combine(folder?.leagueCode)
        h.combine(folder?.name)
        return h.finalize()
    }
}

extension SportsFanFolder {
    var savedTicketPaths: [String] {
        matches.flatMap(\.savedTicketPaths)
    }

    /// SwiftUI `.task(id:)` 재실행용 — 종목·리그·팀·경기 내용이 바뀌면 통계/로스터 로딩을 다시 돌립니다.
    var fanfolioFolderTaskToken: Int {
        var h = Hasher()
        h.combine(sportType)
        h.combine(leagueCode)
        h.combine(name)
        h.combine(displayName)
        h.combine(teamNickname)
        h.combine(teamLogoUrl)
        h.combine(apiSportsTeamID)
        h.combine(matches.count)
        let sortedMatches = matches.sorted {
            String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID)
        }
        for m in sortedMatches {
            h.combine(String(describing: m.persistentModelID))
            h.combine(m.matchStatus)
            h.combine(m.matchResult)
            h.combine(m.myTeamScore)
            h.combine(m.opponentScore)
        }
        return h.finalize()
    }
}

// MARK: - Saved Ticket
@Model
class SavedTicket {
    var ticketID: UUID
    var imagePath: String
    var thumbnailPath: String
    var createdAt: Date
    
    // 갤러리 표시용 경기 메타데이터 스냅샷
    var team1Name: String
    var team2Name: String
    var myTeamScore: Int
    var opponentScore: Int
    var matchResult: MatchResult
    var sportType: SportType
    var matchDate: Date?
    
    var match: SportsModel?
    
    init(
        ticketID: UUID = UUID(),
        imagePath: String,
        thumbnailPath: String,
        createdAt: Date = .now,
        team1Name: String,
        team2Name: String,
        myTeamScore: Int,
        opponentScore: Int,
        matchResult: MatchResult,
        sportType: SportType,
        matchDate: Date? = nil,
        match: SportsModel? = nil
    ) {
        self.ticketID = ticketID
        self.imagePath = imagePath
        self.thumbnailPath = thumbnailPath
        self.createdAt = createdAt
        self.team1Name = team1Name
        self.team2Name = team2Name
        self.myTeamScore = myTeamScore
        self.opponentScore = opponentScore
        self.matchResult = matchResult
        self.sportType = sportType
        self.matchDate = matchDate
        self.match = match
    }
}

// MARK: - 문화 카테고리
enum CultureType: String, Codable, CaseIterable, Identifiable {
    case concert    = "concert"
    case musical    = "musical"
    case movie      = "movie"
    case exhibition = "exhibition"
    case festival   = "festival"
    case other      = "other"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .concert:    return String(localized: "cultureType.concert",    defaultValue: "콘서트")
        case .musical:    return String(localized: "cultureType.musical",    defaultValue: "뮤지컬/연극")
        case .movie:      return String(localized: "cultureType.movie",      defaultValue: "영화")
        case .exhibition: return String(localized: "cultureType.exhibition", defaultValue: "전시회")
        case .festival:   return String(localized: "cultureType.festival",   defaultValue: "페스티벌")
        case .other:      return String(localized: "cultureType.other",      defaultValue: "기타")
        }
    }
    
    var iconName: String {
        switch self {
        case .concert:    return "music.mic"
        case .musical:    return "theatermasks"
        case .movie:      return "film"
        case .exhibition: return "paintpalette"
        case .festival:   return "party.popper"
        case .other:      return "star"
        }
    }
}

// MARK: - 이벤트 상태
enum EventStatus: String, Codable, CaseIterable, Identifiable {
    case upcoming  = "upcoming"
    case completed = "completed"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .upcoming:  return String(localized: "eventStatus.upcoming",  defaultValue: "예정")
        case .completed: return String(localized: "eventStatus.completed", defaultValue: "완료")
        }
    }
    
    var color: Color {
        switch self {
        case .upcoming:  return .blue
        case .completed: return .secondary
        }
    }
    
    var iconName: String {
        switch self {
        case .upcoming:  return "clock"
        case .completed: return "checkmark.circle"
        }
    }
}

// MARK: - Culture Fan Folder
/// 팬이 팔로우하는 아티스트/관심사 단위의 폴더.
/// 사이드바에 표시되며, 내부에 이벤트 기록(CultureModel)을 담는다.
@Model
class CultureFanFolder {
    var name: String
    var cultureType: CultureType
    var orderIndex: Int
    @Relationship(deleteRule: .cascade, inverse: \CultureModel.folder)
    var events: [CultureModel]
    
    init(name: String, cultureType: CultureType, orderIndex: Int = 0) {
        self.name = name
        self.cultureType = cultureType
        self.orderIndex = orderIndex
        self.events = []
    }
}

// MARK: - Culture Model
@Model
class CultureModel: ArchiveItemProtocol {
    // 공통 속성 (프로토콜)
    var title: String
    var date: Date?
    var memo: String?
    var orderIndex: Int
    
    // 문화 전용 속성
    var artist: String?
    var location: String?
    var seatInfo: String?
    var rating: Int
    var eventStatus: EventStatus
    var qrCodeImageData: Data?
    
    /// 현장 사진 (여러 장) — 레거시. 신규는 photoPaths 사용.
    var photosData: [Data]?
    /// 현장 사진 상대 경로 (Document 기준). 저장·표시 시 이 값 사용.
    var photoPaths: [String]?
    
    // 폴더 관계 (cultureType은 folder에서 상속)
    var folder: CultureFanFolder?
    
    init(
        title: String,
        artist: String? = nil,
        date: Date? = nil,
        location: String? = nil,
        seatInfo: String? = nil,
        rating: Int = 0,
        eventStatus: EventStatus = .upcoming,
        memo: String? = nil,
        qrCodeImageData: Data? = nil,
        photosData: [Data]? = nil,
        photoPaths: [String]? = nil,
        orderIndex: Int = 0
    ) {
        self.title = title
        self.artist = artist
        self.date = date
        self.location = location
        self.seatInfo = seatInfo
        self.rating = rating
        self.eventStatus = eventStatus
        self.memo = memo
        self.qrCodeImageData = qrCodeImageData
        self.photosData = photosData
        self.photoPaths = photoPaths
        self.orderIndex = orderIndex
    }
}

extension CultureModel {
    /// SwiftUI `.task(id:)` — 이벤트·폴더 메타가 바뀌면 공유 시트의 이전 렌더 결과를 버리고 다시 맞춤
    var fanfolioCultureShareTaskToken: Int {
        var h = Hasher()
        h.combine(String(describing: persistentModelID))
        h.combine(title)
        h.combine(artist)
        h.combine(location)
        h.combine(seatInfo)
        h.combine(rating)
        h.combine(eventStatus)
        if let d = date { h.combine(d.timeIntervalSince1970) }
        if let f = folder {
            h.combine(f.cultureType)
            h.combine(f.name)
        }
        return h.finalize()
    }
}

