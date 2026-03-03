//
//  F1RaceModel.swift
//  Fanfolio
//
//  Created by 박지호 on 2/24/26.
//
//  F1은 Home vs Away 구조가 아닌 리더보드(순위) 방식의 개인/팀 혼합 종목입니다.
//  SportsModel 대신 별도 SwiftData 모델을 사용합니다.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - F1 드라이버 (폼 내 픽업용, 영구 저장 아님)

struct F1Driver: Identifiable, Hashable {
    let id: String          // ESPN athlete ID 또는 이름 기반 고유값
    let name: String
    let team: String
    let number: Int?

    var headshotURL: String? {
        guard !id.isEmpty else { return nil }
        return "https://a.espncdn.com/i/headshots/f1/players/full/\(id).png"
    }
}

// MARK: - 2026 시즌 드라이버 정적 목록 (ESPN 미지원 기간 Fallback)

enum F1Data {
    static let drivers2026: [F1Driver] = [
        // Red Bull Racing
        F1Driver(id: "4663",   name: "Max Verstappen",      team: "Red Bull Racing", number: 1),
        F1Driver(id: "9861",   name: "Yuki Tsunoda",         team: "Red Bull Racing", number: 22),
        // Ferrari
        F1Driver(id: "4848",   name: "Charles Leclerc",      team: "Ferrari",         number: 16),
        F1Driver(id: "6268",   name: "Lewis Hamilton",        team: "Ferrari",         number: 44),
        // McLaren
        F1Driver(id: "4773",   name: "Lando Norris",          team: "McLaren",         number: 4),
        F1Driver(id: "9862",   name: "Oscar Piastri",         team: "McLaren",         number: 81),
        // Mercedes
        F1Driver(id: "4731",   name: "George Russell",        team: "Mercedes",        number: 63),
        F1Driver(id: "9863",   name: "Kimi Antonelli",        team: "Mercedes",        number: 12),
        // Aston Martin
        F1Driver(id: "3848",   name: "Fernando Alonso",       team: "Aston Martin",    number: 14),
        F1Driver(id: "4772",   name: "Lance Stroll",          team: "Aston Martin",    number: 18),
        // Alpine
        F1Driver(id: "4849",   name: "Pierre Gasly",          team: "Alpine",          number: 10),
        F1Driver(id: "9864",   name: "Jack Doohan",           team: "Alpine",          number: 7),
        // Haas
        F1Driver(id: "9865",   name: "Esteban Ocon",          team: "Haas",            number: 31),
        F1Driver(id: "9866",   name: "Oliver Bearman",        team: "Haas",            number: 87),
        // Racing Bulls
        F1Driver(id: "9867",   name: "Isack Hadjar",          team: "Racing Bulls",    number: 6),
        F1Driver(id: "9868",   name: "Liam Lawson",           team: "Racing Bulls",    number: 30),
        // Williams
        F1Driver(id: "4770",   name: "Alex Albon",            team: "Williams",        number: 23),
        F1Driver(id: "4847",   name: "Carlos Sainz",          team: "Williams",        number: 55),
        // Audi
        F1Driver(id: "4732",   name: "Nico Hülkenberg",       team: "Audi",            number: 27),
        F1Driver(id: "9869",   name: "Gabriel Bortoleto",     team: "Audi",            number: 5),
        // Cadillac
        F1Driver(id: "9870",   name: "Colton Herta",          team: "Cadillac",        number: 9),
    ]

    /// 팀 이름이 일치하는 드라이버 필터 (폴더 팀 기준 자동 선택 지원용)
    static func drivers(forTeam teamName: String) -> [F1Driver] {
        let normalized = teamName.lowercased()
        return drivers2026.filter { $0.team.lowercased().contains(normalized) || normalized.contains($0.team.lowercased()) }
    }

    /// 순위 표시용 텍스트 (0 = DNF, nil = 미입력)
    static func positionText(_ position: Int?) -> String {
        guard let pos = position else { return "-" }
        if pos == 0 { return "DNF" }
        return "\(pos)위"
    }

    /// 포디움 여부
    static func isPodium(_ position: Int?) -> Bool {
        guard let pos = position, pos > 0 else { return false }
        return pos <= 3
    }
}

// MARK: - F1RaceModel (SwiftData)

@Model
class F1RaceModel {
    // MARK: ArchiveItemProtocol 준수
    var title: String           // "2026 일본 그랑프리"
    var date: Date?
    var memo: String?
    var orderIndex: Int

    // MARK: 레이스 정보
    var circuitName: String?    // "스즈카 서킷"
    var raceStatus: MatchStatus

    // MARK: 내 드라이버/팀
    var myDriverName: String?
    var myDriverESPNId: String?     // ESPN CDN 헤드샷 조합용
    var myConstructorName: String?  // 소속 컨스트럭터

    /// 1~20: 정상 완주 순위, 0: DNF, nil: 미입력
    var myFinishPosition: Int?

    // MARK: 포디움 (1~3위 드라이버명)
    var podium1DriverName: String?
    var podium2DriverName: String?
    var podium3DriverName: String?

    // MARK: 미디어
    var photosData: [Data]?
    var qrCodeImageData: Data?

    // MARK: 폴더 관계
    var folder: SportsFanFolder?

    init(
        title: String,
        date: Date? = nil,
        circuitName: String? = nil,
        raceStatus: MatchStatus = .upcoming,
        myDriverName: String? = nil,
        myDriverESPNId: String? = nil,
        myConstructorName: String? = nil,
        myFinishPosition: Int? = nil,
        podium1DriverName: String? = nil,
        podium2DriverName: String? = nil,
        podium3DriverName: String? = nil,
        memo: String? = nil,
        qrCodeImageData: Data? = nil,
        photosData: [Data]? = nil,
        orderIndex: Int = 0
    ) {
        self.title = title
        self.date = date
        self.circuitName = circuitName
        self.raceStatus = raceStatus
        self.myDriverName = myDriverName
        self.myDriverESPNId = myDriverESPNId
        self.myConstructorName = myConstructorName
        self.myFinishPosition = myFinishPosition
        self.podium1DriverName = podium1DriverName
        self.podium2DriverName = podium2DriverName
        self.podium3DriverName = podium3DriverName
        self.memo = memo
        self.qrCodeImageData = qrCodeImageData
        self.photosData = photosData
        self.orderIndex = orderIndex
    }
}

// MARK: - 편의 프로퍼티

extension F1RaceModel {
    var isDNF: Bool { myFinishPosition == 0 }
    var hasResult: Bool { myFinishPosition != nil }
    var isPodiumFinish: Bool { F1Data.isPodium(myFinishPosition) }

    var positionText: String { F1Data.positionText(myFinishPosition) }

    var myDriverHeadshotURL: String? {
        guard let espnId = myDriverESPNId, !espnId.isEmpty else { return nil }
        return "https://a.espncdn.com/i/headshots/f1/players/full/\(espnId).png"
    }

    /// 순위 뱃지 색상 (1위=금, 2위=은, 3위=동, DNF=빨간색, 나머지=기본)
    var positionBadgeColor: Color {
        guard let pos = myFinishPosition else { return .secondary }
        switch pos {
        case 0:  return .red
        case 1:  return Color(red: 1.0, green: 0.84, blue: 0.0)  // gold
        case 2:  return Color(red: 0.75, green: 0.75, blue: 0.75) // silver
        case 3:  return Color(red: 0.8, green: 0.5, blue: 0.2)   // bronze
        default: return .secondary
        }
    }
}
