//
//  LiveFixtureStatusTests.swift
//  FanfolioTests
//
//  LiveFixtureStatus의 상태 코드 변환 로직을 테스트합니다.
//
//  테스트 대상: isLive / isUpcoming / isFinished / displayText
//
//  왜 이걸 테스트해야 하나?
//  → API에서 "NS", "FT", "1Q" 같은 문자열을 받아 앱 로직으로 해석합니다.
//  → 새 종목이 추가될 때 상태 코드 누락으로 버그가 생기기 쉽습니다.
//  → 테스트가 있으면 새 코드를 추가할 때 기존 동작을 깨지 않았는지 자동 확인합니다.
//

import Foundation
import Testing
@testable import Fanfolio

@Suite("LiveFixtureStatus — API 경기 상태 코드 변환")
struct LiveFixtureStatusTests {

    // MARK: - isLive

    /// API에서 받는 라이브 상태 코드 목록:
    /// 농구/미식축구 쿼터: "1Q" "2Q" "3Q" "4Q"
    /// 연장: "OT"
    /// 축구: "HT"(하프타임) "1H"(전반) "2H"(후반)
    /// 일반 진행: "LIVE" "IN_PLAY"
    /// 야구 이닝: "1ST" "2ND" ... "9TH"

    @Test("농구 1쿼터 '1Q'는 라이브")
    func isLiveFirstQuarter() {
        #expect(LiveFixtureStatus(short: "1Q", elapsed: nil, period: nil).isLive)
    }

    @Test("하프타임 'HT'도 라이브로 분류")
    func isLiveHalfTime() {
        #expect(LiveFixtureStatus(short: "HT", elapsed: nil, period: nil).isLive)
    }

    @Test("'IN_PLAY' 코드는 라이브")
    func isLiveInPlay() {
        #expect(LiveFixtureStatus(short: "IN_PLAY", elapsed: nil, period: nil).isLive)
    }

    @Test("야구 1이닝 '1ST' 코드는 라이브")
    func isLiveBaseballFirstInning() {
        #expect(LiveFixtureStatus(short: "1ST", elapsed: nil, period: nil).isLive)
    }

    @Test("경기 전 'NS'는 라이브 아님")
    func isNotLiveScheduled() {
        #expect(!LiveFixtureStatus(short: "NS", elapsed: nil, period: nil).isLive)
    }

    @Test("경기 종료 'FT'는 라이브 아님")
    func isNotLiveFinished() {
        #expect(!LiveFixtureStatus(short: "FT", elapsed: nil, period: nil).isLive)
    }

    // MARK: - isUpcoming / isFinished

    @Test("'NS' (Not Started)는 예정 상태")
    func isUpcomingNS() {
        #expect(LiveFixtureStatus(short: "NS", elapsed: nil, period: nil).isUpcoming)
    }

    @Test("'TBD' (To Be Decided)도 예정 상태")
    func isUpcomingTBD() {
        #expect(LiveFixtureStatus(short: "TBD", elapsed: nil, period: nil).isUpcoming)
    }

    @Test("라이브 중인 경기는 예정 상태 아님")
    func isNotUpcomingWhenLive() {
        #expect(!LiveFixtureStatus(short: "2Q", elapsed: nil, period: nil).isUpcoming)
    }

    @Test("'FT' (Full Time)는 종료 상태")
    func isFinishedFT() {
        #expect(LiveFixtureStatus(short: "FT", elapsed: nil, period: nil).isFinished)
    }

    @Test("'AOT' (After OT)도 종료 상태")
    func isFinishedAOT() {
        #expect(LiveFixtureStatus(short: "AOT", elapsed: nil, period: nil).isFinished)
    }

    @Test("'F' (Finished) 코드도 종료 상태")
    func isFinishedF() {
        #expect(LiveFixtureStatus(short: "F", elapsed: nil, period: nil).isFinished)
    }

    @Test("'Final' 코드도 종료 상태")
    func isFinishedFinal() {
        #expect(LiveFixtureStatus(short: "Final", elapsed: nil, period: nil).isFinished)
    }

    // MARK: - displayText 포맷 변환

