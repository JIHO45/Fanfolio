//
//  NetworkRetry.swift
//  Fanfolio
//
//  지수 백오프(Exponential Backoff) 재시도 헬퍼.
//  일시적인 네트워크 오류 시 자동으로 재시도합니다.
//

import Foundation
import os.log

/// 지수 백오프 재시도 실행
/// - Parameters:
///   - maxAttempts: 최대 시도 횟수 (기본 3회)
///   - initialDelay: 첫 재시도 대기 시간 초 (기본 1.0s)
///   - multiplier: 대기 시간 배수 (기본 2.0배 → 1s, 2s, 4s...)
///   - operation: 실행할 비동기 작업 (첫 번째 trailing closure)
///   - shouldRetry: 에러를 받아 재시도 여부를 결정하는 클로저 (두 번째 trailing closure)
/// - Returns: 성공 시 결과값
/// - Throws: 모든 재시도 실패 또는 재시도 불가 에러
func withRetry<T>(
    maxAttempts: Int = 3,
    initialDelay: TimeInterval = 1.0,
    multiplier: Double = 2.0,
    operation: () async throws -> T,
    shouldRetry: (Error) -> Bool = { _ in true }
) async throws -> T {
    var delay = initialDelay
    var lastError: Error?

    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            // Task 취소는 즉시 rethrow
            if error is CancellationError { throw error }

            lastError = error

            // shouldRetry가 false이거나 마지막 시도면 즉시 throw
            guard shouldRetry(error), attempt < maxAttempts else {
                throw error
            }

            Logger.api.warning(
                "Attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription). Retrying in \(String(format: "%.1f", delay))s..."
            )

            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            delay *= multiplier
        }
    }

    throw lastError!
}
