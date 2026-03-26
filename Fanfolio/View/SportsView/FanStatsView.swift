//
//  FanStatsView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import Kingfisher

struct FanStatsView: View {
    let folder: SportsFanFolder
    
    @State private var showingSharePreviewSheet = false
    @State private var statsResult: FanStatsResult?
    @State private var isComputing = false

    private var rateColor: Color {
        guard let r = statsResult else { return .secondary }
        return r.winRate >= 50 ? .green : (r.winRate >= 30 ? .orange : .red)
    }

    private static let milestoneDefinitions: [(id: String, emoji: String, title: LocalizedStringKey, desc: LocalizedStringKey)] = [
        ("first", "🎫", "첫 직관", "첫 경기 기록"),
        ("ten", "⭐️", "10회 직관", "10경기 기록 달성"),
        ("twentyfive", "🌟", "25회 직관", "25경기 기록 달성"),
        ("fifty", "💫", "50회 직관", "50경기 기록 달성"),
        ("hundred", "🏆", "100회 직관", "100경기 기록 달성"),
        ("away", "🚌", "첫 원정", "원정 경기 기록"),
        ("streak3", "🔥", "3연승 목격", "연속 3승 달성"),
        ("streak5", "⚡️", "5연승 목격", "연속 5승 달성"),
        ("shutout", "🛡️", "완봉승 목격", "상대 무득점 승리"),
        ("rival", "🎯", "라이벌 마니아", "같은 상대 5경기 이상"),
        ("home10", "🏠", "홈 지킴이", "홈경기 10승 이상"),
        ("road5", "⚔️", "원정 전사", "원정 5경기 이상"),
    ]

    // MARK: - Body
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if isComputing {
                    ProgressView("통계 계산 중…")
                        .frame(maxWidth: .infinity)
                        .padding(40)
                } else if let r = statsResult, r.totalCompleted == 0 {
                    ContentUnavailableView(
                        "완료된 경기가 없습니다",
                        systemImage: "chart.bar",
                        description: Text("경기를 완료로 기록하면 통계가 나타납니다.")
                    )
                } else if let r = statsResult {
                    luckyFanCard(r)
                    recordSummaryCard(r)
                    opponentSection(r)
                    heatmapSection(r)
                    milestoneSection(r)
                    seasonReportButton(r)
                }
            }
            .padding()
        }
        .navigationTitle("팬 통계")
        .background(Color(uiColor: .systemGroupedBackground))
        // 경기 추가·수정·폴더 메타 변경 시 통계를 다시 계산
        .task(id: folder.fanfolioFolderTaskToken) { await computeStats() }
        .sheet(isPresented: $showingSharePreviewSheet) {
            SharePreviewView { style in
                await Task { generateSeasonReport(style: style) }.value
            }
        }
    }

    /// 메인에서 DTO로 매핑 후 백그라운드에서 계산, 결과만 메인에 반영.
    private func computeStats() async {
        isComputing = true
        let dto = folder.matches.map { MatchStatDTO(from: $0) }
        let result = await Task.detached(priority: .userInitiated) {
            FanStatsCalculator(data: dto).compute()
        }.value
        statsResult = result
        isComputing = false
    }
}

