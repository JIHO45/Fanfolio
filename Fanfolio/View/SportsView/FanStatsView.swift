//
//  FanStatsView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI

struct FanStatsView: View {
    let folder: SportsFanFolder
    
    @State private var showingSharePreviewSheet = false
    
    // MARK: - 통계 계산기
    /// FanStatsCalculator에 경기 배열을 주입합니다.
    /// 로직을 View와 분리했기 때문에 테스트 코드에서 View 없이도 이 계산기를 검증할 수 있습니다.
    private var calc: FanStatsCalculator { FanStatsCalculator(matches: folder.matches) }

    // MARK: - 기본 통계 (FanStatsCalculator에 위임)
    private var completedMatches: [SportsModel] { calc.completedMatches }
    private var wins:             Int           { calc.wins }
    private var losses:           Int           { calc.losses }
    private var draws:            Int           { calc.draws }
    private var totalCompleted:   Int           { calc.totalCompleted }
    private var winRate:          Double        { calc.winRate }
    private var luckyInfo: (emoji: String, title: String, subtitle: String) { calc.luckyInfo }
    private var maxWinStreak:     Int           { calc.maxWinStreak }
    private var opponentRecords: [OpponentRecord] { calc.opponentRecords }

    private var homeMatches: [SportsModel] { completedMatches.filter {  $0.isHomeGame } }
    private var awayMatches: [SportsModel] { completedMatches.filter { !$0.isHomeGame } }

    private var rateColor: Color {
        winRate >= 50 ? .green : (winRate >= 30 ? .orange : .red)
    }
    
    // MARK: - 월별 데이터 (최근 12개월)
    private var monthlyData: [MonthlyRecord] {
        let calendar = Calendar.current
        return (0..<12).reversed().compactMap { i -> MonthlyRecord? in
            guard let date = calendar.date(byAdding: .month, value: -i, to: Date()) else { return nil }
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)
            let count = completedMatches.filter { match in
                guard let d = match.date else { return false }
                return calendar.component(.month, from: d) == month
                    && calendar.component(.year, from: d) == year
            }.count
            return MonthlyRecord(month: month, count: count)
        }
    }
    
    // MARK: - 마일스톤
    private var milestones: [FanMilestone] {
        let hasAway = completedMatches.contains { !$0.isHomeGame }
        let shutoutWin = completedMatches.contains { $0.matchResult == .win && $0.opponentScore == 0 }
        let homeWins = homeMatches.filter { $0.matchResult == .win }.count
        let awayCount = awayMatches.count
        let hasRival = opponentRecords.contains { $0.total >= 5 }
        
        return [
            FanMilestone(id: "first", emoji: "🎫", title: "첫 직관", desc: "첫 경기 기록", isUnlocked: totalCompleted >= 1),
            FanMilestone(id: "ten", emoji: "⭐️", title: "10회 직관", desc: "10경기 기록 달성", isUnlocked: totalCompleted >= 10),
            FanMilestone(id: "twentyfive", emoji: "🌟", title: "25회 직관", desc: "25경기 기록 달성", isUnlocked: totalCompleted >= 25),
            FanMilestone(id: "fifty", emoji: "💫", title: "50회 직관", desc: "50경기 기록 달성", isUnlocked: totalCompleted >= 50),
            FanMilestone(id: "hundred", emoji: "🏆", title: "100회 직관", desc: "100경기 기록 달성", isUnlocked: totalCompleted >= 100),
            FanMilestone(id: "away", emoji: "🚌", title: "첫 원정", desc: "원정 경기 기록", isUnlocked: hasAway),
            FanMilestone(id: "streak3", emoji: "🔥", title: "3연승 목격", desc: "연속 3승 달성", isUnlocked: maxWinStreak >= 3),
            FanMilestone(id: "streak5", emoji: "⚡️", title: "5연승 목격", desc: "연속 5승 달성", isUnlocked: maxWinStreak >= 5),
            FanMilestone(id: "shutout", emoji: "🛡️", title: "완봉승 목격", desc: "상대 무득점 승리", isUnlocked: shutoutWin),
            FanMilestone(id: "rival", emoji: "🎯", title: "라이벌 마니아", desc: "같은 상대 5경기 이상", isUnlocked: hasRival),
            FanMilestone(id: "home10", emoji: "🏠", title: "홈 지킴이", desc: "홈경기 10승 이상", isUnlocked: homeWins >= 10),
            FanMilestone(id: "road5", emoji: "⚔️", title: "원정 전사", desc: "원정 5경기 이상", isUnlocked: awayCount >= 5),
        ]
    }
    
    private var unlockedMilestones: [FanMilestone] { milestones.filter { $0.isUnlocked } }
    
    // MARK: - Body
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if totalCompleted == 0 {
                    ContentUnavailableView(
                        "완료된 경기가 없습니다",
                        systemImage: "chart.bar",
                        description: Text("경기를 완료로 기록하면 통계가 나타납니다.")
                    )
                } else {
                    luckyFanCard
                    recordSummaryCard
                    opponentSection
                    heatmapSection
                    milestoneSection
                    seasonReportButton
                }
            }
            .padding()
        }
        .navigationTitle("팬 통계")
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $showingSharePreviewSheet) {
            SharePreviewView { style in
                await Task { generateSeasonReport(style: style) }.value
            }
        }
    }
}

