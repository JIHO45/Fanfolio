//
//  APIRateLimiter.swift
//  Fanfolio
//
//  API-Sports 무료 티어 하루 100회 호출 제한 관리.
//  UserDefaults에 카운트를 저장해 앱 재시작 후에도 유지됩니다.
//  자정 이후 자동으로 카운트가 리셋됩니다.
//

import Foundation
import Observation
import os.log

@MainActor
@Observable
final class APIRateLimiter {

    static let shared = APIRateLimiter()

    // MARK: - 상태

    private(set) var callCount: Int = 0

    var remainingCalls: Int { max(0, dailyLimit - callCount) }
    var isLimitReached: Bool { remainingCalls <= 0 }
    var usagePercentage: Double { min(1.0, Double(callCount) / Double(dailyLimit)) }

    // MARK: - 설정

    let dailyLimit: Int = 100

    // MARK: - 내부 저장 키

    private let countKey = "apiSports_dailyCallCount"
    private let dateKey  = "apiSports_lastResetDate"

    private var lastResetDate: Date = Date()

    // MARK: - 초기화

    private init() {
        restore()
    }

    // MARK: - 호출 소비

    /// API 호출 전 이 메서드를 실행하세요.
    /// - Returns: 호출 가능하면 `true`, 한도 초과 시 `false`
    @discardableResult
    func consume() -> Bool {
        resetIfNewDay()

        guard !isLimitReached else {
            Logger.api.warning("Rate limit reached: \(self.callCount)/\(self.dailyLimit). Try again tomorrow.")
            return false
        }

        callCount += 1
        persist()
        Logger.api.info("API call used: \(self.callCount)/\(self.dailyLimit) (\(self.remainingCalls) remaining)")
        return true
    }

    // MARK: - 수동 리셋 (디버그/테스트용)

    func resetForTesting() {
        callCount = 0
        lastResetDate = Date()
        persist()
        Logger.api.debug("Rate limiter manually reset")
    }

    // MARK: - 내부 메서드

    private func resetIfNewDay() {
        guard !Calendar.current.isDateInToday(lastResetDate) else { return }
        callCount = 0
        lastResetDate = Date()
        persist()
        Logger.api.info("Rate limit reset for new day")
    }

    private func persist() {
        UserDefaults.standard.set(callCount, forKey: countKey)
        UserDefaults.standard.set(lastResetDate, forKey: dateKey)
    }

    private func restore() {
        let defaults = UserDefaults.standard
        let savedDate = defaults.object(forKey: dateKey) as? Date ?? Date()

        if Calendar.current.isDateInToday(savedDate) {
            callCount = defaults.integer(forKey: countKey)
        } else {
            callCount = 0
        }
        lastResetDate = savedDate
        Logger.api.info("Rate limiter restored: \(self.callCount)/\(self.dailyLimit) used today")
    }
}
