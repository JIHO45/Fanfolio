//
//  PreReleaseScenarioTests.swift
//  FanfolioTests
//
//  출시 전 회귀용: 사용자에게 노출되는 오류·한도 문구와 빌드 설정 가정을 빠르게 검증합니다.
//

import Testing
@testable import Fanfolio

@Suite("출시 시나리오 — API·네트워크 메시지")
struct PreReleaseScenarioTests {

    @Test("APISportsError 주요 케이스에 비어 있지 않은 설명이 있다")
    func apiSportsErrorDescriptions() {
        let cases: [APISportsError] = [.noAPIKey, .rateLimitExceeded, .noData, .invalidURL]
        for err in cases {
            #expect(err.errorDescription != nil)
            #expect(!(err.errorDescription ?? "").isEmpty)
        }
    }

    @Test("APIRateLimiter 무료 티어 일일 호출 상한")
    @MainActor
    func apiRateLimiterMatchesFreeTier() {
        #expect(APIRateLimiter.shared.dailyLimit == 100)
    }

    @Test("NetworkMonitor 연결 유형 표시 이름이 비어 있지 않다")
    @MainActor
    func networkMonitorConnectionLabels() {
        for kind: NetworkMonitor.ConnectionType in [.wifi, .cellular, .other, .unknown] {
            #expect(!kind.displayName.isEmpty)
        }
    }
}
