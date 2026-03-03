//
//  FanfolioTests.swift
//  FanfolioTests
//
//  이 파일에는 특정 파일에 속하지 않는 공통 테스트나
//  종목 타입 관련 테스트를 모아둡니다.
//
//  다른 테스트 파일들:
//  → FanStatsCalculatorTests.swift  — 팬 통계 계산기 (승률, 연승 등)
//  → GolfRoundModelTests.swift      — 골프 라운드 계산 프로퍼티
//  → LiveFixtureStatusTests.swift   — API 경기 상태 코드 변환
//  → PlayerSeasonStatsTests.swift   — 선수 시즌 스텟 하이라이트
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

    @Test("아이스하키 3피리어드 레이블")
    func hockeyThreePeriods() {
        let labels = SportType.hockey.periodLabels(count: 3)
        #expect(labels == ["1P", "2P", "3P"])
    }

    @Test("아이스하키 연장 포함 4피리어드")
    func hockeyWithOvertime() {
        let labels = SportType.hockey.periodLabels(count: 4)
        #expect(labels == ["1P", "2P", "3P", "OT1"])
    }

    @Test("배구는 최소 5세트 보장")
    func volleyballMinimumFiveSets() {
        let labels = SportType.volleyball.periodLabels(count: 1)
        #expect(labels.count == 5)
        #expect(labels.first == "1세트")
        #expect(labels.last  == "5세트")
    }

    @Test("F1은 항상 '레이스' 레이블 하나")
    func f1SingleRace() {
        let labels = SportType.racing.periodLabels(count: 1)
        #expect(labels == ["레이스"])
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
