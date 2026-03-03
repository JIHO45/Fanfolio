//
//  FanStatsCalculatorTests.swift
//  FanfolioTests
//
//  ============================================================
//  유닛 테스트 기초 개념 — 이 파일을 읽기 전에 먼저 읽으세요
//  ============================================================
//
//  유닛 테스트(Unit Test)란?
//  → 코드의 작은 단위(함수, 계산 프로퍼티 등)가 올바르게
//    동작하는지 자동으로 확인하는 코드입니다.
//
//  Swift Testing 기본 문법:
//  → @Test          테스트 함수 표시
//  → #expect(조건)  조건이 거짓이면 테스트 실패로 기록
//  → #require(값)   nil이면 즉시 테스트 중단 (강제 언래핑 대신 사용)
//
//  AAA 패턴 (모든 테스트가 따르는 구조):
//  → Arrange(준비) → Act(실행) → Assert(검증)
//
//  좋은 테스트 이름 규칙:
//  → "무엇을 테스트하는가"를 한 문장으로 서술합니다.
//  → 예) "3승 1패면 승률은 75%", "무승부는 연승을 끊는다"
//  ============================================================
//

import Testing
import Foundation
@testable import Fanfolio  // @testable: internal 타입까지 테스트에서 접근 가능

// MARK: - FanStatsCalculator 테스트

/// FanStatsCalculator의 핵심 계산 로직을 검증하는 테스트 묶음.
///
/// 이 테스트들이 의미있는 이유:
/// - "승률이 맞는지" 직접 손으로 계산한 결과와 코드 출력이 일치하는지 자동 확인
/// - 나중에 로직을 수정해도 이 테스트들이 통과하면 기존 동작이 깨지지 않았다는 증거
@Suite("FanStatsCalculator — 팬 통계 계산기")
struct FanStatsCalculatorTests {

    // MARK: 헬퍼 함수

