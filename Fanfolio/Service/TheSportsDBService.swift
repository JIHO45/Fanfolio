//
//  TheSportsDBService.swift
//  Fanfolio
//
//  TheSportsDB API 네트워킹 서비스
//  무료 테스트 키(3) 사용 시 선수 이미지에 워터마크가 표시됩니다.
//  Phase 3 출시 직전 $9/월 유료 키로 전환하면 워터마크 자동 제거됩니다.
//

import Foundation
import os.log

// MARK: - TheSportsDB 에러

enum TheSportsDBError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingFailed
    case playerNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "잘못된 URL입니다."
        case .networkError(let e):  return "네트워크 오류: \(e.localizedDescription)"
        case .decodingFailed:       return "데이터 파싱에 실패했습니다."
        case .playerNotFound:       return "선수 정보를 찾을 수 없습니다."
        }
    }
}

// MARK: - TheSportsDB 서비스

@MainActor
final class TheSportsDBService {

    static let shared = TheSportsDBService()
    private init() {}

    private let session = URLSession.shared

    /// 이름 → cutoutURL TTL 캐시 (1시간)
    private let cutoutCache = TTLCache<String, String?>(ttl: 3600)
    /// 팀 선수단 TTL 캐시 (1시간)
    private let squadCache = TTLCache<String, [PlayerInfo]>(ttl: 3600)
    /// 팀 검색 결과 TTL 캐시 (30분)
    private let teamSearchCache = TTLCache<String, TheSportsDBTeamSearchResult?>(ttl: 1800)

    // MARK: - 공통 요청 (재시도 포함)

    private func fetchJSON<T: Decodable>(_ type: T.Type, path: String, params: [String: String] = [:]) async throws -> T {
        var components = URLComponents(string: APIConfig.sportsDBBaseURL + path)
        if !params.isEmpty {
            components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components?.url else { throw TheSportsDBError.invalidURL }

        Logger.api.info("TheSportsDB → \(url.path)")

        return try await withRetry(maxAttempts: 3) {
            do {
                let (data, _) = try await self.session.data(from: url)
                return try JSONDecoder().decode(T.self, from: data)
            } catch let error as DecodingError {
                Logger.api.error("TheSportsDB decoding failed: \(error)")
                throw TheSportsDBError.decodingFailed
            } catch {
                throw TheSportsDBError.networkError(error)
            }
        } shouldRetry: { error in
            // 파싱 실패는 재시도해도 의미 없음
            if case TheSportsDBError.decodingFailed = error { return false }
            return true
        }
    }

    // MARK: - 선수 검색 (이름으로)

    /// 선수 이름으로 검색 후 PlayerInfo 배열 반환
    /// TheSportsDB `/searchplayers.php?p={name}`
    func searchPlayers(name: String) async throws -> [PlayerInfo] {
        let response = try await fetchJSON(
            TheSportsDBPlayerResponse.self,
            path: "/searchplayers.php",
            params: ["p": name]
        )
        return response.player?.map { $0.toPlayerInfo() } ?? []
    }

    /// 선수 이름으로 누끼 이미지 URL 반환 (TTL 캐시 포함)
    func fetchCutoutURL(for playerName: String) async -> String? {
        if let cached = cutoutCache.get(playerName) {
            return cached
        }

        let result: String?
        do {
            let players = try await searchPlayers(name: playerName)
            result = players.first?.cutoutImageURL
        } catch {
            Logger.api.error("TheSportsDB cutout fetch failed for '\(playerName)': \(error.localizedDescription)")
            result = nil
        }

        cutoutCache.set(playerName, value: result)
        return result
    }

    // MARK: - 팀 전체 선수단 조회

    /// TheSportsDB 팀 ID로 전체 선수단 조회 (TTL 캐시 포함)
    /// `/lookup_all_players.php?id={teamId}`
    func fetchTeamSquad(theSportsDBTeamID: String) async throws -> [PlayerInfo] {
        if let cached = squadCache.get(theSportsDBTeamID) {
            return cached
        }

        let response = try await fetchJSON(
            TheSportsDBSquadResponse.self,
            path: "/lookup_all_players.php",
            params: ["id": theSportsDBTeamID]
        )
        let players = response.player?.map { $0.toPlayerInfo() } ?? []
        squadCache.set(theSportsDBTeamID, value: players)
        return players
    }

    /// 팀 이름으로 TheSportsDB 팀 검색 (TTL 캐시 포함)
    /// `/searchteams.php?t={teamName}`
    func searchTeam(name: String) async throws -> TheSportsDBTeamSearchResult? {
        if let cached = teamSearchCache.get(name) {
            return cached
        }

        let response = try await fetchJSON(
            TheSportsDBTeamSearchResponse.self,
            path: "/searchteams.php",
            params: ["t": name]
        )
        let result = response.teams?.first
        teamSearchCache.set(name, value: result)
        return result
    }

    /// 팀 이름으로 선수단 전체를 가져옵니다.
    func fetchSquadByTeamName(_ teamName: String) async throws -> [PlayerInfo] {
        guard let team = try await searchTeam(name: teamName),
              let teamID = team.idTeam else {
            throw TheSportsDBError.playerNotFound
        }
        return try await fetchTeamSquad(theSportsDBTeamID: teamID)
    }

    // MARK: - 최근 경기 결과

    /// 팀의 최근 경기 결과 5개
    /// `/eventslast.php?id={teamId}`
    func fetchRecentEvents(theSportsDBTeamID: String) async throws -> [TheSportsDBEvent] {
        let response = try await fetchJSON(
            TheSportsDBEventsResponse.self,
            path: "/eventslast.php",
            params: ["id": theSportsDBTeamID]
        )
        return response.results ?? []
    }

    // MARK: - 캐시 초기화

    func clearCache() {
        cutoutCache.removeAll()
        squadCache.removeAll()
        teamSearchCache.removeAll()
    }

    func purgeExpiredCache() {
        cutoutCache.purgeExpired()
        squadCache.purgeExpired()
        teamSearchCache.purgeExpired()
    }
}

// MARK: - TheSportsDB 팀 검색 응답 모델

struct TheSportsDBTeamSearchResponse: Codable {
    let teams: [TheSportsDBTeamSearchResult]?
}

struct TheSportsDBTeamSearchResult: Codable {
    let idTeam: String?
    let strTeam: String?
    let strTeamBadge: String?
    let strLeague: String?
    let strSport: String?
    let strCountry: String?
    let strDescriptionEN: String?
}

// MARK: - TheSportsDB 이벤트(경기) 모델

struct TheSportsDBEventsResponse: Codable {
    let results: [TheSportsDBEvent]?
}

struct TheSportsDBEvent: Codable, Identifiable {
    var id: String { idEvent ?? UUID().uuidString }
    let idEvent: String?
    let strEvent: String?
    let dateEvent: String?
    let strHomeTeam: String?
    let strAwayTeam: String?
    let intHomeScore: String?
    let intAwayScore: String?
    let strLeague: String?
    let strSport: String?
}