// MARK: - 럭키팬 지수 카드
extension FanStatsView {
    private var luckyFanCard: some View {
        VStack(spacing: 16) {
            Text(luckyInfo.emoji)
                .font(.system(size: 52))
            
            Text(luckyInfo.title)
                .font(.title2.bold())
            
            Text(luckyInfo.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // 승률 원형 프로그레스
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: winRate / 100)
                    .stroke(rateColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: winRate)
                VStack(spacing: 2) {
                    Text("\(Int(winRate))%")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                    Text("승률")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)
            
            if maxWinStreak >= 2 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("최다 연승: \(maxWinStreak)연승")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

// MARK: - 전적 요약 카드
extension FanStatsView {
    private var recordSummaryCard: some View {
        VStack(spacing: 16) {
            // 섹션 제목
            HStack {
                Label("전적 요약", systemImage: "chart.bar.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(totalCompleted)경기")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 승/패/무 숫자
            HStack(spacing: 0) {
                statItem(value: "\(wins)", label: "승", color: .green)
                statItem(value: "\(losses)", label: "패", color: .red)
                statItem(value: "\(draws)", label: "무", color: .orange)
            }
            
            // 비율 바
            GeometryReader { geo in
                let total = CGFloat(max(totalCompleted, 1))
                HStack(spacing: 2) {
                    if wins > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(MatchResult.win.color)
                            .frame(width: max(geo.size.width * CGFloat(wins) / total, 8))
                    }
                    if losses > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(MatchResult.loss.color)
                            .frame(width: max(geo.size.width * CGFloat(losses) / total, 8))
                    }
                    if draws > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(MatchResult.draw.color)
                    }
                }
            }
            .frame(height: 8)
            
            Divider()
            
            // 홈 vs 원정
            HStack(spacing: 0) {
                homeAwayBlock(title: "홈", matches: homeMatches)
                
                Divider()
                    .frame(height: 50)
                    .padding(.horizontal, 16)
                
                homeAwayBlock(title: "원정", matches: awayMatches)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func homeAwayBlock(title: String, matches: [SportsModel]) -> some View {
        let w = matches.filter { $0.matchResult == .win }.count
        let l = matches.filter { $0.matchResult == .loss }.count
        let d = matches.filter { $0.matchResult == .draw }.count
        
        return VStack(spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("\(matches.count)경기")
                .font(.subheadline.weight(.semibold))
            Text("\(w)승 \(l)패 \(d)무")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 상대별 전적
extension FanStatsView {
    private var opponentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("상대별 전적", systemImage: "person.2.fill")
                    .font(.subheadline.bold())
                Spacer()
            }
            
            ForEach(opponentRecords) { record in
                HStack {
                    Text(record.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Text("\(record.wins)승 \(record.losses)패 \(record.draws)무")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("\(Int(record.winRate))%")
                            .font(.caption.bold())
                            .foregroundStyle(record.winRate >= 50 ? .green : .red)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                .padding(.vertical, 4)
                
                if record.id != opponentRecords.last?.id {
                    Divider()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

// MARK: - 월별 히트맵
extension FanStatsView {
    private var heatmapSection: some View {
        let maxCount = max(monthlyData.map(\.count).max() ?? 1, 1)
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("월별 기록", systemImage: "calendar.badge.clock")
                    .font(.subheadline.bold())
                Spacer()
                Text("최근 12개월")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 히트맵 그리드
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(monthlyData) { data in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(heatmapColor(count: data.count, max: maxCount))
                            .frame(height: 40)
                            .overlay {
                                if data.count > 0 {
                                    Text("\(data.count)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(
                                            data.count > 0
                                                ? .white
                                                : .secondary
                                        )
                                }
                            }
                        
                        Text("\(data.month)월")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // 범례
            HStack(spacing: 12) {
                Spacer()
                Text("적음")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    ForEach(0..<4) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.1 + Double(i) * 0.25))
                            .frame(width: 12, height: 12)
                    }
                }
                Text("많음")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    private func heatmapColor(count: Int, max: Int) -> Color {
        guard count > 0 else { return Color.secondary.opacity(0.08) }
        let intensity = Double(count) / Double(max)
        return Color.green.opacity(0.2 + intensity * 0.65)
    }
}

// MARK: - 마일스톤 뱃지
extension FanStatsView {
    private var milestoneSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("직관 마일스톤", systemImage: "trophy.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(unlockedMilestones.count)/\(milestones.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(milestones) { milestone in
                    VStack(spacing: 6) {
                        Text(milestone.emoji)
                            .font(.system(size: 28))
                            .grayscale(milestone.isUnlocked ? 0 : 1)
                            .opacity(milestone.isUnlocked ? 1 : 0.3)
                        
                        Text(milestone.title)
                            .font(.caption2.bold())
                            .lineLimit(1)
                        
                        Text(milestone.desc)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(milestone.isUnlocked
                                  ? Color.yellow.opacity(0.08)
                                  : Color.secondary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                milestone.isUnlocked
                                    ? Color.yellow.opacity(0.3)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}


// MARK: - 선수 이미지 뷰 (누끼 / 일반 / fallback 자동 전환)
struct PlayerImageView: View {
    let cutoutURL: String?
    let photoURL: String?
    let fallbackTeamLogoURL: String?
    let fallbackGradient: [Color]
    var size: CGFloat = 44
    
    var body: some View {
        ZStack {
            if let cutoutStr = cutoutURL, let url = URL(string: cutoutStr) {
                // 누끼 이미지 (투명 배경, TheSportsDB strCutout)
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        fallbackView
                    case .empty:
                        ProgressView().scaleEffect(0.6)
                    @unknown default:
                        fallbackView
                    }
                }
            } else if let photoStr = photoURL, let url = URL(string: photoStr) {
                // 일반 선수 사진
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .clipped()
                    case .failure:
                        fallbackView
                    default:
                        ProgressView().scaleEffect(0.6)
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
    }
    
    private var fallbackView: some View {
        ZStack {
            LinearGradient(
                colors: fallbackGradient.map { $0.opacity(0.3) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            if let logoStr = fallbackTeamLogoURL, let url = URL(string: logoStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .opacity(0.6)
                    } else {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            } else {
                Image(systemName: "person.fill")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - 스켈레톤 shimmer 효과
extension View {
    @ViewBuilder
    func shimmer() -> some View {
        self.overlay(
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, .white.opacity(0.4), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: -geo.size.width)
                .animation(
                    .linear(duration: 1.2).repeatForever(autoreverses: false),
                    value: true
                )
            }
            .allowsHitTesting(false)
        )
    }
}

// MARK: - 시즌 리포트 공유
extension FanStatsView {
    private var seasonReportButton: some View {
        Button {
            showingSharePreviewSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                Text("시즌 리포트 공유하기")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.15, green: 0.15, blue: 0.3), Color(red: 0.2, green: 0.1, blue: 0.35)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    @MainActor
    private func generateSeasonReport(style: ShareStyle) -> UIImage? {
        let topOpp = opponentRecords.first
        
        let content = SeasonReportContent(
            teamName: folder.displayName,
            sportType: folder.sportType,
            winRate: winRate,
            wins: wins,
            losses: losses,
            draws: draws,
            totalGames: totalCompleted,
            luckyEmoji: luckyInfo.emoji,
            luckyTitle: luckyInfo.title,
            maxStreak: maxWinStreak,
            topOpponentName: topOpp?.name,
            topOpponentRecord: topOpp.map { "\($0.wins)승 \($0.losses)패 \($0.draws)무" },
            unlockedEmojis: unlockedMilestones.map(\.emoji).joined(separator: " "),
            style: style
        )
        
        let renderer = ImageRenderer(
            content: content.frame(width: 390)
        )
        renderer.scale = 3
        return renderer.uiImage
    }
}

// MARK: - 시즌 리포트 이미지 뷰 (라이트/다크 지원)
private struct SeasonReportContent: View {
    let teamName: String
    let sportType: SportType
    let winRate: Double
    let wins: Int
    let losses: Int
    let draws: Int
    let totalGames: Int
    let luckyEmoji: String
    let luckyTitle: String
    let maxStreak: Int
    let topOpponentName: String?
    let topOpponentRecord: String?
    let unlockedEmojis: String
    let style: ShareStyle
    
    // 스타일별 색상
    private var bgGradient: LinearGradient {
        style == .dark
            ? LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.14),
                    Color(red: 0.12, green: 0.06, blue: 0.22),
                    Color(red: 0.08, green: 0.08, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.96, blue: 0.97),
                    Color(red: 0.98, green: 0.97, blue: 1.0),
                    Color(red: 0.95, green: 0.95, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }
    private var textMain: Color {
        style == .dark ? .white : Color(red: 0.1, green: 0.1, blue: 0.1)
    }
    private var textSub: Color {
        style == .dark ? .white.opacity(0.5) : Color(red: 0.5, green: 0.5, blue: 0.5)
    }
    private var textDim: Color {
        style == .dark ? .white.opacity(0.4) : Color(red: 0.7, green: 0.7, blue: 0.7)
    }
    private var dividerColor: Color {
        style == .dark ? .white.opacity(0.08) : Color(red: 0.85, green: 0.85, blue: 0.87)
    }
    private var luckyColor: Color {
        style == .dark ? .yellow : Color(red: 0.85, green: 0.55, blue: 0.0)
    }
    private var brandColor: Color {
        style == .dark ? .white.opacity(0.2) : Color(red: 0.8, green: 0.8, blue: 0.82)
    }
    
    var body: some View {
        VStack(spacing: 28) {
            // 헤더
            VStack(spacing: 8) {
                Text("나의 시즌 리포트")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(textSub)
                    .tracking(2)
                
                HStack(spacing: 8) {
                    Image(systemName: sportType.iconName)
                    Text(teamName)
                }
                .font(.title.bold())
                .foregroundStyle(textMain)
            }
            
            // 승률
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(Int(winRate))")
                        .font(.system(size: 80, weight: .heavy, design: .rounded))
                        .foregroundStyle(textMain)
                    
                    Text("%")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(textSub)
                }
                
                Text("승률")
                    .font(.subheadline)
                    .foregroundStyle(textSub)
            }
            
            // 럭키 지수
            Text("\(luckyEmoji) \(luckyTitle)")
                .font(.title3.bold())
                .foregroundStyle(luckyColor)
            
            // 구분선
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
                .padding(.horizontal, 40)
            
            // 전적
            HStack(spacing: 20) {
                reportStat(value: "\(totalGames)", label: "경기")
                reportStat(value: "\(wins)", label: "승")
                reportStat(value: "\(losses)", label: "패")
                reportStat(value: "\(draws)", label: "무")
            }
            
            // 최다 연승
            if maxStreak >= 2 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("최다 연승")
                        .foregroundStyle(textSub)
                    Text("\(maxStreak)연승")
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)
            }
            
            // 최다 대결 상대
            if let opponent = topOpponentName, let record = topOpponentRecord {
                VStack(spacing: 6) {
                    Text("최다 대결")
                        .font(.caption)
                        .foregroundStyle(textDim)
                    Text("vs \(opponent)")
                        .font(.headline)
                        .foregroundStyle(textMain)
                    Text(record)
                        .font(.caption)
                        .foregroundStyle(textSub)
                }
            }
            
            // 구분선
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
                .padding(.horizontal, 40)
            
            // 달성 뱃지
            if !unlockedEmojis.isEmpty {
                VStack(spacing: 10) {
                    Text("달성 뱃지")
                        .font(.caption)
                        .foregroundStyle(textDim)
                    Text(unlockedEmojis)
                        .font(.title2)
                }
            }
            
            // 브랜딩
            Text("Fanfolio")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(brandColor)
                .tracking(3)
                .padding(.top, 8)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .background(bgGradient)
    }
    
    private func reportStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(textMain)
            Text(label)
                .font(.caption)
                .foregroundStyle(textDim)
        }
    }
}

// MARK: - 데이터 모델
// OpponentRecord는 FanStatsCalculator.swift로 이동했습니다.

private struct MonthlyRecord: Identifiable {
    let id = UUID()
    let month: Int
    let count: Int
}

private struct FanMilestone: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let desc: String
    let isUnlocked: Bool
}

// MARK: - Previews
#Preview {
    NavigationStack {
        FanStatsView(folder: {
            let folder = SportsFanFolder(name: "LG 트윈스", sportType: .baseball)
            
            let data: [(String, Int, Int, MatchResult, Bool)] = [
                ("두산 베어스", 5, 2, .win, true),
                ("두산 베어스", 3, 5, .loss, true),
                ("두산 베어스", 7, 1, .win, true),
                ("SSG 랜더스", 3, 1, .win, false),
                ("SSG 랜더스", 4, 2, .win, false),
                ("한화 이글스", 7, 4, .win, true),
                ("한화 이글스", 2, 3, .loss, false),
                ("NC 다이노스", 2, 5, .loss, true),
                ("NC 다이노스", 1, 0, .win, true),
                ("키움 히어로즈", 4, 4, .draw, true),
                ("KT 위즈", 6, 3, .win, false),
                ("삼성 라이온즈", 1, 3, .loss, true),
                ("KIA 타이거즈", 8, 0, .win, true),
                ("롯데 자이언츠", 3, 6, .loss, false),
                ("두산 베어스", 4, 1, .win, true),
            ]
            
            for (i, d) in data.enumerated() {
                let m = SportsModel(
                    title: "LG vs \(d.0)",
                    opponentTeam: d.0,
                    myTeamScore: d.1,
                    opponentScore: d.2,
                    matchResult: d.3,
                    matchStatus: .completed,
                    isHomeGame: d.4,
                    date: Calendar.current.date(byAdding: .day, value: -(i * 5), to: Date()),
                    location: "잠실 야구장",
                    orderIndex: i
                )
                m.folder = folder
                folder.matches.append(m)
            }
            
            return folder
        }())
    }
}