// MARK: - 럭키팬 지수 카드
extension FanStatsView {
    private func luckyFanCard(_ r: FanStatsResult) -> some View {
        VStack(spacing: 16) {
            Text(r.luckyInfo.emoji)
                .font(.system(size: 52))
            
            Text(r.luckyInfo.title)
                .font(.title2.bold())
            
            Text(r.luckyInfo.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: r.winRate / 100)
                    .stroke(rateColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: r.winRate)
                VStack(spacing: 2) {
                    Text("\(Int(r.winRate))%")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                    Text("승률")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)
            
            if r.maxWinStreak >= 2 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("최다 연승: \(r.maxWinStreak)연승")
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
    private func recordSummaryCard(_ r: FanStatsResult) -> some View {
        VStack(spacing: 16) {
            HStack {
                Label("전적 요약", systemImage: "chart.bar.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(r.totalCompleted)경기")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 0) {
                statItem(value: "\(r.wins)", label: "승", color: .green)
                statItem(value: "\(r.losses)", label: "패", color: .red)
                statItem(value: "\(r.draws)", label: "무", color: .orange)
            }
            
            GeometryReader { geo in
                let total = CGFloat(max(r.totalCompleted, 1))
                HStack(spacing: 2) {
                    if r.wins > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(MatchResult.win.color)
                            .frame(width: max(geo.size.width * CGFloat(r.wins) / total, 8))
                    }
                    if r.losses > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(MatchResult.loss.color)
                            .frame(width: max(geo.size.width * CGFloat(r.losses) / total, 8))
                    }
                    if r.draws > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(MatchResult.draw.color)
                    }
                }
            }
            .frame(height: 8)
            
            Divider()
            
            HStack(spacing: 0) {
                homeAwayBlock(title: "홈", wins: r.homeWins, losses: r.homeLosses, draws: r.homeDraws)
                Divider()
                    .frame(height: 50)
                    .padding(.horizontal, 16)
                homeAwayBlock(title: "원정", wins: r.awayWins, losses: r.awayLosses, draws: r.awayDraws)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    private func statItem(value: String, label: LocalizedStringKey, color: Color) -> some View {
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
    
    private func homeAwayBlock(title: LocalizedStringKey, wins: Int, losses: Int, draws: Int) -> some View {
        let w = wins
        let l = losses
        let d = draws
        let total = w + l + d
        return VStack(spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("\(total)경기")
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
    private func opponentSection(_ r: FanStatsResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("상대별 전적", systemImage: "person.2.fill")
                    .font(.subheadline.bold())
                Spacer()
            }
            
            ForEach(r.opponentRecords) { record in
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
                
                if record.id != r.opponentRecords.last?.id {
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
    private func heatmapSection(_ r: FanStatsResult) -> some View {
        let monthlyRecords = r.monthlyData.map { MonthlyRecord(month: $0.month, count: $0.count) }
        let maxCount = max(monthlyRecords.map(\.count).max() ?? 1, 1)
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("월별 기록", systemImage: "calendar.badge.clock")
                    .font(.subheadline.bold())
                Spacer()
                Text("최근 12개월")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(monthlyRecords) { data in
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
    private func milestoneSection(_ r: FanStatsResult) -> some View {
        let milestones = Self.milestoneDefinitions.map { def in
            FanMilestone(
                id: def.id,
                emoji: def.emoji,
                title: def.title,
                desc: def.desc,
                isUnlocked: r.milestoneUnlocks[def.id] ?? false
            )
        }
        let unlockedCount = milestones.filter(\.isUnlocked).count
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("직관 마일스톤", systemImage: "trophy.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(unlockedCount)/\(milestones.count)")
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


// MARK: - 선수 이미지 뷰 (선수 사진 / 유니폼 이니셜 플레이스홀더 자동 전환)
struct PlayerImageView: View {
    let imageURL: String?
    let fallbackTeamLogoURL: String?
    let fallbackGradient: [Color]
    var size: CGFloat = 44
    var playerName: String = ""
    var jerseyNumber: String? = nil
    var sportType: SportType? = nil

    private var teamColor: Color {
        fallbackGradient.first ?? .blue
    }

    var body: some View {
        ZStack {
            if let imgStr = imageURL, let url = URL(string: imgStr) {
                KFImage.url(url)
                    .placeholder { ProgressView().scaleEffect(0.6) }
                    .onFailureView { initialsPlaceholder }
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
    }

    private var initialsPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: fallbackGradient.map { $0.opacity(0.25) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 유니폼 실루엣 (종목에 따라 농구 저지 / 반팔 저지)
            Group {
                if sportType == .basketball {
                    BasketballJerseyShape()
                        .fill(teamColor.opacity(0.20))
                } else {
                    ShortSleeveJerseyShape()
                        .fill(teamColor.opacity(0.20))
                }
            }
            .padding(size * 0.07)

            VStack(spacing: 0) {
                if let number = jerseyNumber, !number.isEmpty {
                    Text("#\(number)")
                        .font(.system(size: max(7, size * 0.16), weight: .bold))
                        .foregroundStyle(teamColor.opacity(0.75))
                }
                Text(extractInitials(from: playerName))
                    .font(.system(
                        size: jerseyNumber == nil ? max(13, size * 0.36) : max(11, size * 0.30),
                        weight: .heavy,
                        design: .rounded
                    ))
                    .foregroundStyle(teamColor)
            }
        }
    }

    private func extractInitials(from name: String) -> String {
        let parts = name.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String((parts.last ?? "").prefix(1))).uppercased()
        } else if let first = parts.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
}

// MARK: - 농구 저지 실루엣 (민소매)
struct BasketballJerseyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()

        // V넥 왼쪽 시작
        p.move(to: CGPoint(x: 0.30 * w, y: 0.02 * h))
        // V넥 곡선
        p.addQuadCurve(
            to: CGPoint(x: 0.70 * w, y: 0.02 * h),
            control: CGPoint(x: 0.50 * w, y: 0.22 * h)
        )
        // 오른쪽 어깨 스트랩 상단
        p.addLine(to: CGPoint(x: 0.92 * w, y: 0.06 * h))
        // 오른쪽 암홀 (오목한 곡선 — 안으로 들어왔다가 내려감)
        p.addQuadCurve(
            to: CGPoint(x: 0.82 * w, y: 0.34 * h),
            control: CGPoint(x: 1.04 * w, y: 0.20 * h)
        )
        // 오른쪽 몸통 → 밑단
        p.addLine(to: CGPoint(x: 0.94 * w, y: h))
        p.addLine(to: CGPoint(x: 0.06 * w, y: h))
        // 왼쪽 몸통 위로
        p.addLine(to: CGPoint(x: 0.18 * w, y: 0.34 * h))
        // 왼쪽 암홀 (오목한 곡선)
        p.addQuadCurve(
            to: CGPoint(x: 0.08 * w, y: 0.06 * h),
            control: CGPoint(x: -0.04 * w, y: 0.20 * h)
        )
        // 왼쪽 어깨 스트랩 → 넥 시작으로 닫기
        p.addLine(to: CGPoint(x: 0.30 * w, y: 0.02 * h))
        p.closeSubpath()
        return p
    }
}

// MARK: - 반팔 저지 실루엣 (축구·야구·미식축구 등)
struct ShortSleeveJerseyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()

        // V넥 왼쪽 시작
        p.move(to: CGPoint(x: 0.34 * w, y: 0))
        // V넥 곡선
        p.addQuadCurve(
            to: CGPoint(x: 0.66 * w, y: 0),
            control: CGPoint(x: 0.50 * w, y: 0.17 * h)
        )
        // 오른쪽 어깨 → 소매 끝
        p.addLine(to: CGPoint(x: 1.00 * w, y: 0.21 * h))
        // 오른쪽 소매 하단
        p.addLine(to: CGPoint(x: 0.80 * w, y: 0.37 * h))
        // 오른쪽 몸통 → 밑단
        p.addLine(to: CGPoint(x: 0.92 * w, y: h))
        p.addLine(to: CGPoint(x: 0.08 * w, y: h))
        // 왼쪽 몸통 위로
        p.addLine(to: CGPoint(x: 0.20 * w, y: 0.37 * h))
        // 왼쪽 소매 하단
        p.addLine(to: CGPoint(x: 0.00 * w, y: 0.21 * h))
        // 왼쪽 어깨 → 넥 시작으로 닫기
        p.addLine(to: CGPoint(x: 0.34 * w, y: 0))
        p.closeSubpath()
        return p
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
    private func seasonReportButton(_ r: FanStatsResult) -> some View {
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
        guard let r = statsResult else { return nil }
        let topOpp = r.opponentRecords.first
        let unlockedEmojis = Self.milestoneDefinitions
            .filter { r.milestoneUnlocks[$0.id] ?? false }
            .map(\.emoji)
            .joined(separator: " ")

        let content = SeasonReportContent(
            teamName:          folder.displayName,
            sportType:         folder.sportType,
            winRate:           r.winRate,
            wins:              r.wins,
            losses:            r.losses,
            draws:             r.draws,
            totalGames:        r.totalCompleted,
            maxStreak:         r.maxWinStreak,
            topOpponentName:   topOpp?.name,
            topOpponentRecord: topOpp.map {
                String(format: String(localized: "sports.stats.record.winLossDraw", defaultValue: "%lld승 %lld패 %lld무"),
                       locale: .autoupdatingCurrent,
                       $0.wins, $0.losses, $0.draws)
            },
            unlockedEmojis:    unlockedEmojis,
            style:             style,
            fanArchetype:      r.fanArchetype,
            fanRankPercentile: r.fanRankPercentile,
            seasonHighlight:   r.seasonHighlight
        )

        let canvasWidth: CGFloat  = 390
        let canvasHeight: CGFloat = canvasWidth * 16 / 9
        let renderer = ImageRenderer(
            content: content.frame(width: canvasWidth, height: canvasHeight)
        )
        renderer.scale = 3
        return renderer.uiImage
    }
}

// MARK: - 시즌 리포트 이미지 뷰 (프리미엄 글래스모피즘)
private struct SeasonReportContent: View {
    let teamName:          String
    let sportType:         SportType
    let winRate:           Double
    let wins:              Int
    let losses:            Int
    let draws:             Int
    let totalGames:        Int
    let maxStreak:         Int
    let topOpponentName:   String?
    let topOpponentRecord: String?
    let unlockedEmojis:    String
    let style:             ShareStyle
    let fanArchetype:      FanArchetype
    let fanRankPercentile: Int
    let seasonHighlight:   SeasonHighlight?

    private var isDark: Bool { style == .dark }

    // MARK: 색상

    private var textMain:    Color { isDark ? .white : Color(red: 0.08, green: 0.08, blue: 0.12) }
    private var textSub:     Color { isDark ? .white.opacity(0.55) : Color(red: 0.40, green: 0.40, blue: 0.45) }
    private var textDim:     Color { isDark ? .white.opacity(0.35) : Color(red: 0.60, green: 0.60, blue: 0.65) }
    private var cardBg:      Color { isDark ? .white.opacity(0.09) : .white.opacity(0.58) }
    private var cardBorder:  Color { isDark ? .white.opacity(0.16) : .white.opacity(0.75) }
    private var accentGold:  Color { isDark ? Color(red: 1.0, green: 0.82, blue: 0.30) : Color(red: 0.85, green: 0.55, blue: 0.0) }
    private var barcodeInk:  Color { isDark ? .white.opacity(0.65) : Color(red: 0.12, green: 0.12, blue: 0.18).opacity(0.70) }

    // MARK: - Body
    // 캔버스: 390 × 693pt (9:16). 수직 패딩 40pt × 2 = 80pt 제외하면
    // 콘텐츠 + 섹션 간 spacing 모두 합쳐 613pt 이하여야 잘리지 않습니다.

    var body: some View {
        ZStack {
            meshBackground

            VStack(spacing: 8) {
                headerSection
                archetypeCard
                winRateCard
                streakOpponentRow
                if let h = seasonHighlight { highlightCard(h) }
                if !unlockedEmojis.isEmpty { badgesSection }
                Spacer(minLength: 0)
                barcodeSection
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 배경 (메시 그라데이션)

    private var meshBackground: some View {
        ZStack {
            (isDark
                ? Color(red: 0.05, green: 0.04, blue: 0.13)
                : Color(red: 0.96, green: 0.95, blue: 1.00))

            Circle()
                .fill(isDark
                    ? Color(red: 0.45, green: 0.05, blue: 0.85).opacity(0.55)
                    : Color(red: 1.00, green: 0.72, blue: 0.82).opacity(0.65))
                .frame(width: 320, height: 320)
                .blur(radius: 60)
                .offset(x: -100, y: -220)

            Circle()
                .fill(isDark
                    ? Color(red: 0.05, green: 0.25, blue: 0.90).opacity(0.45)
                    : Color(red: 0.65, green: 0.88, blue: 1.00).opacity(0.60))
                .frame(width: 280, height: 280)
                .blur(radius: 55)
                .offset(x: 120, y: 250)

            Circle()
                .fill(isDark
                    ? Color(red: 0.15, green: 0.05, blue: 0.55).opacity(0.30)
                    : Color(red: 0.88, green: 0.82, blue: 1.00).opacity(0.50))
                .frame(width: 200, height: 200)
                .blur(radius: 45)
                .offset(x: 40, y: 0)
        }
    }

    // MARK: - 헤더

    private var headerSection: some View {
        VStack(spacing: 7) {
            Text("나의 시즌 리포트")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(textDim)
                .tracking(3)

            HStack(spacing: 7) {
                Image(systemName: sportType.iconName)
                    .font(.title3)
                Text(teamName)
                    .font(.system(size: 22, weight: .heavy))
            }
            .foregroundStyle(textMain)
        }
    }

    // MARK: - 팬 유형 + 퍼센타일 카드

    private var archetypeCard: some View {
        glassCard {
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text(fanArchetype.emoji)
                        .font(.system(size: 28))
                    Text(fanArchetype.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(textMain)
                    Text(fanArchetype.subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(textSub)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(cardBorder)
                    .frame(width: 0.5, height: 52)

                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("상위")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(textSub)
                        Text("\(100 - fanRankPercentile)%")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(accentGold)
                    }
                    Text("팬 퍼센타일")
                        .font(.system(size: 9))
                        .foregroundStyle(textDim)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
        }
    }

    // MARK: - 승률 카드

    private var winRateCard: some View {
        glassCard {
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(winRate))")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(textMain)
                    Text("%")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(textSub)
                }

                Text("승률")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(textDim)
                    .tracking(2)

                GeometryReader { geo in
                    let total = CGFloat(max(totalGames, 1))
                    HStack(spacing: 2) {
                        if wins > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.green.opacity(0.85))
                                .frame(width: max(geo.size.width * CGFloat(wins) / total, 6))
                        }
                        if losses > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.red.opacity(0.75))
                                .frame(width: max(geo.size.width * CGFloat(losses) / total, 6))
                        }
                        if draws > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange.opacity(0.75))
                        }
                    }
                }
                .frame(height: 5)

                HStack(spacing: 0) {
                    statCell(value: "\(wins)",       label: "승",  color: .green)
                    statCell(value: "\(losses)",     label: "패",  color: .red)
                    statCell(value: "\(draws)",      label: "무",  color: .orange)
                    statCell(value: "\(totalGames)", label: "경기", color: textSub)
                }
            }
            .padding(12)
        }
    }

    private func statCell(value: String, label: LocalizedStringKey, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(textDim)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 연승 + 최다 대결 행

    private var streakOpponentRow: some View {
        HStack(spacing: 8) {
            glassCard {
                VStack(spacing: 5) {
                    Text(maxStreak >= 2 ? "🔥" : "—")
                        .font(.system(size: 22))
                    if maxStreak >= 2 {
                        Text("\(maxStreak)연승")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.orange)
                    } else {
                        Text("기록 없음")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(textDim)
                    }
                    Text("최다 연승")
                        .font(.system(size: 9))
                        .foregroundStyle(textDim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            if let opp = topOpponentName {
                glassCard {
                    VStack(spacing: 5) {
                        Text("⚔️")
                            .font(.system(size: 22))
                        Text("vs \(opp)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(textMain)
                            .lineLimit(1)
                        if let rec = topOpponentRecord {
                            Text(rec)
                                .font(.system(size: 9))
                                .foregroundStyle(textDim)
                        }
                        Text("최다 대결")
                            .font(.system(size: 9))
                            .foregroundStyle(textDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - 시즌 하이라이트 카드

    private func highlightCard(_ h: SeasonHighlight) -> some View {
        glassCard {
            HStack(spacing: 10) {
                Text(h.emoji)
                    .font(.system(size: 26))

                VStack(alignment: .leading, spacing: 3) {
                    Text("시즌 하이라이트")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(textDim)
                        .tracking(1)
                    Text(h.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(textMain)
                    Text(h.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(textSub)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
    }

    // MARK: - 달성 뱃지

    private var badgesSection: some View {
        VStack(spacing: 6) {
            Text("달성 뱃지")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(textDim)
                .tracking(1)
            Text(unlockedEmojis)
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - 바코드 + 워터마크

    private var barcodeSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 1.5) {
                ForEach(Array(barcodeWidths(seed: teamName).enumerated()), id: \.offset) { _, w in
                    Rectangle()
                        .fill(barcodeInk)
                        .frame(width: w, height: 36)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .clipped()

            Text(String(format: String(localized: "sports.stats.share.seasonWatermark", defaultValue: "FANFOLIO  SEASON %lld"),
                        locale: .autoupdatingCurrent,
                        Calendar.current.component(.year, from: Date())))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(textDim)
                .tracking(3)
        }
        .padding(.top, 4)
    }

    /// LCG 기반 결정론적 바코드 너비 생성 (시드: 팀 이름).
    private func barcodeWidths(seed: String, count: Int = 75) -> [CGFloat] {
        var widths: [CGFloat] = []
        var h = UInt(bitPattern: seed.hashValue)
        for _ in 0..<count {
            h = h &* 1664525 &+ 1013904223
            widths.append(CGFloat(h % 4 + 1))
        }
        return widths
    }

    // MARK: - 글래스 카드 빌더

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(cardBorder, lineWidth: 0.5)
            )
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
    let title: LocalizedStringKey
    let desc: LocalizedStringKey
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