    /// API 코드를 `Localizable` 기준으로 locale별 화면 텍스트로 변환하는 로직을 검증합니다.

    /// String Catalog 항목은 `en` / `ko` 로컬라이제이션으로 등록되어 있음
    private let ko = Locale(identifier: "ko")
    private let en = Locale(identifier: "en")

    @Test("'NS' — ko: 예정 / en: Scheduled")
    func displayTextScheduled() {
        let s = LiveFixtureStatus(short: "NS", elapsed: nil, period: nil)
        #expect(s.displayText(for: ko) == "예정")
        #expect(s.displayText(for: en) == "Scheduled")
    }

    @Test("'1Q' — ko: 1쿼터 / en: 1st quarter")
    func displayTextFirstQuarter() {
        let s = LiveFixtureStatus(short: "1Q", elapsed: nil, period: nil)
        #expect(s.displayText(for: ko) == "1쿼터")
        #expect(s.displayText(for: en) == "1st quarter")
    }

    @Test("'2Q' — ko: 2쿼터 / en: 2nd quarter")
    func displayTextSecondQuarter() {
        let s = LiveFixtureStatus(short: "2Q", elapsed: nil, period: nil)
        #expect(s.displayText(for: ko) == "2쿼터")
        #expect(s.displayText(for: en) == "2nd quarter")
    }

    @Test("'OT' — ko: 연장 / en: OT")
    func displayTextOT() {
        let s = LiveFixtureStatus(short: "OT", elapsed: nil, period: nil)
        #expect(s.displayText(for: ko) == "연장")
        #expect(s.displayText(for: en) == "OT")
    }

    @Test("'HT' — ko: 하프타임 / en: Half-time")
    func displayTextHalfTime() {
        let s = LiveFixtureStatus(short: "HT", elapsed: nil, period: nil)
        #expect(s.displayText(for: ko) == "하프타임")
        #expect(s.displayText(for: en) == "Half-time")
    }

    @Test("'1H' / '2H' — scoreboard.period 키와 동일")
    func displayTextSoccerHalves() {
        let first = LiveFixtureStatus(short: "1H", elapsed: nil, period: nil)
        let second = LiveFixtureStatus(short: "2H", elapsed: nil, period: nil)
        #expect(first.displayText(for: ko) == "전반")
        #expect(first.displayText(for: en) == "1st half")
        #expect(second.displayText(for: ko) == "후반")
        #expect(second.displayText(for: en) == "2nd half")
    }

    @Test("'FT' — ko: 종료 / en: Final")
    func displayTextFinished() {
        let s = LiveFixtureStatus(short: "FT", elapsed: nil, period: nil)
        #expect(s.displayText(for: ko) == "종료")
        #expect(s.displayText(for: en) == "Final")
    }

    @Test("'AOT' — ko: 연장 종료 / en: Final (OT)")
    func displayTextAOT() {
        let s = LiveFixtureStatus(short: "AOT", elapsed: nil, period: nil)
        #expect(s.displayText(for: ko) == "연장 종료")
        #expect(s.displayText(for: en) == "Final (OT)")
    }

    @Test("알 수 없는 코드 + elapsed 있으면 분(프라임) 접미 — 예: 72′")
    func displayTextWithElapsed() {
        // "LIVE" 코드는 switch default로 빠지면서 elapsed 값을 사용합니다
        let status = LiveFixtureStatus(short: "LIVE", elapsed: 72, period: nil)
        #expect(status.displayText(for: ko) == "72′")
        #expect(status.displayText(for: en) == "72′")
    }

    @Test("KBO 'IN3' — 이닝 포맷은 scoreboard.inning.labelFormat")
    func displayTextApiInningIN3() {
        let s = LiveFixtureStatus(short: "IN3", elapsed: nil, period: nil)
        #expect(s.displayText(for: ko) == "3회")
        #expect(s.displayText(for: en) == "3")
    }

    @Test("알 수 없는 코드 + elapsed 없으면 코드 문자열 그대로 반환")
    func displayTextUnknownCodeNoElapsed() {
        let status = LiveFixtureStatus(short: "CUSTOM", elapsed: nil, period: nil)
        #expect(status.displayText == "CUSTOM")
    }
}
