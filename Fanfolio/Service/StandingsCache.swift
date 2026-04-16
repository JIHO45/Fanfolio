//
//  StandingsCache.swift
//  Fanfolio
//
//  순위표 인메모리 캐시(TTL) + 동시 요청 합치기(in-flight dedup).
//

import Foundation

actor StandingsCache {

    static let shared = StandingsCache()

    /// 기본 TTL (초 단위 갱신이 불필요한 순위 데이터용)
    private let ttl: TimeInterval = 45 * 60

    private var entries: [String: (payload: LeagueStandingsPayload, expiry: Date)] = [:]
    /// `leagueCode` → 마지막으로 성공한 페치의 캐시 키 (조회 시 시즌 메타 없이 히트 가능)
    private var lastKeyByLeague: [String: StandingsCacheKey] = [:]
    private var inFlight: [String: Task<LeagueStandingsFetchResult, Error>] = [:]

    /// `forceRefresh == true`일 때만 TTL을 무시하고 네트워크를 태웁니다(당겨서 새로고침 등).
    func payload(leagueCode: String, forceRefresh: Bool) async throws -> LeagueStandingsPayload {
        let code = leagueCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            throw ESPNServiceError.unsupportedLeague(leagueCode)
        }

        if !forceRefresh,
           let key = lastKeyByLeague[code],
           let entry = entries[key.storageKey],
           entry.expiry > Date() {
            return entry.payload
        }

        if let task = inFlight[code] {
            let result = try await task.value
            return storeAndReturn(result, leagueCode: code)
        }

        let task = Task<LeagueStandingsFetchResult, Error> {
            try await ESPNStandingsLoader.fetch(leagueCode: code)
        }
        inFlight[code] = task
        do {
            let result = try await task.value
            inFlight[code] = nil
            return storeAndReturn(result, leagueCode: code)
        } catch {
            inFlight[code] = nil
            throw error
        }
    }

    private func storeAndReturn(_ result: LeagueStandingsFetchResult, leagueCode code: String) -> LeagueStandingsPayload {
        let key = result.cacheKey
        if let old = lastKeyByLeague[code], old.storageKey != key.storageKey {
            entries.removeValue(forKey: old.storageKey)
        }
        lastKeyByLeague[code] = key
        entries[key.storageKey] = (result.payload, Date().addingTimeInterval(ttl))
        return result.payload
    }
}
