//
//  ESPNStandingsLoader.swift
//  Fanfolio
//
//  ESPN v2 standings JSON → `LeagueStandingsPayload`
//

import Foundation
import os.log

enum ESPNStandingsLoader {

    /// ESPN이 해당 리그 순위를 제공하는 경우에만 성공합니다. (KBO 등은 `unsupportedLeague`)
    /// 캐시 키는 응답의 `season.year`와 요청한 `seasontype`으로 구성합니다.
    static func fetch(leagueCode: String) async throws -> LeagueStandingsFetchResult {
        guard let (sport, league) = ESPNPlayerService.shared.teamSportPath(for: leagueCode) else {
            throw ESPNServiceError.unsupportedLeague(leagueCode)
        }
        let seasonType = (sport == "soccer") ? 1 : 2
        guard let url = URL(string:
            "https://site.api.espn.com/apis/v2/sports/\(sport)/\(league)/standings?seasontype=\(seasonType)"
        ) else {
            throw ESPNServiceError.networkError(URLError(.badURL))
        }

        Logger.api.info("ESPN → standings: \(leagueCode) (seasonType=\(seasonType))")

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ESPNServiceError.networkError(URLError(.badServerResponse))
        }

        let decoded = try JSONDecoder().decode(ESPNStandingsV2Response.self, from: data)
        guard let groups = decoded.children, !groups.isEmpty else {
            throw ESPNServiceError.decodingError(
                NSError(domain: "ESPNStandings", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty standings"])
            )
        }

        let seasonYear = decoded.season?.year ?? Calendar.current.component(.year, from: Date())
        let cacheKey = StandingsCacheKey(leagueCode: leagueCode, seasonYear: seasonYear, seasonType: seasonType)

        if sport == "soccer" {
            let sections: [SoccerStandingsSection] = groups.enumerated().map { si, group in
                let title = group.name ?? String(localized: "standings.section.table", defaultValue: "순위")
                let entries = group.standings?.entries ?? []
                let rows: [SoccerStandingRow] = entries.enumerated().map { ri, entry in
                    parseSoccerRow(entry, fallbackRank: ri + 1)
                }
                let slug = slugify(title)
                return SoccerStandingsSection(
                    id: "\(leagueCode)-\(si)-\(slug.isEmpty ? "table" : slug)",
                    title: title,
                    rows: rows
                )
            }
            let payload: LeagueStandingsPayload = .soccer(SoccerStandingsDisplayOptions(), sections)
            return LeagueStandingsFetchResult(payload: payload, cacheKey: cacheKey)
        }

        guard let config = WinPctStandingsConfiguration.for(leagueCode: leagueCode) else {
            throw ESPNServiceError.unsupportedLeague(leagueCode)
        }

        let sections: [WinPctStandingsSection] = groups.enumerated().map { si, group in
            let title = group.name ?? String(localized: "standings.section.table", defaultValue: "순위")
            let entries = group.standings?.entries ?? []
            let rows: [WinPctStandingRow] = entries.enumerated().map { idx, entry in
                parseWinPctRow(entry, rank: idx + 1, config: config)
            }
            let slug = slugify(title)
            return WinPctStandingsSection(
                id: "\(leagueCode)-\(si)-\(slug.isEmpty ? "table" : slug)",
                title: title,
                rows: rows
            )
        }
        let payload: LeagueStandingsPayload = .winPct(config, sections)
        return LeagueStandingsFetchResult(payload: payload, cacheKey: cacheKey)
    }

    // MARK: - Win %

    private static func parseWinPctRow(
        _ entry: ESPNStandingsEntry,
        rank: Int,
        config: WinPctStandingsConfiguration
    ) -> WinPctStandingRow {
        let map = statDisplayMap(entry.stats)
        let valueMap = statValueMap(entry.stats)

        let wins = intStat(map, "wins") ?? 0
        let losses = intStat(map, "losses") ?? 0
        let ties = intStat(map, "ties") ?? 0

        let apiPct = parseWinPctFromStats(display: map["winPercent"], value: valueMap["winPercent"])

        let pct = StandingsWinPctFormatting.resolveWinPct(
            wins: wins,
            losses: losses,
            ties: ties,
            apiWinPct: apiPct,
            source: config.winPctSource
        )

        return WinPctStandingRow(
            id: entry.team.id,
            rank: rank,
            teamDisplayName: entry.team.displayName ?? entry.team.shortDisplayName ?? "—",
            wins: wins,
            losses: losses,
            ties: ties,
            winPct: pct,
            gamesBehindDisplay: map["gamesBehind"],
            streakDisplay: map["streak"]
        )
    }

