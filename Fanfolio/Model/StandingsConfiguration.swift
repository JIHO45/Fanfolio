//
//  StandingsConfiguration.swift
//  Fanfolio
//
//  승률 리그(WinPct) vs 승점 리그(축구) UI·계산 정책을 뷰 밖에서 주입합니다.

import Foundation

// MARK: - Win % league

/// 전적 표기: W-L 또는 W-L-T
enum StandingsRecordFormat: Equatable, Sendable {
    case winsLosses
    case winsLossesTies
}

/// 승률 리그에서 승률 숫자를 어떻게 채울지
enum StandingsWinPctSource: Equatable, Sendable {
    /// ESPN `winPercent` 스탯 우선, 없으면 승/(승+패)로 보조 계산
    case preferESPN
    /// MLB/KBO 등: 승 / (승 + 패), 무는 제외
    case computeExcludingTies
    /// NFL: (승 + 무×0.5) / 총 경기
    case computeNFLStyle
}

enum StandingsWinPctSubColumn: Equatable, Sendable, CaseIterable, Hashable {
    case gamesBehind
    case streak
}

/// `WinPctStandingsView` 렌더링 명세 (도메인 분기는 여기서 끝)
struct WinPctStandingsConfiguration: Equatable, Sendable {
    var recordFormat: StandingsRecordFormat
    /// 표시할 부가 열 순서 (헤더·셀 모두 동일 순서)
    var subColumns: [StandingsWinPctSubColumn]
    var winPctSource: StandingsWinPctSource

    static func `for`(leagueCode: String) -> WinPctStandingsConfiguration? {
        switch leagueCode {
        case "NFL":
            return WinPctStandingsConfiguration(
                recordFormat: .winsLossesTies,
                subColumns: [.gamesBehind, .streak],
                winPctSource: .preferESPN
            )
        case "NBA":
            return WinPctStandingsConfiguration(
                recordFormat: .winsLosses,
                subColumns: [.gamesBehind, .streak],
                winPctSource: .preferESPN
            )
        case "MLB":
            return WinPctStandingsConfiguration(
                recordFormat: .winsLosses,
                subColumns: [.gamesBehind, .streak],
                winPctSource: .preferESPN
            )
        case "KBO":
            // 무승부 있음(재경기 처리), GB·연속 표시
            return WinPctStandingsConfiguration(
                recordFormat: .winsLossesTies,
                subColumns: [.gamesBehind, .streak],
                winPctSource: .computeExcludingTies
            )
        default:
            return nil
        }
    }
}

// MARK: - Rows (Win %)

struct WinPctStandingRow: Identifiable, Equatable, Sendable {
    let id: String
    let rank: Int
    let teamDisplayName: String
    let wins: Int
    let losses: Int
    let ties: Int
    /// 0...1
    let winPct: Double
    let gamesBehindDisplay: String?
    let streakDisplay: String?
}

struct WinPctStandingsSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let rows: [WinPctStandingRow]
}

// MARK: - Soccer

/// 축구 순위표 전용 표시 옵션 (필요 시 열 확장)
struct SoccerStandingsDisplayOptions: Equatable, Sendable {
    init() {}
}

struct SoccerStandingRow: Identifiable, Equatable, Sendable {
    let id: String
    let rank: Int
    let teamDisplayName: String
    let wins: Int
    let draws: Int
    let losses: Int
    let points: Int
    let goalDifference: Int
}

struct SoccerStandingsSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let rows: [SoccerStandingRow]
}

// MARK: - Payload

enum LeagueStandingsPayload: Sendable {
    case winPct(WinPctStandingsConfiguration, [WinPctStandingsSection])
    case soccer(SoccerStandingsDisplayOptions, [SoccerStandingsSection])
}

// MARK: - Fetch / cache identity

/// ESPN 응답의 시즌 연도 + 실제 요청한 `seasontype` — 시즌 전환 시 낡은 캐시가 섞이지 않게 합니다.
struct StandingsCacheKey: Hashable, Sendable {
    let leagueCode: String
    let seasonYear: Int
    /// API 쿼리 `seasontype`(축구 1, 미국 프로 정규시즌 2 등)
    let seasonType: Int

    var storageKey: String { "\(leagueCode)|\(seasonYear)|\(seasonType)" }
}

struct LeagueStandingsFetchResult: Sendable {
    let payload: LeagueStandingsPayload
    let cacheKey: StandingsCacheKey
}

// MARK: - Win % 표시용 숫자

enum StandingsWinPctFormatting {
    static func resolveWinPct(
        wins: Int,
        losses: Int,
        ties: Int,
        apiWinPct: Double?,
        source: StandingsWinPctSource
    ) -> Double {
        switch source {
        case .preferESPN:
            if let p = apiWinPct, p >= 0, p <= 1 { return p }
            if ties > 0 {
                let g = wins + losses + ties
                guard g > 0 else { return 0 }
                return (Double(wins) + 0.5 * Double(ties)) / Double(g)
            }
            let d = Double(wins + losses)
            guard d > 0 else { return 0 }
            return Double(wins) / d
        case .computeExcludingTies:
            let d = Double(wins + losses)
            guard d > 0 else { return 0 }
            return Double(wins) / d
        case .computeNFLStyle:
            let games = wins + losses + ties
            guard games > 0 else { return 0 }
            return (Double(wins) + 0.5 * Double(ties)) / Double(games)
        }
    }

    /// 승률을 ESPN과 유사하게 3자리로 표기 (예: 0.824)
    static func formatWinPct(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
