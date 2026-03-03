//
//  PlayerSeasonStatsTests.swift
//  FanfolioTests
//
//  PlayerSeasonStats.highlights(for:) 메서드를 테스트합니다.
//
//  테스트 대상:
//  → 종목별 핵심 스텟 2~3개가 올바른 레이블·값으로 반환되는지
//  → 포맷 문자열(%.1f, %.3f)이 정확하게 적용되는지
//  → nil 스텟은 결과에서 제외되는지
//
//  의존성 분리의 좋은 예시:
//  PlayerSeasonStats는 struct로 순수 데이터만 담고 있어서
//  highlights()를 호출하는 데 네트워크·DB·View가 전혀 필요 없습니다.
//

import Testing
@testable import Fanfolio

@Suite("PlayerSeasonStats — 종목별 핵심 스텟 하이라이트")
struct PlayerSeasonStatsTests {

    // MARK: 헬퍼

    /// 특정 종목 스텟만 채우고 나머지는 nil로 설정하는 헬퍼들.
    /// PlayerSeasonStats 이니셜라이저는 필드가 많아서
    /// 헬퍼로 감싸면 테스트 코드가 훨씬 읽기 쉬워집니다.

    private func makeSoccerStats(
        goals: Int?, assists: Int?, minutesPlayed: Int? = nil
    ) -> PlayerSeasonStats {
        PlayerSeasonStats(
            gamesPlayed: nil,
            passingTouchdowns: nil, passingYards: nil,
            rushingTouchdowns: nil, rushingYards: nil,
            receptions: nil, receivingYards: nil, receivingTouchdowns: nil,
            sacks: nil, interceptions: nil,
            goals: goals, assists: assists,
            yellowCards: nil, redCards: nil,
            minutesPlayed: minutesPlayed, shotsOnTarget: nil,
            points: nil, rebounds: nil, basketballAssists: nil,
            steals: nil, blocks: nil,
            battingAvg: nil, homeRuns: nil, rbi: nil, era: nil,
            strikeouts: nil, wins: nil,
            raceWins: nil, podiums: nil, championshipPoints: nil, polePositions: nil
        )
    }

    private func makeBasketballStats(
        points: Double?, rebounds: Double?, assists: Double?
    ) -> PlayerSeasonStats {
        PlayerSeasonStats(
            gamesPlayed: nil,
            passingTouchdowns: nil, passingYards: nil,
            rushingTouchdowns: nil, rushingYards: nil,
            receptions: nil, receivingYards: nil, receivingTouchdowns: nil,
            sacks: nil, interceptions: nil,
            goals: nil, assists: nil,
            yellowCards: nil, redCards: nil,
            minutesPlayed: nil, shotsOnTarget: nil,
            points: points, rebounds: rebounds, basketballAssists: assists,
            steals: nil, blocks: nil,
            battingAvg: nil, homeRuns: nil, rbi: nil, era: nil,
            strikeouts: nil, wins: nil,
            raceWins: nil, podiums: nil, championshipPoints: nil, polePositions: nil
        )
    }

    private func makeBaseballStats(
        battingAvg: Double?, homeRuns: Int?, rbi: Int?, era: Double? = nil
    ) -> PlayerSeasonStats {
        PlayerSeasonStats(
            gamesPlayed: nil,
            passingTouchdowns: nil, passingYards: nil,
            rushingTouchdowns: nil, rushingYards: nil,
            receptions: nil, receivingYards: nil, receivingTouchdowns: nil,
            sacks: nil, interceptions: nil,
            goals: nil, assists: nil,
            yellowCards: nil, redCards: nil,
            minutesPlayed: nil, shotsOnTarget: nil,
            points: nil, rebounds: nil, basketballAssists: nil,
            steals: nil, blocks: nil,
            battingAvg: battingAvg, homeRuns: homeRuns, rbi: rbi, era: era,
            strikeouts: nil, wins: nil,
            raceWins: nil, podiums: nil, championshipPoints: nil, polePositions: nil
        )
    }

    private func makeF1Stats(
        raceWins: Int?, podiums: Int?, points: Int?
    ) -> PlayerSeasonStats {
        PlayerSeasonStats(
            gamesPlayed: nil,
            passingTouchdowns: nil, passingYards: nil,
            rushingTouchdowns: nil, rushingYards: nil,
            receptions: nil, receivingYards: nil, receivingTouchdowns: nil,
            sacks: nil, interceptions: nil,
            goals: nil, assists: nil,
            yellowCards: nil, redCards: nil,
            minutesPlayed: nil, shotsOnTarget: nil,
            points: nil, rebounds: nil, basketballAssists: nil,
            steals: nil, blocks: nil,
            battingAvg: nil, homeRuns: nil, rbi: nil, era: nil,
            strikeouts: nil, wins: nil,
            raceWins: raceWins, podiums: podiums, championshipPoints: points, polePositions: nil
        )
    }

    // MARK: - 축구 하이라이트