    // MARK: - Soccer

    private static func parseSoccerRow(_ entry: ESPNStandingsEntry, fallbackRank: Int) -> SoccerStandingRow {
        let map = statDisplayMap(entry.stats)
        let rank = intStat(map, "rank") ?? fallbackRank
        let wins = intStat(map, "wins") ?? 0
        let losses = intStat(map, "losses") ?? 0
        let ties = intStat(map, "ties") ?? intStat(map, "draws") ?? 0
        let points = intStat(map, "points") ?? 0
        let gd = parseGoalDifference(map["pointDifferential"] ?? map["goalDifferential"])
        return SoccerStandingRow(
            id: entry.team.id,
            rank: rank,
            teamDisplayName: entry.team.displayName ?? entry.team.shortDisplayName ?? "—",
            wins: wins,
            draws: ties,
            losses: losses,
            points: points,
            goalDifference: gd
        )
    }

    // MARK: - Stats helpers

    private static func statDisplayMap(_ stats: [ESPNStandingStat]) -> [String: String] {
        var out: [String: String] = [:]
        for s in stats {
            guard let name = s.name, let dv = s.displayValue else { continue }
            out[name] = dv
        }
        return out
    }

    private static func statValueMap(_ stats: [ESPNStandingStat]) -> [String: Double] {
        var out: [String: Double] = [:]
        for s in stats {
            guard let name = s.name, let v = s.value else { continue }
            out[name] = v
        }
        return out
    }

    private static func intStat(_ map: [String: String], _ key: String) -> Int? {
        guard let raw = map[key] else { return nil }
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
        return Int(cleaned)
    }

    private static func parseWinPctFromStats(display: String?, value: Double?) -> Double? {
        if let v = value, v >= 0, v <= 1.0001 { return min(1, max(0, v)) }
        guard var d = display?.trimmingCharacters(in: .whitespaces), !d.isEmpty else { return nil }
        if d.hasSuffix("%") {
            d.removeLast()
            if let x = Double(d.trimmingCharacters(in: .whitespaces)) { return x / 100 }
        }
        if d.hasPrefix(".") { d = "0" + d }
        if let x = Double(d) {
            if x > 1 { return x / 100 }
            return x
        }
        return nil
    }

    private static func parseGoalDifference(_ raw: String?) -> Int {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return 0 }
        let t = raw.replacingOccurrences(of: "+", with: "")
        return Int(t) ?? 0
    }

    /// 섹션 ID용 ASCII 슬러그. 비라틴 문자만 있으면 빈 문자열이 될 수 있음 → 호출부에서 `table` 등으로 대체.
    private static func slugify(_ s: String) -> String {
        let lowered = s.lowercased()
        var out = ""
        for ch in lowered {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                out.append(ch)
            } else if ch.isWhitespace || ch == "-" || ch == "." {
                if out.last != "-" { out.append("-") }
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

// MARK: - Decodable (ESPN v2)

private struct ESPNStandingsSeason: Decodable {
    let year: Int?
}

private struct ESPNStandingsV2Response: Decodable {
    let children: [ESPNStandingsGroup]?
    let season: ESPNStandingsSeason?
}

private struct ESPNStandingsGroup: Decodable {
    let name: String?
    let standings: ESPNStandingsTable?
}

private struct ESPNStandingsTable: Decodable {
    let entries: [ESPNStandingsEntry]?
}

private struct ESPNStandingsEntry: Decodable {
    let team: ESPNStandingsTeam
    let stats: [ESPNStandingStat]
}

private struct ESPNStandingsTeam: Decodable {
    let id: String
    let displayName: String?
    let shortDisplayName: String?
}

private struct ESPNStandingStat: Decodable {
    let name: String?
    let displayValue: String?
    let value: Double?
}
