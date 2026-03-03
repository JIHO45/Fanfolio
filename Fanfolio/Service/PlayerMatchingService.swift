//
//  PlayerMatchingService.swift
//  Fanfolio
//
//  Phase 2: API-Sports 선수 이름 → TheSportsDB 누끼 이미지 매칭 서비스
//  퍼지 매칭 + 인메모리 캐싱으로 API 호출 최소화
//

import Foundation
import os.log

// MARK: - 매칭 서비스

@MainActor
final class PlayerMatchingService {
    
    static let shared = PlayerMatchingService()
    private init() {}
    
    private let sportsDB = TheSportsDBService.shared
    private let apiSports = APISportsService.shared

    /// playerID → PlayerInfo (스텟 + 누끼 포함) TTL 캐시 (1시간)
    private let playerCache = TTLCache<Int, PlayerInfo>(ttl: 3600)
    
    // MARK: - 선수단 + 누끼 이미지 통합 로드

    /// 팀 이름으로 선수단을 로드하고, 누끼 이미지(TheSportsDB)를 비동기 매칭합니다.
    /// API-Sports squad → TheSportsDB cutout 순으로 연결합니다.
    func fetchSquadWithCutouts(
        sportType: SportType,
        teamName: String,
        teamID: Int
    ) async -> [PlayerInfo] {
        Logger.api.info("PlayerMatching: loading squad for '\(teamName)' (id: \(teamID))")

        // 1단계: API-Sports에서 로스터 가져오기
        var squadPlayers: [PlayerInfo]
        do {
            let rawPlayers = try await apiSports.fetchSquad(sportType: sportType, teamID: teamID)
            squadPlayers = rawPlayers.map { raw in
                PlayerInfo(
                    id: raw.id,
                    name: raw.name,
                    position: raw.position,
                    number: raw.number.map { "\($0)" },
                    cutoutImageURL: nil,
                    photoURL: raw.photo,
                    nationality: nil,
                    age: raw.age,
                    teamName: teamName,
                    stats: nil
                )
            }
        } catch {
            Logger.api.warning("API-Sports squad failed for '\(teamName)', falling back to TheSportsDB: \(error.localizedDescription)")
            do {
                squadPlayers = try await sportsDB.fetchSquadByTeamName(teamName)
            } catch {
                Logger.api.error("TheSportsDB squad also failed for '\(teamName)': \(error.localizedDescription)")
                return []
            }
        }

        // 2단계: TheSportsDB에서 팀 선수단 한 번에 로드 (누끼 이미지 포함)
        var cutoutMap: [String: String] = [:]
        if let dbTeam = try? await sportsDB.searchTeam(name: teamName),
           let dbTeamID = dbTeam.idTeam {
            let dbPlayers = (try? await sportsDB.fetchTeamSquad(theSportsDBTeamID: dbTeamID)) ?? []
            for player in dbPlayers {
                if let cutout = player.cutoutImageURL {
                    cutoutMap[player.name.lowercased()] = cutout
                }
            }
        }

        Logger.api.info("PlayerMatching: matched \(cutoutMap.count) cutouts for '\(teamName)'")

        // 3단계: 이름 기반 퍼지 매칭으로 cutoutURL 결합
        return squadPlayers.map { player in
            let cutout = findCutout(for: player.name, in: cutoutMap)
            return PlayerInfo(
                id: player.id,
                name: player.name,
                position: player.position,
                number: player.number,
                cutoutImageURL: cutout,
                photoURL: player.photoURL,
                nationality: player.nationality,
                age: player.age,
                teamName: player.teamName,
                stats: player.stats
            )
        }
    }

    // MARK: - 단일 선수 누끼 이미지 조회

    /// API-Sports 선수 이름으로 TheSportsDB 누끼 이미지 URL을 찾습니다.
    func fetchCutoutURL(for playerName: String) async -> String? {
        await sportsDB.fetchCutoutURL(for: playerName)
    }

    // MARK: - 캐시 초기화

    func clearCache() {
        playerCache.removeAll()
    }
    
    // MARK: - 퍼지 이름 매칭
    
    /// 다양한 이름 표기법을 고려한 퍼지 매칭
    /// "Brock Purdy" ↔ "brock purdy", "B. Purdy", "purdy" 등 처리
    private func findCutout(for name: String, in map: [String: String]) -> String? {
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespaces)
        
        // 1. 정확히 일치
        if let url = map[normalizedName] { return url }
        
        let parts = normalizedName.split(separator: " ").map(String.init)
        guard parts.count >= 2 else {
            // 단일 이름: 성(last name)만 검색
            return map.first { $0.key.contains(normalizedName) }?.value
        }
        
        let firstName = parts.first ?? ""
        let lastName = parts.last ?? ""
        
        // 2. 성(last name)만 일치
        if let match = map.first(where: { $0.key.hasSuffix(lastName) }) {
            return match.value
        }
        
        // 3. 이름 이니셜 + 성 형태 (예: "B. Purdy")
        let initial = String(firstName.prefix(1))
        let abbreviated = "\(initial). \(lastName)"
        if let url = map[abbreviated] { return url }
        
        // 4. 성 포함 여부
        if let match = map.first(where: { $0.key.contains(lastName) && lastName.count >= 4 }) {
            return match.value
        }
        
        return nil
    }
}
