//
//  WinPctStandingsView.swift
//  Fanfolio
//

import SwiftUI

struct WinPctStandingsView: View {
    let config: WinPctStandingsConfiguration
    let sections: [WinPctStandingsSection]
    /// 하이라이트할 팀 ESPN ID (없으면 미표시)
    var highlightTeamId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    winPctTable(section)
                }
            }
        }
    }

    private func winPctTable(_ section: WinPctStandingsSection) -> some View {
        VStack(spacing: 0) {
            winPctHeaderRow
            ForEach(section.rows) { row in
                winPctRow(row)
                if row.id != section.rows.last?.id {
                    Divider().opacity(0.35)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
        .groupedCardOutline(cornerRadius: 16)
    }

    private var winPctHeaderRow: some View {
        HStack(spacing: 8) {
            Text("#")
                .frame(width: 28, alignment: .leading)
            Text(String(localized: "standings.col.team", defaultValue: "팀"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(localized: "standings.col.record", defaultValue: "경기"))
                .frame(width: 56, alignment: .trailing)
            Text(String(localized: "standings.col.pct", defaultValue: "PCT"))
                .frame(width: 44, alignment: .trailing)
            ForEach(config.subColumns, id: \.self) { col in
                switch col {
                case .gamesBehind:
                    Text(String(localized: "standings.col.gb", defaultValue: "GB"))
                        .frame(width: 36, alignment: .trailing)
                case .streak:
                    Text(String(localized: "standings.col.streak", defaultValue: "연속"))
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
    }

    private func winPctRow(_ row: WinPctStandingRow) -> some View {
        let isHi = highlightTeamId.map { $0 == row.id } ?? false
        return HStack(spacing: 8) {
            Text(verbatim: "\(row.rank)")
                .frame(width: 28, alignment: .leading)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isHi ? .primary : .secondary)
            Text(row.teamDisplayName)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.subheadline.weight(isHi ? .semibold : .regular))
            Text(recordString(row))
                .font(.caption.monospacedDigit())
                .frame(width: 56, alignment: .trailing)
            Text(StandingsWinPctFormatting.formatWinPct(row.winPct))
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
            ForEach(config.subColumns, id: \.self) { col in
                switch col {
                case .gamesBehind:
                    Text(row.gamesBehindDisplay ?? "—")
                        .font(.caption.monospacedDigit())
                        .frame(width: 36, alignment: .trailing)
                case .streak:
                    Text(row.streakDisplay ?? "—")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 6)
        .background(isHi ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func recordString(_ row: WinPctStandingRow) -> String {
        switch config.recordFormat {
        case .winsLosses:
            return "\(row.wins)-\(row.losses)"
        case .winsLossesTies:
            return "\(row.wins)-\(row.losses)-\(row.ties)"
        }
    }
}
