//
//  LiveScoreboardView.swift
//  Fanfolio
//
//  스포츠 중계 방송 스타일의 실시간 스코어보드
//

import SwiftUI
import Kingfisher

// MARK: - 스코어보드 메인 뷰

struct LiveScoreboardView: View {
    let fixture: LiveFixture
    let sportType: SportType

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            if fixture.periods.isEmpty {
                scoreRow
            } else if fixture.periods.count <= 9 {
                // 9이닝 이하: MLB처럼 스크롤 없이 한 화면에 전체 컬럼 표시
                scoreRowInline
            } else {
                // 10이닝+: 기존 가로 스크롤 방식
                scoreRowWithSyncedPeriodScroll
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    fixture.isLive
                        ? Color.red.opacity(0.4)
                        : GroupedCardChrome.outlineStrokeColor(colorScheme: colorScheme),
                    lineWidth: fixture.isLive ? 1.5 : 1
                )
        )
    }
    
    // MARK: - 헤더 바 (리그명 + 상태 + 경과 시간)
    
    private var headerBar: some View {
        HStack(spacing: 8) {
            // 리그명
            Text(fixture.league.name)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            Text(verbatim: "·")
                .foregroundStyle(.tertiary)
            
            // 상태 (LIVE 깜빡임 또는 예정 시간)
            if fixture.isLive {
                LiveIndicator()
                Text(fixture.status.displayText)
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            } else if fixture.isUpcoming, let time = fixture.startTime {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text(timeString(time))
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            } else {
                Text(fixture.status.displayText)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // 스포츠 아이콘
            Image(systemName: sportType.iconName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .fill(fixture.isLive
                      ? Color.red.opacity(0.08)
                      : Color.secondary.opacity(0.05))
        )
    }
    
    // MARK: - 팀 스코어 행
    
    private var scoreRow: some View {
        VStack(spacing: 0) {
            teamScoreLine(
                team: fixture.homeTeam,
                score: fixture.score.home,
                isHome: true
            )
            
            Divider().padding(.horizontal, 14)
            
            teamScoreLine(
                team: fixture.awayTeam,
                score: fixture.score.away,
                isHome: false
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - 인라인 이닝 테이블 (9이닝 이하, 스크롤 없음)

    /// MLB와 동일 구조: 팀명이 남은 공간을 차지하고 이닝 컬럼이 고정 너비로 나란히 붙음.
    /// 9이닝 모두 한 화면에 표시되며, 연장전(10이닝+)에서는 scoreRowWithSyncedPeriodScroll 사용.
    private var scoreRowInline: some View {
        VStack(spacing: 0) {
            teamScoreLine(team: fixture.homeTeam, score: fixture.score.home, isHome: true)
            Divider().padding(.horizontal, 14)
            teamScoreLine(team: fixture.awayTeam, score: fixture.score.away, isHome: false)
            // 이닝 번호 라벨 행 (teamScoreLine의 레이아웃과 동일 구조)
            HStack(spacing: 10) {
                Color.clear.frame(width: 28, height: 1).accessibilityHidden(true)
                Color.clear.frame(maxWidth: .infinity, minHeight: 1).accessibilityHidden(true)
                HStack(spacing: 0) {
                    ForEach(fixture.periods) { period in
                        Text(verbatim: period.period)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(width: periodColumnWidth, alignment: .center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                Text(String(localized: "scoreboard.total", defaultValue: "합계"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.04))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
        }
        .padding(.vertical, 4)
    }

    /// 피리어드 열이 많을 때 가로 스크롤로 한 번에 맞춤 (야구 연장 등)
    private var scoreRowWithSyncedPeriodScroll: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                teamLeadingOnly(team: fixture.homeTeam, isHome: true)
                Divider().padding(.horizontal, 14)
                teamLeadingOnly(team: fixture.awayTeam, isHome: false)
                HStack(spacing: 10) {
                    Color.clear.frame(width: 28, height: 1).accessibilityHidden(true)
                    Color.clear.frame(maxWidth: .infinity, minHeight: 1).accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: 200, alignment: .leading)
            .layoutPriority(1)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(fixture.periods) { period in
                            Text(verbatim: period.home.map { String($0) } ?? "-")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: periodColumnWidth, alignment: .center)
                        }
                    }
                    .padding(.vertical, 10)

                    Divider()

                    HStack(spacing: 0) {
                        ForEach(fixture.periods) { period in
                            Text(verbatim: period.away.map { String($0) } ?? "-")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: periodColumnWidth, alignment: .center)
                        }
                    }
                    .padding(.vertical, 10)

                    HStack(spacing: 0) {
                        ForEach(fixture.periods) { period in
                            Text(verbatim: period.period)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .frame(width: periodColumnWidth, alignment: .center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.04))
                }
            }
            .layoutPriority(0)

            VStack(spacing: 0) {
                Text(verbatim: fixture.score.home.map { String($0) } ?? "-")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(scoreHighlight(isHome: true))
                    .frame(width: 40, alignment: .trailing)
                    .padding(.vertical, 10)

                Divider().padding(.horizontal, 4)

                Text(verbatim: fixture.score.away.map { String($0) } ?? "-")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(scoreHighlight(isHome: false))
                    .frame(width: 40, alignment: .trailing)
                    .padding(.vertical, 10)

                Text(String(localized: "scoreboard.total", defaultValue: "합계"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
    }

    private func teamLeadingOnly(team: LiveTeamInfo, isHome: Bool) -> some View {
        HStack(spacing: 10) {
            teamLogo(team)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: liveFixtureTeamDisplayName(team.name))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if isHome {
                    Text(String(localized: "scoreboard.side.home", defaultValue: "홈"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }
    
    private func teamScoreLine(team: LiveTeamInfo, score: Int?, isHome: Bool) -> some View {
        HStack(spacing: 10) {
            teamLogo(team)

            // 팀명 열을 동일한 가변 폭으로 맞춰 홈/원정·헤더 행의 피리어드 열이 한 줄로 정렬됨
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: liveFixtureTeamDisplayName(team.name))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if isHome {
                    Text(String(localized: "scoreboard.side.home", defaultValue: "홈"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !fixture.periods.isEmpty {
                HStack(spacing: 0) {
                    ForEach(fixture.periods) { period in
                        let val = isHome ? period.home : period.away
                        Text(verbatim: val.map { String($0) } ?? "-")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: periodColumnWidth, alignment: .center)
                    }
                }
            }

            Text(verbatim: score.map { String($0) } ?? "-")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(scoreHighlight(isHome: isHome))
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    // MARK: - 헬퍼

    private func liveFixtureTeamDisplayName(_ raw: String) -> String {
        KBOTeamLogoAsset.uiDisplayName(forTeamName: raw, leagueCode: fixture.league.name == "KBO" ? "KBO" : nil)
    }
    
    private var periodColumnWidth: CGFloat {
        let count = fixture.periods.count
        if count <= 4 { return 28 }   // NFL·농구: 4쿼터
        if count <= 9 { return 14 }   // 야구 9이닝: 인라인 레이아웃에서 한 화면에 표시
        return 18                      // 10이닝+: 스크롤 레이아웃
    }
    
    private func scoreHighlight(isHome: Bool) -> Color {
        guard let homeScore = fixture.score.home,
              let awayScore = fixture.score.away,
              fixture.status.isFinished || fixture.isLive else {
            return .primary
        }
        let isWinning = isHome ? homeScore > awayScore : awayScore > homeScore
        let isTied = homeScore == awayScore
        if isTied { return .orange }
        return isWinning ? .green : .primary
    }
    
    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MdHHmm")
        return formatter.string(from: date)
    }
    
    private func teamLogo(_ team: LiveTeamInfo) -> some View {
        let assetName = fixture.league.name == "KBO"
            ? KBOTeamLogoAsset.imageName(forTeamName: team.name)
            : nil
        return Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else if let urlStr = team.logoURL, let url = URL(string: urlStr) {
                KFImage.url(url)
                    .placeholder {
                        Image(systemName: "sportscourt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .onFailureView {
                        Image(systemName: "sportscourt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "sportscourt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - LIVE 깜빡임 인디케이터

struct LiveIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 7, height: 7)
            .opacity(isAnimating ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - 예정 경기 카드 (스코어보드 스타일)

struct UpcomingFixtureCard: View {
    let fixture: LiveFixture
    let sportType: SportType

    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text(String(localized: "match.status.scheduledShort", defaultValue: "경기 예정"))
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text(fixture.league.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: sportType.iconName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                    .fill(Color.blue.opacity(0.06))
            )
            
            // 팀 VS 팀
            HStack(spacing: 16) {
                teamBlock(team: fixture.homeTeam, label: String(localized: "scoreboard.side.home", defaultValue: "홈"))
                
                VStack(spacing: 4) {
                    Text(String(localized: "sports.card.vs", defaultValue: "VS"))
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                    if let time = fixture.startTime {
                        Text(dateString(time))
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                
                teamBlock(team: fixture.awayTeam, label: String(localized: "teamInfo.away", defaultValue: "원정"))
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.blue.opacity(colorScheme == .light ? 0.32 : 0.22), lineWidth: 1)
        )
    }
    
    private func upcomingFixtureTeamDisplayName(_ raw: String) -> String {
        KBOTeamLogoAsset.uiDisplayName(forTeamName: raw, leagueCode: fixture.league.name == "KBO" ? "KBO" : nil)
    }

    private func teamBlock(team: LiveTeamInfo, label: String) -> some View {
        let assetName = fixture.league.name == "KBO"
            ? KBOTeamLogoAsset.imageName(forTeamName: team.name)
            : nil
        return VStack(spacing: 6) {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
            } else if let url = team.logoURL, let imgURL = URL(string: url) {
                KFImage.url(imgURL)
                    .placeholder {
                        Image(systemName: "sportscourt").foregroundStyle(.secondary)
                    }
                    .onFailureView {
                        Image(systemName: "sportscourt").foregroundStyle(.secondary)
                    }
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
            }
            Text(verbatim: upcomingFixtureTeamDisplayName(team.name))
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(verbatim: label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MdHHmm")
        return formatter.string(from: date)
    }
}

// MARK: - 복수 경기 스코어보드 컨테이너

struct LiveScoreboardSection: View {
    let fixtures: [LiveFixture]
    let sportType: SportType
    
    private var liveFixtures: [LiveFixture] { fixtures.filter { $0.isLive } }
    private var upcomingFixtures: [LiveFixture] { fixtures.filter { $0.isUpcoming } }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // LIVE 경기
            if !liveFixtures.isEmpty {
                ForEach(liveFixtures) { fixture in
                    LiveScoreboardView(fixture: fixture, sportType: sportType)
                }
            }
            
            // 예정 경기
            if !upcomingFixtures.isEmpty {
                ForEach(upcomingFixtures) { fixture in
                    UpcomingFixtureCard(fixture: fixture, sportType: sportType)
                }
            }
        }
    }
}

// MARK: - 프리뷰

#Preview("LIVE 경기 - NFL") {
    let fixture = LiveFixture(
        id: 1,
        homeTeam: LiveTeamInfo(id: 25, name: "San Francisco 49ers", logoURL: "https://a.espncdn.com/i/teamlogos/nfl/500/sf.png"),
        awayTeam: LiveTeamInfo(id: 20, name: "Seattle Seahawks", logoURL: "https://a.espncdn.com/i/teamlogos/nfl/500/sea.png"),
        score: LiveScore(home: 24, away: 17),
        status: LiveFixtureStatus(short: "3Q", elapsed: 7, period: "3Q"),
        league: LiveLeagueInfo(id: 1, name: "NFL", season: 2025),
        startTime: Date(),
        periods: [
            PeriodScore(period: "1Q", home: 7, away: 7),
            PeriodScore(period: "2Q", home: 10, away: 3),
            PeriodScore(period: "3Q", home: 7, away: 7),
            PeriodScore(period: "4Q", home: nil, away: nil),
        ]
    )
    
    ScrollView {
        VStack(spacing: 16) {
            LiveScoreboardView(fixture: fixture, sportType: .americanFootball)
            
            let soccer = LiveFixture(
                id: 2,
                homeTeam: LiveTeamInfo(id: 50, name: "Manchester City", logoURL: "https://a.espncdn.com/i/teamlogos/soccer/500/382.png"),
                awayTeam: LiveTeamInfo(id: 40, name: "Arsenal", logoURL: "https://a.espncdn.com/i/teamlogos/soccer/500/359.png"),
                score: LiveScore(home: 1, away: 1),
                status: LiveFixtureStatus(short: "2H", elapsed: 67, period: nil),
                league: LiveLeagueInfo(id: 39, name: "EPL", season: 2025),
                startTime: Date(),
                periods: [
                    PeriodScore(period: "전반", home: 1, away: 0),
                    PeriodScore(period: "후반", home: 0, away: 1),
                ]
            )
            LiveScoreboardView(fixture: soccer, sportType: .soccer)
        }
        .padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
