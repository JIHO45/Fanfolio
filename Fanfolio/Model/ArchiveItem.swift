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
    case sports = "스포츠"
    case culture = "문화"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .sports: return "sportscourt"
        case .culture: return "theatermasks"
        }
    }
}

// MARK: - Sports Type
enum SportType: String, Codable, CaseIterable, Identifiable {
    case baseball = "야구"
    case soccer = "축구"
    case basketball = "농구"
    case americanFootball = "미식축구"
    case hockey = "아이스하키"
    case racing = "모터스포츠"
    case mma = "UFC/MMA"
    case tennis = "테니스"
    case golf = "골프"
    case volleyball = "배구"
    case eSports = "e스포츠"
    case other = "기타"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .baseball:        return "figure.baseball"
        case .soccer:          return "figure.soccer"
        case .basketball:      return "figure.basketball"
        case .americanFootball: return "figure.american.football"
        case .hockey:          return "figure.hockey"
        case .racing:          return "flag.checkered"
        case .mma:             return "figure.martial.arts"
        case .tennis:          return "figure.tennis"
        case .golf:            return "figure.golf"
        case .volleyball:      return "figure.volleyball"
        case .eSports:         return "gamecontroller.fill"
        case .other:           return "sportscourt"
        }
    }
}

// MARK: - Match Status
enum MatchStatus: String, Codable, CaseIterable, Identifiable {
    case upcoming = "경기 예정"
    case live = "진행 중"
    case completed = "완료"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .upcoming: return .blue
        case .live: return .red
        case .completed: return .secondary
        }
    }
    
    var iconName: String {
        switch self {
        case .upcoming: return "clock"
        case .live: return "circle.fill"
        case .completed: return "checkmark.circle"
        }
    }
}

// MARK: - Match Result
enum MatchResult: String, Codable, CaseIterable, Identifiable {
    case win = "승리"
    case loss = "패배"
    case draw = "무승부"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .win: return .green
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
    @Relationship(deleteRule: .cascade, inverse: \SportsModel.folder)
    var matches: [SportsModel]

    @Relationship(deleteRule: .cascade, inverse: \F1RaceModel.folder)
    var f1Races: [F1RaceModel]

    @Relationship(deleteRule: .cascade, inverse: \GolfRoundModel.folder)
    var golfRounds: [GolfRoundModel]
    
    /// JSON 팀 선택 시 저장 (상대팀 선택, 그라디언트 등에 사용)
    var leagueCode: String?
    var teamLogoUrl: String?
    var teamColor: String?
    var teamAlternateColor: String?
    
    /// team nickname  Ex) "San Francisco 49ers" → "49ers"
    var teamNickname: String?
    
    init(name: String, sportType: SportType, orderIndex: Int = 0) {
        self.name = name
        self.sportType = sportType
        self.orderIndex = orderIndex
        self.matches = []
        self.f1Races = []
        self.golfRounds = []
    }
    
    /// 화면 표시용 이름. 애칭이 있으면 애칭, 없으면 공식 이름(name)
    var displayName: String {
        let nick = teamNickname?.trimmingCharacters(in: .whitespaces)
        return (nick != nil && !nick!.isEmpty) ? nick! : name
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
    
    /// TheSportsDB idEvent - 외부 API에서 불러온 경기의 고유 ID (중복 아카이브 방지용)
    var externalEventID: String?
    
    /// 직관 사진 (여러 장)
    var photosData: [Data]?
    
    // 폴더 관계 (sportType, myTeam은 folder에서 상속)
    var folder: SportsFanFolder?
    
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
        orderIndex: Int = 0,
        externalEventID: String? = nil
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
        self.orderIndex = orderIndex
        self.externalEventID = externalEventID
    }
}

extension SportsModel {
    /// 첫 번째 팀 (응원팀 있으면 folder, 없으면 team1)
    var team1Display: String {
        team1 ?? folder?.displayName ?? "내 팀"
    }
    /// 두 번째 팀 (항상 opponentTeam)
    var team2Display: String { opponentTeam }
    var hasFavoriteTeam: Bool { folder?.teamLogoUrl != nil }
}

// MARK: - 문화 카테고리
enum CultureType: String, Codable, CaseIterable, Identifiable {
    case concert = "콘서트"
    case musical = "뮤지컬/연극"
    case movie = "영화"
    case exhibition = "전시회"
    case festival = "페스티벌"
    case other = "기타"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .concert: return "music.mic"
        case .musical: return "theatermasks"
        case .movie: return "film"
        case .exhibition: return "paintpalette"
        case .festival: return "party.popper"
        case .other: return "star"
        }
    }
}

// MARK: - 이벤트 상태
enum EventStatus: String, Codable, CaseIterable, Identifiable {
    case upcoming = "예정"
    case completed = "완료"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .upcoming: return .blue
        case .completed: return .secondary
        }
    }
    
    var iconName: String {
        switch self {
        case .upcoming: return "clock"
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
    
    /// 현장 사진 (여러 장)
    var photosData: [Data]?
    
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
        self.orderIndex = orderIndex
    }
}

