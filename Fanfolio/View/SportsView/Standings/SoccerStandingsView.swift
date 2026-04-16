//
//  SoccerStandingsView.swift
//  Fanfolio
//

import SwiftUI

struct SoccerStandingsView: View {
    let sections: [SoccerStandingsSection]
    var highlightTeamId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    soccerTable(section)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func soccerTable(_ section: SoccerStandingsSection) -> some View {
        VStack(spacing: 0) {
            soccerHeaderRow
            ForEach(section.rows) { row in
                soccerRow(row)
                if row.id != section.rows.last?.id {
                    Divider().opacity(0.35)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
        .groupedCardOutline(cornerRadius: 16)
    }

    private var soccerHeaderRow: some View {
        HStack(spacing: 8) {
            Text("#")
                .frame(width: 28, alignment: .leading)
            Text(String(localized: "standings.col.team", defaultValue: "팀"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(localized: "standings.col.wdl", defaultValue: "승·무·패"))
                .frame(width: 64, alignment: .trailing)
            Text(String(localized: "standings.col.pts", defaultValue: "승점"))
                .frame(width: 36, alignment: .trailing)
            Text(String(localized: "standings.col.gd", defaultValue: "득실"))
                .frame(width: 36, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
    }

    private func soccerRow(_ row: SoccerStandingRow) -> some View {
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
            Text(verbatim: "\(row.wins)-\(row.draws)-\(row.losses)")
                .font(.caption.monospacedDigit())
                .frame(width: 64, alignment: .trailing)
            Text(verbatim: "\(row.points)")
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
            Text(goalDiffString(row.goalDifference))
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .background(isHi ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func goalDiffString(_ gd: Int) -> String {
        if gd > 0 { return "+\(gd)" }
        return "\(gd)"
    }
}