    @Test("축구: 골, 어시스트, 출전 시간 하이라이트 반환")
    func soccerHighlightsAll() {
        let stats = makeSoccerStats(goals: 15, assists: 8, minutesPlayed: 2520)
        let highlights = stats.highlights(for: .soccer)

        // 최대 3개 반환
        #expect(highlights.count <= 3)

        let goalEntry    = highlights.first { $0.0 == "골" }
        let assistEntry  = highlights.first { $0.0 == "어시스트" }
        let minuteEntry  = highlights.first { $0.0 == "출전 시간" }

        #expect(goalEntry?.1   == "15")
        #expect(assistEntry?.1 == "8")
        #expect(minuteEntry?.1 == "2520'")
    }

    @Test("축구: 골만 있으면 어시스트 항목은 결과에 없음")
    func soccerHighlightsGoalOnly() {
        let stats = makeSoccerStats(goals: 10, assists: nil)
        let highlights = stats.highlights(for: .soccer)

        #expect(highlights.contains { $0.0 == "골" })
        #expect(!highlights.contains { $0.0 == "어시스트" })
    }

    // MARK: - 농구(NBA) 하이라이트

    @Test("농구: 득점 소수점 1자리 포맷 확인 ('27.5')")
    func basketballHighlightsPointsFormat() {
        let stats = makeBasketballStats(points: 27.5, rebounds: 8.2, assists: 6.3)
        let highlights = stats.highlights(for: .basketball)

        let pointEntry = highlights.first { $0.0 == "득점" }
        // %.1f 포맷이므로 "27.5"가 나와야 합니다
        #expect(pointEntry?.1 == "27.5")

        let reboundEntry = highlights.first { $0.0 == "리바운드" }
        #expect(reboundEntry?.1 == "8.2")

        let assistEntry = highlights.first { $0.0 == "어시스트" }
        #expect(assistEntry?.1 == "6.3")
    }

    @Test("농구: 소수점이 0이어도 '20.0' 형태로 표시")
    func basketballHighlightsRoundNumber() {
        let stats = makeBasketballStats(points: 20.0, rebounds: nil, assists: nil)
        let highlights = stats.highlights(for: .basketball)

        let pointEntry = highlights.first { $0.0 == "득점" }
        // "20"이 아니라 "20.0"이어야 합니다 (%.1f 포맷)
        #expect(pointEntry?.1 == "20.0")
    }

    // MARK: - 야구 하이라이트

    @Test("야구: 타율은 소수점 3자리 포맷 ('0.315')")
    func baseballBattingAverageFormat() {
        let stats = makeBaseballStats(battingAvg: 0.315, homeRuns: 28, rbi: 95)
        let highlights = stats.highlights(for: .baseball)

        let avgEntry = highlights.first { $0.0 == "타율" }
        // %.3f 포맷이므로 "0.315"가 나와야 합니다
        #expect(avgEntry?.1 == "0.315")

        let hrEntry  = highlights.first { $0.0 == "홈런" }
        #expect(hrEntry?.1 == "28")

        let rbiEntry = highlights.first { $0.0 == "타점" }
        #expect(rbiEntry?.1 == "95")
    }

    @Test("야구: ERA는 소수점 2자리 포맷 ('3.14')")
    func baseballERAFormat() {
        // 타자 스텟 없고 투수 ERA만 있는 경우
        let stats = makeBaseballStats(battingAvg: nil, homeRuns: nil, rbi: nil, era: 3.14)
        let highlights = stats.highlights(for: .baseball)

        let eraEntry = highlights.first { $0.0 == "ERA" }
        // %.2f 포맷이므로 "3.14"
        #expect(eraEntry?.1 == "3.14")
    }

    // MARK: - F1 하이라이트

    @Test("F1: 우승, 포디움, 포인트 하이라이트 반환")
    func f1HighlightsAll() {
        let stats = makeF1Stats(raceWins: 12, podiums: 16, points: 575)
        let highlights = stats.highlights(for: .racing)

        let winEntry    = highlights.first { $0.0 == "우승" }
        let podiumEntry = highlights.first { $0.0 == "포디움" }
        let ptsEntry    = highlights.first { $0.0 == "포인트" }

        #expect(winEntry?.1    == "12")
        #expect(podiumEntry?.1 == "16")
        #expect(ptsEntry?.1    == "575")
    }

    // MARK: - 스텟 없을 때

    @Test("모든 스텟이 nil이면 빈 배열 반환")
    func highlightsEmptyWhenAllNil() {
        let stats = makeSoccerStats(goals: nil, assists: nil)
        #expect(stats.highlights(for: .soccer).isEmpty)
    }

    @Test("지원하지 않는 종목(MMA 등)은 빈 배열 반환")
    func highlightsEmptyForUnsupportedSport() {
        let stats = makeSoccerStats(goals: 5, assists: 3)
        // .mma, .eSports 등은 default case로 빈 배열 반환
        #expect(stats.highlights(for: .mma).isEmpty)
        #expect(stats.highlights(for: .eSports).isEmpty)
    }
}
