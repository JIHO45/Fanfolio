//
//  FanfolioTests.swift
//  FanfolioTests
//
//  이 파일에는 특정 파일에 속하지 않는 공통 테스트나
//  종목 타입 관련 테스트를 모아둡니다.
//
//  다른 테스트 파일들:
//  → FanStatsCalculatorTests.swift  — 팬 통계 계산기 (승률, 연승 등)
//  → LiveFixtureStatusTests.swift   — API 경기 상태 코드 변환
//

import Testing
@testable import Fanfolio

// MARK: - SportType 피리어드 레이블 테스트

/// `SportType.periodLabels(count:)` 메서드를 검증합니다.
///
/// 종목마다 쿼터/이닝/세트의 표기 방식이 다릅니다.
/// 이 테스트는 각 종목의 레이블이 올바른 형식으로 생성되는지 확인합니다.
@Suite("SportType — 피리어드 레이블 생성")
struct SportTypePeriodLabelsTests {

    @Test("미식축구 4쿼터 레이블")
    func nflFourQuarters() {
        let labels = SportType.americanFootball.periodLabels(count: 4)
        #expect(labels == ["1Q", "2Q", "3Q", "4Q"])
    }

    @Test("미식축구 연장 포함 5피리어드: 'OT1' 추가")
    func nflWithOvertime() {
        let labels = SportType.americanFootball.periodLabels(count: 5)
        #expect(labels == ["1Q", "2Q", "3Q", "4Q", "OT1"])
    }

    @Test("농구 4쿼터 레이블")
    func basketballFourQuarters() {
        let labels = SportType.basketball.periodLabels(count: 4)
        #expect(labels == ["1Q", "2Q", "3Q", "4Q"])
    }

    @Test("축구 2피리어드(전반·후반) 레이블")
    func soccerTwoPeriods() {
        let labels = SportType.soccer.periodLabels(count: 2)
        #expect(labels == ["전반", "후반"])
    }

    @Test("축구 연장 포함 3피리어드: '연장1' 추가")
    func soccerWithExtraTime() {
        let labels = SportType.soccer.periodLabels(count: 3)
        #expect(labels == ["전반", "후반", "연장1"])
    }

    @Test("야구 9이닝 레이블")
    func baseballNineInnings() {
        let labels = SportType.baseball.periodLabels(count: 9)
        #expect(labels == ["1회","2회","3회","4회","5회","6회","7회","8회","9회"])
    }

    @Test("야구 count가 9 미만이어도 최소 9이닝 보장")
    func baseballMinimumNineInnings() {
        // count=3이어도 max(9, count) = 9
        let labels = SportType.baseball.periodLabels(count: 3)
        #expect(labels.count == 9)
        #expect(labels.first == "1회")
        #expect(labels.last  == "9회")
    }

}

// MARK: - SportsFanFolder displayName 테스트

/// `SportsFanFolder.displayName` 계산 프로퍼티를 검증합니다.
///
/// 애칭(teamNickname)이 있으면 애칭을, 없으면 공식 팀 이름(name)을 반환합니다.
@Suite("SportsFanFolder — displayName")
struct SportsFanFolderDisplayNameTests {

    @Test("애칭 없으면 공식 이름 반환")
    func displayNameFallsBackToName() {
        let folder = SportsFanFolder(name: "LG 트윈스", sportType: .baseball)
        #expect(folder.displayName == "LG 트윈스")
    }

    @Test("애칭 설정 시 애칭 반환")
    func displayNameUsesNickname() {
        let folder = SportsFanFolder(name: "San Francisco 49ers", sportType: .americanFootball)
        folder.teamNickname = "49ers"
        #expect(folder.displayName == "49ers")
    }

    @Test("빈 문자열 애칭은 공식 이름으로 폴백")
    func displayNameIgnoresEmptyNickname() {
        let folder = SportsFanFolder(name: "Manchester City", sportType: .soccer)
        folder.teamNickname = ""
        #expect(folder.displayName == "Manchester City")
    }

    @Test("공백만 있는 애칭도 공식 이름으로 폴백")
    func displayNameIgnoresWhitespaceOnlyNickname() {
        let folder = SportsFanFolder(name: "Manchester City", sportType: .soccer)
        folder.teamNickname = "   "
        #expect(folder.displayName == "Manchester City")
    }

    @Test("앞뒤 공백이 있어도 애칭 내용이 있으면 트리밍 후 반환")
    func displayNameTrimsNickname() {
        let folder = SportsFanFolder(name: "Los Angeles Lakers", sportType: .basketball)
        folder.teamNickname = "  Lakers  "
        #expect(folder.displayName == "Lakers")
    }
}

// MARK: - SportsModel 확장 프로퍼티 테스트

/// `SportsModel`의 `team1Display`, `team2Display` 계산 프로퍼티를 검증합니다.
@Suite("SportsModel — 팀 이름 표시 프로퍼티")
struct SportsModelExtensionTests {

    @Test("team1이 설정된 경우 team1Display는 team1 값 반환")
    func team1DisplayReturnsTeam1WhenSet() {
        let match = SportsModel(title: "리그 경기", opponentTeam: "전북 현대")
        match.team1 = "FC 서울"
        #expect(match.team1Display == "FC 서울")
    }

    @Test("team1이 nil이고 folder도 nil이면 '내 팀' 반환")
    func team1DisplayFallsBackToDefaultWhenNil() {
        let match = SportsModel(title: "경기", opponentTeam: "상대팀")
        // team1도 nil, folder도 nil
        #expect(match.team1Display == "내 팀")
    }

    @Test("team2Display는 항상 opponentTeam 반환")
    func team2DisplayAlwaysReturnsOpponent() {
        let match = SportsModel(title: "경기", opponentTeam: "두산 베어스")
        match.team1 = "LG 트윈스"
        #expect(match.team2Display == "두산 베어스")
    }
}

// MARK: - LiveFixture 편의 프로퍼티 테스트

/// LiveFixture의 isLive / isUpcoming 계산 프로퍼티가
/// 내부 status 코드를 올바르게 반영하는지 확인합니다.
@Suite("LiveFixture — 경기 상태 편의 프로퍼티")
struct LiveFixtureTests {

    /// 테스트용 LiveFixture를 생성하는 헬퍼.
    private func makeFixture(statusShort: String) -> LiveFixture {
        LiveFixture(
            id:       1,
            homeTeam: LiveTeamInfo(id: 1, name: "홈팀", logoURL: nil),
            awayTeam: LiveTeamInfo(id: 2, name: "원정팀", logoURL: nil),
            score:    LiveScore(home: 0, away: 0),
            status:   LiveFixtureStatus(short: statusShort, elapsed: nil, period: nil),
            league:   LiveLeagueInfo(id: 1, name: "테스트리그", season: 2025),
            startTime: nil,
            periods:  []
        )
    }

    @Test("진행 중인 경기는 isLive == true")
    func isLiveWhenInProgress() {
        let fixture = makeFixture(statusShort: "2Q")
        #expect(fixture.isLive)
        #expect(!fixture.isUpcoming)
    }

    @Test("예정 경기는 isUpcoming == true")
    func isUpcomingWhenScheduled() {
        let fixture = makeFixture(statusShort: "NS")
        #expect(fixture.isUpcoming)
        #expect(!fixture.isLive)
    }
}
