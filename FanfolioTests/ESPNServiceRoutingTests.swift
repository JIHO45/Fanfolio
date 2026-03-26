//
//  ESPNServiceRoutingTests.swift
//  FanfolioTests
//
//  ESPN / API-Sports 라우팅 로직을 테스트합니다.
//
//  테스트 대상:
//  → ESPNPlayerService.supportsLiveScoreboard(_:)
//      — 리그 코드 기준으로 ESPN 실시간 스코어보드 지원 여부 판단
//  → APISportsService.nonESPNLeagues
//      — ESPN이 지원하지 않아 API-Sports 로 처리해야 하는 리그 집합
//
//  왜 이걸 테스트해야 하나?
//  → 리그 코드가 잘못 분류되면 API-Sports의 하루 100회 제한을
//    미국 리그에 낭비하거나, 비미국 리그 경기가 안 뜨는 버그가 생깁니다.
//  → 새 리그를 추가할 때 어디에 넣어야 하는지 명확한 기준이 됩니다.
//

import Testing
@testable import Fanfolio

// MARK: - ESPNPlayerService.supportsLiveScoreboard 테스트

/// ESPN 팀 스포츠 스코어보드 지원 여부를 검증합니다.
///
/// `supportsLiveScoreboard`는 `nonisolated` 동기 함수이므로
/// actor isolation 없이 직접 호출할 수 있습니다.
@Suite("ESPNPlayerService — supportsLiveScoreboard")
struct ESPNLiveScoreboardSupportTests {

    // MARK: ESPN 지원 리그 (true 기대)

    @Test("NFL은 ESPN 스코어보드 지원")
    func nflIsSupported() {
        #expect(ESPNPlayerService.shared.supportsLiveScoreboard("NFL"))
    }

    @Test("NBA는 ESPN 스코어보드 지원")
    func nbaIsSupported() {
        #expect(ESPNPlayerService.shared.supportsLiveScoreboard("NBA"))
    }

    @Test("MLB는 ESPN 스코어보드 지원")
    func mlbIsSupported() {
        #expect(ESPNPlayerService.shared.supportsLiveScoreboard("MLB"))
    }

    @Test("EPL(ENG.1)은 ESPN 스코어보드 지원")
    func eplIsSupported() {
        #expect(ESPNPlayerService.shared.supportsLiveScoreboard("ENG.1"))
    }

    // MARK: ESPN 미지원 리그 (false 기대)

    @Test("KBO(한국 야구)는 ESPN 스코어보드 미지원")
    func kboIsNotSupported() {
        #expect(!ESPNPlayerService.shared.supportsLiveScoreboard("KBO"))
    }

    @Test("알 수 없는 리그 코드는 미지원으로 처리")
    func unknownLeagueIsNotSupported() {
        #expect(!ESPNPlayerService.shared.supportsLiveScoreboard("UNKNOWN_LEAGUE"))
    }
}

// MARK: - APISportsService.nonESPNLeagues 테스트

/// ESPN이 지원하지 않아 API-Sports를 사용해야 하는 리그 집합을 검증합니다.
///
/// 이 집합에 포함된 리그만 API-Sports 호출로 라이브 스코어를 가져오므로
/// 하루 100회 제한을 지키는 핵심 방어선입니다.
@Suite("APISportsService — nonESPNLeagues 리그 분류")
@MainActor
struct APISportsNonESPNLeaguesTests {

    // MARK: 비ESPN 리그 (포함 기대)

    @Test("KBO(한국 야구)는 API-Sports 담당")
    func kboIsNonESPN() {
        #expect(APISportsService.nonESPNLeagues.contains("KBO"))
    }

    @Test("KBL(한국 농구)는 API-Sports 담당")
    func kblIsNonESPN() {
        #expect(APISportsService.nonESPNLeagues.contains("KBL"))
    }

    @Test("EPL(ENG.1)은 API-Sports 담당")
    func eplIsNonESPN() {
        #expect(APISportsService.nonESPNLeagues.contains("ENG.1"))
    }

    @Test("라리가(ESP.1)는 API-Sports 담당")
    func laLigaIsNonESPN() {
        #expect(APISportsService.nonESPNLeagues.contains("ESP.1"))
    }

    @Test("에레디비시(NED.1)는 API-Sports 담당")
    func eredivisieIsNonESPN() {
        #expect(APISportsService.nonESPNLeagues.contains("NED.1"))
    }

    @Test("프리메이라리가(POR.1)는 API-Sports 담당")
    func primeiraLigaIsNonESPN() {
        #expect(APISportsService.nonESPNLeagues.contains("POR.1"))
    }

    @Test("UEFA 챔피언스리그는 전용 데이터 없음 (팀은 국내 리그 기준)")
    func uclIsNotNonESPN() {
        #expect(!APISportsService.nonESPNLeagues.contains("UEFA.CHAMPIONS"))
    }

    // MARK: 미국 4대 스포츠 (미포함 기대 — ESPN 담당)

    @Test("NFL은 API-Sports 담당 아님 (ESPN 전용)")
    func nflIsNotNonESPN() {
        #expect(!APISportsService.nonESPNLeagues.contains("NFL"))
    }

    @Test("NBA는 API-Sports 담당 아님 (ESPN 전용)")
    func nbaIsNotNonESPN() {
        #expect(!APISportsService.nonESPNLeagues.contains("NBA"))
    }

    @Test("MLB는 API-Sports 담당 아님 (ESPN 전용)")
    func mlbIsNotNonESPN() {
        #expect(!APISportsService.nonESPNLeagues.contains("MLB"))
    }

}
