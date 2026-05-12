//
//  LiveScoreWidget.swift
//  FanfolioLiveScoreWidget
//
//  잠금화면 / 다이내믹 아일랜드용 UI.
//  ⚠️ Widget Extension 타겟 전용. LiveScoreAttributes.swift는 본 앱+위젯 양쪽에
//  Target Membership을 체크해야 컴파일됩니다.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LiveScoreWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveScoreAttributes.self) { context in
            // MARK: - 잠금 화면 / 배너 UI
            LockScreenLiveScoreView(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TeamBadgeView(
                        teamName: context.attributes.homeTeamName,
                        assetImageName: context.attributes.homeTeamAssetImageName,
                        abbreviation: context.attributes.homeTeamAbbreviation,
                        size: 32
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TeamBadgeView(
                        teamName: context.attributes.awayTeamName,
                        assetImageName: context.attributes.awayTeamAssetImageName,
                        abbreviation: context.attributes.awayTeamAbbreviation,
                        size: 32
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("\(context.state.homeScore) : \(context.state.awayScore)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(context.state.matchStatus)
                            .font(.caption2)
                            .foregroundStyle(context.state.isLive ? Color.red : Color.white.opacity(0.7))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.leagueCode)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } compactLeading: {
                CompactTeamLabel(
                    assetImageName: context.attributes.homeTeamAssetImageName,
                    abbreviation: context.attributes.homeTeamAbbreviation,
                    fallback: context.attributes.homeTeamName
                )
            } compactTrailing: {
                Text("\(context.state.homeScore):\(context.state.awayScore)")
                    .font(.system(.caption, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(context.state.isLive ? .red : .primary)
            } minimal: {
                Image(systemName: context.state.isLive ? "dot.radiowaves.left.and.right" : "sportscourt.fill")
                    .foregroundStyle(context.state.isLive ? .red : .secondary)
            }
            .widgetURL(URL(string: "fanfolio://live?event=\(context.attributes.externalEventID)"))
        }
    }
}

// MARK: - 잠금 화면 UI

private struct LockScreenLiveScoreView: View {
    let attributes: LiveScoreAttributes
    let state: LiveScoreAttributes.ContentState

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(attributes.leagueCode)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.15), in: Capsule())
                    .foregroundStyle(.white)
                Spacer()
                if state.isLive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                    }
                }
            }

            HStack(spacing: 12) {
                teamColumn(
                    name: attributes.homeTeamName,
                    assetImageName: attributes.homeTeamAssetImageName,
                    abbreviation: attributes.homeTeamAbbreviation,
                    score: state.homeScore
                )

                VStack(spacing: 2) {
                    Text(":")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(state.matchStatus)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                teamColumn(
                    name: attributes.awayTeamName,
                    assetImageName: attributes.awayTeamAssetImageName,
                    abbreviation: attributes.awayTeamAbbreviation,
                    score: state.awayScore
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func teamColumn(
        name: String,
        assetImageName: String?,
        abbreviation: String?,
        score: Int
    ) -> some View {
        VStack(spacing: 4) {
            TeamBadgeView(
                teamName: name,
                assetImageName: assetImageName,
                abbreviation: abbreviation,
                size: 36
            )
            Text(abbreviation ?? name)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Text("\(score)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 팀 배지 (로고 or 약자)

private struct TeamBadgeView: View {
    let teamName: String
    let assetImageName: String?
    let abbreviation: String?
    let size: CGFloat

    var body: some View {
        if let assetName = assetImageName, !assetName.isEmpty {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Text(abbreviationText)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.15), in: Circle())
        }
    }

    private var abbreviationText: String {
        if let abbr = abbreviation, !abbr.isEmpty { return abbr }
        // 폴백: 팀명의 첫 3글자
        return String(teamName.prefix(3)).uppercased()
    }
}

// MARK: - 다이내믹 아일랜드 컴팩트용 라벨

private struct CompactTeamLabel: View {
    let assetImageName: String?
    let abbreviation: String?
    let fallback: String

    var body: some View {
        if let assetName = assetImageName, !assetName.isEmpty {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        } else {
            Text(label)
                .font(.system(.caption2, design: .rounded).bold())
                .lineLimit(1)
        }
    }

    private var label: String {
        if let abbr = abbreviation, !abbr.isEmpty { return abbr }
        return String(fallback.prefix(3)).uppercased()
    }
}
