//
//  PlayerMatchingService.swift
//  Fanfolio
//
//  선수 로스터 라우팅 서비스
//
//  라우팅 원칙:
//    US 스포츠 (NFL·NBA·MLB·NHL·축구 메이저리그):
//      ESPN roster API (무제한) → ESPN CDN 헤드샷 URL 직접 사용
//    비US 스포츠 (KBO 등):
//      API-Sports squad (1회만, 100회/일 제한) → API-Sports 선수 사진
//

import Foundation
import os.log

// MARK: - 로스터 서비스

@MainActor
final class PlayerMatchingService {

    static let shared = PlayerMatchingService()
    private init() {}

    private let apiSports = APISportsService.shared

    // MARK: - 선수단 로드

    func fetchSquadWithCutouts(
        sportType: SportType,
        teamName: String,
        espnTeamID: String? = nil,
        leagueCode: String? = nil,
        apiSportsTeamID: Int? = nil
    ) async -> [PlayerInfo] {
        Logger.api.info("PlayerMatching: loading squad for '\(teamName)'")

        let code   = leagueCode ?? ""
        let isESPN = !code.isEmpty && ESPNPlayerService.shared.supportsLiveScoreboard(code)

        if isESPN, let eid = espnTeamID, !eid.isESPNFakeID {
            do {
                let athletes = try await ESPNPlayerService.shared.fetchRoster(teamESPNId: eid, leagueCode: code)
                let players  = athletes.map { athlete in
                    PlayerInfo(
                        id: Int(athlete.id) ?? athlete.id.hashValue,
                        name: athlete.name,
                        position: athlete.position,
                        number: athlete.jerseyNumber,
                        imageURL: athlete.headshotURL,
                        nationality: nil,
                        age: nil,
                        teamName: teamName
                    )
                }
                Logger.api.info("PlayerMatching: ESPN roster → \(players.count) players for '\(teamName)'")
                return players
            } catch {
                Logger.api.warning("PlayerMatching: ESPN roster failed for '\(teamName)': \(error.localizedDescription) — API-Sports로 폴백")
                // 아래 API-Sports 경로로 계속 진행
            }
        }

        if let tid = apiSportsTeamID, tid > 0 {
            let canUseAPISports = NetworkMonitor.shared.isConnected
                && !APIConfig.apiSportsKey.isEmpty
                && !APIRateLimiter.shared.isLimitReached

            if !canUseAPISports {
                if !NetworkMonitor.shared.isConnected {
                    Logger.api.warning("PlayerMatching: 오프라인이라 API-Sports 로스터를 건너뜁니다. '\(teamName)'")
                } else if APIConfig.apiSportsKey.isEmpty {
                    Logger.api.warning("PlayerMatching: API 키 없음, API-Sports 로스터 생략. '\(teamName)'")
                } else {
                    Logger.api.warning("PlayerMatching: API 일일 한도 도달, API-Sports 로스터 생략. '\(teamName)'")
                }
            } else {
                do {
                    let rawPlayers = try await apiSports.fetchSquad(sportType: sportType, teamID: tid)
                    let players = rawPlayers.map { raw in
                        PlayerInfo(
                            id: raw.id,
                            name: raw.name,
                            position: raw.position,
                            number: raw.number.map { "\($0)" },
                            imageURL: raw.photo,
                            nationality: nil,
                            age: raw.age,
                            teamName: teamName
                        )
                    }
                    Logger.api.info("PlayerMatching: API-Sports squad → \(players.count) players for '\(teamName)'")
                    return players
                } catch {
                    Logger.api.warning("API-Sports squad failed for '\(teamName)': \(error.localizedDescription)")
                }
            }
        }

        Logger.api.warning("PlayerMatching: no squad data available for '\(teamName)'")
        return []
    }
}