    /// 테스트용 SportsModel 인스턴스를 빠르게 만드는 헬퍼 함수.
    ///
    /// **헬퍼 함수를 사용하는 이유:**
    /// SportsModel의 생성자는 매개변수가 많습니다.
    /// 테스트마다 모든 인자를 나열하면 코드가 길어지고
    /// 핵심 의도가 묻혀버립니다. 헬퍼로 묶으면
    /// 테스트 본문이 "3승 1패" 같은 핵심 시나리오만 담게 됩니다.
    private func makeMatch(
        result:        MatchResult,
        status:        MatchStatus = .completed,   // 기본값: 완료 상태
        opponent:      String = "상대팀",
        opponentScore: Int = 0,
        daysAgo:       Int = 0                     // 오늘부터 며칠 전인지
    ) -> SportsModel {
        SportsModel(
            title:         "테스트 경기",
            opponentTeam:  opponent,
            myTeamScore:   result == .win ? 1 : 0,
            opponentScore: opponentScore,
            matchResult:   result,
            matchStatus:   status,
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())
        )
    }

    // MARK: - 승률(winRate) 테스트

    @Test("완료 경기가 없으면 승률은 0")
    func winRateWhenNoCompletedMatches() {
        // Arrange: 예정·진행 중 경기만 있고 완료 경기는 없는 상황
        let matches = [
            makeMatch(result: .win, status: .upcoming),
            makeMatch(result: .win, status: .live),
        ]
        let calc = FanStatsCalculator(matches: matches)

        // Assert: 완료 경기 0개 → 승률 0, 총 완료 수 0
        #expect(calc.winRate == 0)
        #expect(calc.totalCompleted == 0)
    }

    @Test("경기 기록이 아예 없으면 승률은 0")
    func winRateWhenEmptyArray() {
        let calc = FanStatsCalculator(matches: [])
        #expect(calc.winRate == 0)
    }

    @Test("3승 1패면 승률은 75%")
    func winRateThreeWinsOneLoss() {
        // Arrange
        let matches = [
            makeMatch(result: .win),
            makeMatch(result: .win),
            makeMatch(result: .win),
            makeMatch(result: .loss),
        ]
        let calc = FanStatsCalculator(matches: matches)

        // Assert
        #expect(calc.wins   == 3)
        #expect(calc.losses == 1)
        #expect(calc.draws  == 0)
        #expect(calc.winRate == 75.0)
    }

    @Test("1승 1무 2패면 승률은 25%")
    func winRateMixedResults() {
        let matches = [
            makeMatch(result: .win),
            makeMatch(result: .draw),
            makeMatch(result: .loss),
            makeMatch(result: .loss),
        ]
        let calc = FanStatsCalculator(matches: matches)
        #expect(calc.draws  == 1)
        #expect(calc.winRate == 25.0)
    }

    @Test("무승부는 승패에 포함되지 않지만 totalCompleted에는 포함")
    func drawCountsAsCompleted() {
        let matches = [makeMatch(result: .draw)]
        let calc = FanStatsCalculator(matches: matches)
        #expect(calc.totalCompleted == 1)
        #expect(calc.wins   == 0)
        #expect(calc.losses == 0)
        #expect(calc.draws  == 1)
    }

    // MARK: - 최대 연승(maxWinStreak) 테스트

    @Test("경기가 없으면 최대 연승은 0")
    func maxStreakNoMatches() {
        #expect(FanStatsCalculator(matches: []).maxWinStreak == 0)
    }

    @Test("전부 패배면 최대 연승은 0")
    func maxStreakAllLosses() {
        let matches = [
            makeMatch(result: .loss, daysAgo: 2),
            makeMatch(result: .loss, daysAgo: 1),
        ]
        #expect(FanStatsCalculator(matches: matches).maxWinStreak == 0)
    }

    @Test("연속 3승이면 최대 연승은 3")
    func maxStreakThreeConsecutiveWins() {
        // daysAgo를 다르게 설정해 날짜 정렬 순서를 명확하게 합니다
        let matches = [
            makeMatch(result: .win, daysAgo: 2),
            makeMatch(result: .win, daysAgo: 1),
            makeMatch(result: .win, daysAgo: 0),
        ]
        #expect(FanStatsCalculator(matches: matches).maxWinStreak == 3)
    }

    @Test("2승-패배-3승 패턴에서 최대 연승은 3")
    func maxStreakWithBreak() {
        // 승-승-패(연승 끊김)-승-승-승 순서
        let matches = [
            makeMatch(result: .win,  daysAgo: 5),
            makeMatch(result: .win,  daysAgo: 4),
            makeMatch(result: .loss, daysAgo: 3),  // 여기서 연승 초기화
            makeMatch(result: .win,  daysAgo: 2),
            makeMatch(result: .win,  daysAgo: 1),
            makeMatch(result: .win,  daysAgo: 0),
        ]
        #expect(FanStatsCalculator(matches: matches).maxWinStreak == 3)
    }

    @Test("무승부는 연승을 끊는다")
    func maxStreakBrokenByDraw() {
        // 승-무(연승 끊김)-승 → 최대 연승 1
        let matches = [
            makeMatch(result: .win,  daysAgo: 2),
            makeMatch(result: .draw, daysAgo: 1),
            makeMatch(result: .win,  daysAgo: 0),
        ]
        #expect(FanStatsCalculator(matches: matches).maxWinStreak == 1)
    }

    @Test("승리 1경기만 있으면 최대 연승은 1")
    func maxStreakSingleWin() {
        let matches = [makeMatch(result: .win)]
        #expect(FanStatsCalculator(matches: matches).maxWinStreak == 1)
    }

    // MARK: - 상대별 전적(opponentRecords) 테스트

    @Test("두 상대팀에 대한 전적을 올바르게 그룹화")
    func opponentRecordsGrouping() throws {
        let matches = [
            makeMatch(result: .win,  opponent: "두산"),
            makeMatch(result: .win,  opponent: "두산"),
            makeMatch(result: .loss, opponent: "두산"),
            makeMatch(result: .win,  opponent: "SSG"),
        ]
        let records = FanStatsCalculator(matches: matches).opponentRecords

        // #require: nil이면 테스트 즉시 중단 (안전한 언래핑)
        let doosan = try #require(records.first { $0.name == "두산" })
        #expect(doosan.wins   == 2)
        #expect(doosan.losses == 1)
        #expect(doosan.total  == 3)

        let ssg = try #require(records.first { $0.name == "SSG" })
        #expect(ssg.wins  == 1)
        #expect(ssg.total == 1)
    }

    @Test("상대별 전적은 총 경기 수 내림차순으로 정렬")
    func opponentRecordsSortedByTotal() {
        let matches = [
            makeMatch(result: .win,  opponent: "한화"),  // 한화: 1경기
            makeMatch(result: .win,  opponent: "두산"),
            makeMatch(result: .loss, opponent: "두산"),
            makeMatch(result: .win,  opponent: "두산"),  // 두산: 3경기
        ]
        let records = FanStatsCalculator(matches: matches).opponentRecords

        // 두산(3경기)이 한화(1경기)보다 앞에 와야 합니다
        #expect(records.first?.name == "두산")
    }

    // MARK: - 럭키팬 지수(luckyInfo) 테스트

    @Test("경기 기록이 없으면 '불굴의 팬' (기본값)")
    func luckyInfoDefaultWhenEmpty() {
        let info = FanStatsCalculator(matches: []).luckyInfo
        #expect(info.title == "불굴의 팬")
    }

    @Test("승률 80% 이상이면 '전설의 럭키팬'")
    func luckyInfoLegendary() {
        // 8승 2패 = 80% (경계값 포함 확인)
        let matches = (0..<8).map { makeMatch(result: .win,  daysAgo: $0) }
                   + (0..<2).map { makeMatch(result: .loss, daysAgo: $0 + 8) }
        let info = FanStatsCalculator(matches: matches).luckyInfo
        #expect(info.title == "전설의 럭키팬")
    }

    @Test("승률 60%면 '복 받은 팬' (50~65% 구간)")
    func luckyInfoBlessed() {
        // 6승 4패 = 60%
        let matches = (0..<6).map { makeMatch(result: .win,  daysAgo: $0) }
                   + (0..<4).map { makeMatch(result: .loss, daysAgo: $0 + 6) }
        let info = FanStatsCalculator(matches: matches).luckyInfo
        #expect(info.title == "복 받은 팬")
    }

    @Test("승률 45%면 '분투의 팬' (40~50% 구간)")
    func luckyInfoFighting() {
        // 9승 11패 = 45%
        let matches = (0..<9).map  { makeMatch(result: .win,  daysAgo: $0) }
                   + (0..<11).map { makeMatch(result: .loss, daysAgo: $0 + 9) }
        let info = FanStatsCalculator(matches: matches).luckyInfo
        #expect(info.title == "분투의 팬")
    }
}

