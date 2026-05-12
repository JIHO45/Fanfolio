//
//  LiveScoreAttributes.swift
//  Fanfolio
//
//  ⚠️ 본 파일은 **본 앱 타겟(Fanfolio)** 과 **Widget Extension 타겟** 둘 다에
//  Target Membership을 체크해야 합니다. (앱은 활동을 시작·업데이트, 위젯은 UI 렌더링)
//
//  ContentState 총 페이로드는 4KB 제한이 있으므로 짧은 텍스트만 담습니다.
//

import Foundation
import ActivityKit

struct LiveScoreAttributes: ActivityAttributes {

    // MARK: - 동적 상태 (경기 진행에 따라 변하는 값)
    public struct ContentState: Codable, Hashable {
        /// 홈팀 총점
        var homeScore: Int
        /// 원정팀 총점
        var awayScore: Int
        /// 경기 상태 표시용 (예: "3회 초", "전반 35분", "경기 종료")
        var matchStatus: String
        /// LiveFixtureStatus.short 원본 (예: "1Q", "IN3", "FT"). 위젯이 로컬라이즈하거나
        /// 색상 결정 등에 활용할 수 있도록 보존.
        var rawStatusShort: String
        /// 라이브 여부 (위젯에서 빨간 점 등 표시할 때 사용)
        var isLive: Bool
        /// 종료 여부
        var isFinished: Bool
    }

    // MARK: - 정적 속성 (액티비티 생성 시 결정, 변경 불가)

    /// 홈팀 표시명
    var homeTeamName: String
    /// 원정팀 표시명
    var awayTeamName: String

    /// 번들 에셋에 들어있는 홈팀 로고 이미지 이름 (KBO 전용, 없으면 nil)
    var homeTeamAssetImageName: String?
    /// 번들 에셋에 들어있는 원정팀 로고 이미지 이름 (KBO 전용, 없으면 nil)
    var awayTeamAssetImageName: String?

    /// 번들 에셋이 없을 때 위젯에서 로고 대체용으로 사용할 약자 (예: "LAL", "MCI")
    var homeTeamAbbreviation: String?
    var awayTeamAbbreviation: String?

    /// 리그 코드 (예: "KBO", "EPL", "NBA"). 위젯에서 종목별 라벨링 분기에 사용.
    var leagueCode: String

    /// 경기 외부 식별자 (중복 액티비티 방지·재시작 식별용)
    var externalEventID: String
}
