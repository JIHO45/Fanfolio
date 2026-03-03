//
//  GolfRoundModel.swift
//  Fanfolio
//
//  골프는 상대 팀 없이 스코어(타수)로 기록하는 개인 스포츠입니다.
//  SportsModel 대신 별도 SwiftData 모델을 사용합니다.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - GolfRoundModel (SwiftData)

@Model
class GolfRoundModel {
    // MARK: 공통 필드
    var title: String           // "버디힐스 CC 라운드"
    var date: Date?
    var memo: String?
    var orderIndex: Int

    // MARK: 라운드 정보
    var courseName: String?     // "버디힐스 CC"
    var roundStatus: MatchStatus
    var numberOfHoles: Int      // 9 or 18

    // MARK: 대회 여부
    var isTournament: Bool
    var myPosition: Int?        // 대회 순위 (일반 라운드는 nil)

    // MARK: 스코어
    var totalScore: Int?        // 총 타수
    var par: Int?               // 코스 파 (기본 72)

    // MARK: 세부 스코어 (선택)
    var eagleCount: Int?
    var birdieCount: Int?
    var parCount: Int?
    var bogeyCount: Int?
    var doubleBogeyPlusCount: Int?
    var putts: Int?
    var fairwaysHit: Int?
    var greensInRegulation: Int?

    // MARK: 미디어
    var photosData: [Data]?
    var qrCodeImageData: Data?

    // MARK: 폴더 관계
    var folder: SportsFanFolder?

    init(
        title: String,
        date: Date? = nil,
        courseName: String? = nil,
        roundStatus: MatchStatus = .upcoming,
        numberOfHoles: Int = 18,
        isTournament: Bool = false,
        myPosition: Int? = nil,
        totalScore: Int? = nil,
        par: Int? = nil,
        eagleCount: Int? = nil,
        birdieCount: Int? = nil,
        parCount: Int? = nil,
        bogeyCount: Int? = nil,
        doubleBogeyPlusCount: Int? = nil,
        putts: Int? = nil,
        fairwaysHit: Int? = nil,
        greensInRegulation: Int? = nil,
        memo: String? = nil,
        qrCodeImageData: Data? = nil,
        photosData: [Data]? = nil,
        orderIndex: Int = 0
    ) {
        self.title = title
        self.date = date
        self.courseName = courseName
        self.roundStatus = roundStatus
        self.numberOfHoles = numberOfHoles
        self.isTournament = isTournament
        self.myPosition = myPosition
        self.totalScore = totalScore
        self.par = par
        self.eagleCount = eagleCount
        self.birdieCount = birdieCount
        self.parCount = parCount
        self.bogeyCount = bogeyCount
        self.doubleBogeyPlusCount = doubleBogeyPlusCount
        self.putts = putts
        self.fairwaysHit = fairwaysHit
        self.greensInRegulation = greensInRegulation
        self.memo = memo
        self.qrCodeImageData = qrCodeImageData
        self.photosData = photosData
        self.orderIndex = orderIndex
    }
}

// MARK: - 편의 프로퍼티

extension GolfRoundModel {
    /// 파 대비 스코어 (언더: 음수, 이븐: 0, 오버: 양수)
    var scoreToPar: Int? {
        guard let total = totalScore, let p = par else { return nil }
        return total - p
    }

    /// 파 대비 스코어 텍스트 ("E", "-3", "+2" 등)
    var scoreToParText: String {
        guard let diff = scoreToPar else { return "-" }
        if diff == 0 { return "E" }
        if diff < 0 { return "\(diff)" }
        return "+\(diff)"
    }

    /// 총 타수 표시 텍스트
    var totalScoreText: String {
        guard let score = totalScore else { return "-" }
        return "\(score)"
    }

    /// 언더파 여부
    var isUnderPar: Bool {
        guard let diff = scoreToPar else { return false }
        return diff < 0
    }

    /// 이븐파 여부
    var isEvenPar: Bool {
        scoreToPar == 0
    }

    /// 스코어 색상 (언더=초록, 이븐=파랑, 오버=빨강)
    var scoreColor: Color {
        guard let diff = scoreToPar else { return .secondary }
        if diff < 0 { return .green }
        if diff == 0 { return .blue }
        return .red
    }

    /// 순위 표시 텍스트
    var positionText: String {
        guard let pos = myPosition else { return "-" }
        return "\(pos)위"
    }

    /// 세부 스코어 입력 여부
    var hasDetailScore: Bool {
        eagleCount != nil || birdieCount != nil || parCount != nil || bogeyCount != nil
    }

    /// 페어웨이 안착률 텍스트
    var fairwayHitRateText: String? {
        guard let hit = fairwaysHit else { return nil }
        let total = numberOfHoles == 18 ? 14 : 7  // 파3 제외 기준
        return "\(hit)/\(total)"
    }

    /// 홀 수 텍스트
    var holesText: String { "\(numberOfHoles)홀" }
}
