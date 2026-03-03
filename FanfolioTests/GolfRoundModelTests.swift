//
//  GolfRoundModelTests.swift
//  FanfolioTests
//
//  GolfRoundModel의 계산 프로퍼티를 테스트합니다.
//
//  이 테스트들이 좋은 이유:
//  → 입력(totalScore, par)과 출력(scoreToPar, scoreToParText)이 명확합니다.
//  → 직접 계산해보면 "72 - 70 = -2 (언더파)" 처럼 정답을 알 수 있습니다.
//  → 코드의 포맷 문자열("E", "+2", "-3")이 올바른지 확인합니다.
//

import Testing
import Foundation
@testable import Fanfolio

@Suite("GolfRoundModel — 골프 라운드 계산 프로퍼티")
struct GolfRoundModelTests {

    // MARK: 헬퍼

    /// par와 totalScore만 지정한 최소한의 GolfRoundModel을 생성합니다.
    private func makeRound(
        total: Int?,
        par:   Int?,
        holes: Int = 18
    ) -> GolfRoundModel {
        GolfRoundModel(
            title:        "테스트 라운드",
            numberOfHoles: holes,
            totalScore:   total,
            par:          par
        )
    }

    // MARK: - scoreToPar 계산

    @Test("파 72에 70타면 scoreToPar == -2 (언더파)")
    func scoreToParUnderPar() throws {
        let round = makeRound(total: 70, par: 72)

        // #require로 nil 아님을 보장한 뒤 값을 사용합니다
        let diff = try #require(round.scoreToPar)
        #expect(diff == -2)
        #expect(round.isUnderPar)
        #expect(!round.isEvenPar)
    }

    @Test("파 72에 72타면 이븐파 (scoreToPar == 0)")
    func scoreToParEven() {
        let round = makeRound(total: 72, par: 72)
        #expect(round.scoreToPar == 0)
        #expect(round.isEvenPar)
        #expect(!round.isUnderPar)
    }

    @Test("파 72에 76타면 +4 오버파")
    func scoreToParOverPar() {
        let round = makeRound(total: 76, par: 72)
        #expect(round.scoreToPar == 4)
        #expect(!round.isUnderPar)
        #expect(!round.isEvenPar)
    }

    @Test("totalScore가 nil이면 scoreToPar는 nil (계산 불가)")
    func scoreToParNilWhenNoScore() {
        let round = makeRound(total: nil, par: 72)
        #expect(round.scoreToPar == nil)
        #expect(!round.isUnderPar)
        #expect(!round.isEvenPar)
    }

    @Test("par가 nil이어도 scoreToPar는 nil")
    func scoreToParNilWhenNoPar() {
        let round = makeRound(total: 72, par: nil)
        #expect(round.scoreToPar == nil)
    }

    // MARK: - scoreToParText 포맷 검증

    /// 포맷 로직:
    ///   diff < 0  → "-3" (음수 그대로)
    ///   diff == 0 → "E"  (Even의 약자)
    ///   diff > 0  → "+2" (플러스 기호 추가)
    ///   nil       → "-"  (데이터 없음)

    @Test("언더파는 '-3'처럼 음수 그대로 표시")
    func scoreToParTextUnderPar() {
        let round = makeRound(total: 69, par: 72)
        #expect(round.scoreToParText == "-3")
    }

    @Test("이븐파는 'E'로 표시")
    func scoreToParTextEven() {
        let round = makeRound(total: 72, par: 72)
        #expect(round.scoreToParText == "E")
    }

    @Test("오버파는 '+2'처럼 플러스 기호와 함께 표시")
    func scoreToParTextOverPar() {
        let round = makeRound(total: 74, par: 72)
        #expect(round.scoreToParText == "+2")
    }

    @Test("스코어/파 없으면 '-' 표시")
    func scoreToParTextNilBothNil() {
        let round = makeRound(total: nil, par: nil)
        #expect(round.scoreToParText == "-")
    }

    // MARK: - 페어웨이 안착률 텍스트

    /// 파3 홀은 드라이버를 치지 않으므로 제외합니다.
    ///   18홀 → 파3 홀 4개 제외 → 14홀이 분모
    ///    9홀 → 파3 홀 2개 제외 →  7홀이 분모

    @Test("18홀에서 9개 적중하면 '9/14'")
    func fairwayRate18Holes() {
        let round = GolfRoundModel(title: "라운드", numberOfHoles: 18, fairwaysHit: 9)
        #expect(round.fairwayHitRateText == "9/14")
    }

    @Test("9홀에서 5개 적중하면 '5/7'")
    func fairwayRate9Holes() {
        let round = GolfRoundModel(title: "라운드", numberOfHoles: 9, fairwaysHit: 5)
        #expect(round.fairwayHitRateText == "5/7")
    }

    @Test("페어웨이 데이터 없으면 nil 반환")
    func fairwayRateNilWhenNotSet() {
        let round = makeRound(total: nil, par: nil)
        // fairwaysHit을 설정하지 않았으므로 nil이어야 합니다
        #expect(round.fairwayHitRateText == nil)
    }

    // MARK: - 순위 텍스트

    @Test("1위면 '1위' 표시")
    func positionTextFirstPlace() {
        let round = GolfRoundModel(title: "대회", myPosition: 1)
        #expect(round.positionText == "1위")
    }

    @Test("10위면 '10위' 표시")
    func positionTextTenth() {
        let round = GolfRoundModel(title: "대회", myPosition: 10)
        #expect(round.positionText == "10위")
    }

    @Test("순위 없으면 '-' 표시")
    func positionTextNilWhenNotSet() {
        let round = GolfRoundModel(title: "일반 라운드")
        #expect(round.positionText == "-")
    }

    // MARK: - 세부 스코어 입력 여부

    @Test("버디 수를 입력하면 hasDetailScore가 true")
    func hasDetailScoreWhenBirdieSet() {
        let round = GolfRoundModel(title: "라운드", birdieCount: 3)
        #expect(round.hasDetailScore)
    }

    @Test("세부 스코어를 입력하지 않으면 hasDetailScore가 false")
    func hasDetailScoreFalseWhenNotSet() {
        let round = GolfRoundModel(title: "라운드")
        #expect(!round.hasDetailScore)
    }

    // MARK: - 홀 수 텍스트

    @Test("18홀이면 '18홀' 텍스트")
    func holesText18() {
        let round = GolfRoundModel(title: "라운드", numberOfHoles: 18)
        #expect(round.holesText == "18홀")
    }

    @Test("9홀이면 '9홀' 텍스트")
    func holesText9() {
        let round = GolfRoundModel(title: "라운드", numberOfHoles: 9)
        #expect(round.holesText == "9홀")
    }
}
