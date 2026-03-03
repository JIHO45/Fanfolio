//
//  LiveScoreboardView.swift
//  Fanfolio
//
//  스포츠 중계 방송 스타일의 실시간 스코어보드
//

import SwiftUI

// MARK: - 스코어보드 메인 뷰

struct LiveScoreboardView: View {
    let fixture: LiveFixture
    let sportType: SportType
    
    var body: some View {
        VStack(spacing: 0) {
            headerBar
            scoreRow
            if !fixture.periods.isEmpty {
                periodTable
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    fixture.isLive
                        ? Color.red.opacity(0.4)
                        : Color.secondary.opacity(0.15),
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
            
            Text("·")
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
    
    private func teamScoreLine(team: LiveTeamInfo, score: Int?, isHome: Bool) -> some View {
        HStack(spacing: 10) {
            // 팀 로고
            teamLogo(url: team.logoURL)
            
            // 팀 이름
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if isHome {
                    Text("홈")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // 쿼터별 점수 (피리어드 있을 때)
            if !fixture.periods.isEmpty {
                HStack(spacing: 0) {
                    ForEach(fixture.periods) { period in
                        let val = isHome ? period.home : period.away
                        Text(val.map { "\($0)" } ?? "-")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: periodColumnWidth)
                    }
                }
            }
            
            // 합계 점수
            let scoreVal = score
            Text(scoreVal.map { "\($0)" } ?? "-")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(scoreHighlight(isHome: isHome))
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    // MARK: - 피리어드 헤더 테이블
    
    private var periodTable: some View {
        HStack(spacing: 0) {
            // 빈 공간 (팀명 영역)
            Spacer()
            
            // 쿼터/이닝 헤더
            HStack(spacing: 0) {
                ForEach(fixture.periods) { period in
                    Text(period.period)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: periodColumnWidth)
                }
            }
            
            // "합계" 헤더
            Text("합계")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 14)
        }
        .padding(.leading, 14)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.04))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
    }
    
    // MARK: - 헬퍼
    
    private var periodColumnWidth: CGFloat {
        // 피리어드 수에 따라 컬럼 너비 조정
        let count = fixture.periods.count
        if count <= 4 { return 28 }
        if count <= 9 { return 22 }
        return 18
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
        formatter.dateFormat = "M/d HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
    
    private func teamLogo(url: String?) -> some View {
        Group {
            if let urlStr = url, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Image(systemName: "sportscourt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
            .onAppear { isAnimating = true }
    }
}

// MARK: - 예정 경기 카드 (스코어보드 스타일)

struct UpcomingFixtureCard: View {
    let fixture: LiveFixture
    let sportType: SportType
    
    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text("경기 예정")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Text("·")
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
                teamBlock(team: fixture.homeTeam, label: "홈")
                
                VStack(spacing: 4) {
                    Text("VS")
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                    if let time = fixture.startTime {
                        Text(dateString(time))
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                
                teamBlock(team: fixture.awayTeam, label: "원정")
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func teamBlock(team: LiveTeamInfo, label: String) -> some View {
        VStack(spacing: 6) {
            if let url = team.logoURL, let imgURL = URL(string: url) {
                AsyncImage(url: imgURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Image(systemName: "sportscourt").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 40, height: 40)
            }
            Text(team.name)
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
}

// MARK: - 복수 경기 스코어보드 컨테이너

struct LiveScoreboardSection: View {
    let fixtures: [LiveFixture]
    let sportType: SportType
    
    private var liveFixtures: [LiveFixture] { fixtures.filter { $0.isLive } }
    private var upcomingFixtures: [LiveFixture] { fixtures.filter { $0.isUpcoming } }
    private var finishedFixtures: [LiveFixture] { fixtures.filter { $0.status.isFinished } }
    
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
            
            // 최근 종료 경기
            if !finishedFixtures.isEmpty {
                ForEach(finishedFixtures) { fixture in
                    LiveScoreboardView(fixture: fixture, sportType: sportType)
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