// MARK: - OpponentRecord 단위 테스트

/// OpponentRecord 구조체 자체의 계산 프로퍼티를 독립적으로 검증합니다.
///
/// FanStatsCalculator 없이 OpponentRecord만 생성해서 테스트하는 방식으로,
/// 작은 단위를 격리(isolation)해서 테스트하는 좋은 예시입니다.
@Suite("OpponentRecord — 상대별 전적 모델")
struct OpponentRecordTests {

    @Test("경기가 없으면 승률은 0 (0으로 나누기 방지)")
    func winRateZeroWhenNoMatches() {
        let record = OpponentRecord(name: "상대", wins: 0, losses: 0, draws: 0)
        #expect(record.winRate == 0)
        #expect(record.total   == 0)
    }

    @Test("3전 2승이면 승률 약 66.7%")
    func winRateTwoOutOfThree() {
        let record = OpponentRecord(name: "상대", wins: 2, losses: 1, draws: 0)
        // 부동소수점(Double) 비교는 오차 범위(허용오차)를 두고 비교합니다.
        // 2/3 * 100 = 66.666...이므로 정확히 66.666과 차이가 0.01 미만인지 확인
        #expect(abs(record.winRate - 66.666) < 0.01)
    }

    @Test("total은 승+패+무의 합")
    func totalIsSum() {
        let record = OpponentRecord(name: "상대", wins: 3, losses: 2, draws: 1)
        #expect(record.total == 6)
    }
}
