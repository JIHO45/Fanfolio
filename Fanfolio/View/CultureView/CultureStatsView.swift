//
//  CultureStatsView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI

struct CultureStatsView: View {
    let folder: CultureFanFolder
    
    @State private var showingSharePreviewSheet = false
    
    // MARK: - 기본 통계
    private var completedEvents: [CultureModel] {
        folder.events.filter { $0.eventStatus == .completed }
    }
    
    private var totalCompleted: Int { completedEvents.count }
    
    private var ratedEvents: [CultureModel] {
        completedEvents.filter { $0.rating > 0 }
    }
    
    private var averageRating: Double {
        guard !ratedEvents.isEmpty else { return 0 }
        return Double(ratedEvents.map(\.rating).reduce(0, +)) / Double(ratedEvents.count)
    }
    
    private var ratingCounts: [Int: Int] {
        var counts: [Int: Int] = [:]
        for star in 1...5 {
            counts[star] = ratedEvents.filter { $0.rating == star }.count
        }
        return counts
    }
    
    // MARK: - 문화팬 칭호
    private var cultureTitle: (emoji: String, title: String, subtitle: String) {
        switch totalCompleted {
        case 100...: return ("👑", "문화계의 왕", "100회 이상 관람, 진정한 문화 마스터!")
        case 50..<100: return ("🎭", "문화 마니아", "당신은 공연의 단골!")
        case 30..<50: return ("🌟", "열정적인 관객", "꾸준한 관람 기록이 멋져요!")
        case 15..<30: return ("🎵", "문화 애호가", "문화 생활의 재미를 알아가고 있어요!")
        case 5..<15: return ("🎬", "문화 입문자", "좋은 시작이에요! 더 많이 즐겨보세요!")
        default: return ("✨", "문화 새싹", "첫 걸음을 내딛었어요!")
        }
    }
    
    // MARK: - 아티스트/작품별 통계
    private var artistRecords: [ArtistRecord] {
        let eventsWithArtist = completedEvents.filter { $0.artist != nil && !($0.artist?.isEmpty ?? true) }
        let grouped = Dictionary(grouping: eventsWithArtist, by: { $0.artist! })
        return grouped.map { (artist, events) in
            let ratings = events.filter { $0.rating > 0 }.map(\.rating)
            let avg = ratings.isEmpty ? 0 : Double(ratings.reduce(0, +)) / Double(ratings.count)
            return ArtistRecord(
                name: artist,
                count: events.count,
                averageRating: avg
            )
        }
        .sorted { $0.count > $1.count }
    }
    
    // MARK: - 월별 데이터 (최근 12개월)
    private var monthlyData: [CultureMonthlyRecord] {
        let calendar = Calendar.current
        return (0..<12).reversed().compactMap { i -> CultureMonthlyRecord? in
            guard let date = calendar.date(byAdding: .month, value: -i, to: Date()) else { return nil }
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)
            let count = completedEvents.filter { event in
                guard let d = event.date else { return false }
                return calendar.component(.month, from: d) == month
                    && calendar.component(.year, from: d) == year
            }.count
            return CultureMonthlyRecord(month: month, count: count)
        }
    }
    
    // MARK: - 마일스톤
    private var milestones: [CultureMilestone] {
        let hasHighRating = completedEvents.contains { $0.rating == 5 }
        let distinctArtists = Set(completedEvents.compactMap { $0.artist }).count
        let hasPhotos = completedEvents.contains { $0.photosData != nil && !($0.photosData?.isEmpty ?? true) }
        let hasQR = completedEvents.contains { $0.qrCodeImageData != nil }
        let distinctLocations = Set(completedEvents.compactMap { $0.location }).count
        let repeatArtist = artistRecords.contains { $0.count >= 3 }
        
        return [
            CultureMilestone(id: "first", emoji: "🎫", title: "첫 관람", desc: "첫 기록 달성", isUnlocked: totalCompleted >= 1),
            CultureMilestone(id: "ten", emoji: "⭐️", title: "10회 관람", desc: "10회 기록 달성", isUnlocked: totalCompleted >= 10),
            CultureMilestone(id: "twentyfive", emoji: "🌟", title: "25회 관람", desc: "25회 기록 달성", isUnlocked: totalCompleted >= 25),
            CultureMilestone(id: "fifty", emoji: "💫", title: "50회 관람", desc: "50회 기록 달성", isUnlocked: totalCompleted >= 50),
            CultureMilestone(id: "hundred", emoji: "🏆", title: "100회 관람", desc: "100회 기록 달성", isUnlocked: totalCompleted >= 100),
            CultureMilestone(id: "perfect", emoji: "💯", title: "완벽한 공연", desc: "별점 5점 기록", isUnlocked: hasHighRating),
            CultureMilestone(id: "diverse", emoji: "🎨", title: "다양한 취향", desc: "5명 이상 아티스트 관람", isUnlocked: distinctArtists >= 5),
            CultureMilestone(id: "photographer", emoji: "📸", title: "포토그래퍼", desc: "사진과 함께 기록", isUnlocked: hasPhotos),
            CultureMilestone(id: "collector", emoji: "🎟️", title: "티켓 수집가", desc: "QR/티켓 사진 첨부", isUnlocked: hasQR),
            CultureMilestone(id: "explorer", emoji: "🗺️", title: "탐험가", desc: "5곳 이상 장소 방문", isUnlocked: distinctLocations >= 5),
            CultureMilestone(id: "superfan", emoji: "💜", title: "슈퍼팬", desc: "같은 아티스트 3회 이상", isUnlocked: repeatArtist),
            CultureMilestone(id: "critic", emoji: "📝", title: "평론가", desc: "10개 이상 별점 평가", isUnlocked: ratedEvents.count >= 10),
        ]
    }
    
    private var unlockedMilestones: [CultureMilestone] { milestones.filter { $0.isUnlocked } }
    
    // MARK: - Body
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if totalCompleted == 0 {
                    ContentUnavailableView(
                        "완료된 기록이 없습니다",
                        systemImage: "chart.bar",
                        description: Text("관람을 완료로 기록하면 통계가 나타납니다.")
                    )
                } else {
                    cultureFanCard
                    ratingDistributionCard
                    artistSection
                    heatmapSection
                    milestoneSection
                    cultureReportButton
                }
            }
            .padding()
        }
        .navigationTitle("관람 통계")
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $showingSharePreviewSheet) {
            SharePreviewView { style in
                await Task { generateReport(style: style) }.value
            }
        }
    }
}

// MARK: - 문화팬 칭호 카드
extension CultureStatsView {
    private var cultureFanCard: some View {
        VStack(spacing: 16) {
            Text(cultureTitle.emoji)
                .font(.system(size: 52))
            
            Text(cultureTitle.title)
                .font(.title2.bold())
            
            Text(cultureTitle.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // 평균 별점 원형 프로그레스
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: averageRating / 5.0)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: averageRating)
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(String(format: "%.1f", averageRating))
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                    }
                    Text("평균 별점")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)
            
            Text("\(totalCompleted)회 관람")
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.1))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

// MARK: - 별점 분포 카드
extension CultureStatsView {
    private var ratingDistributionCard: some View {
        VStack(spacing: 16) {
            HStack {
                Label("별점 분포", systemImage: "star.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(ratedEvents.count)개 평가")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ForEach((1...5).reversed(), id: \.self) { star in
                let count = ratingCounts[star] ?? 0
                let maxCount = ratingCounts.values.max() ?? 1
                
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Text("\(star)")
                            .font(.caption.bold())
                            .frame(width: 12)
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }
                    
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(starColor(for: star))
                            .frame(width: maxCount > 0 ? max(geo.size.width * CGFloat(count) / CGFloat(maxCount), count > 0 ? 8 : 0) : 0)
                    }
                    .frame(height: 16)
                    
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    private func starColor(for star: Int) -> Color {
        switch star {
        case 5: return .yellow
        case 4: return .orange
        case 3: return .blue
        case 2: return .gray
        default: return .red
        }
    }
}

// MARK: - 아티스트/작품별 통계
extension CultureStatsView {
    private var artistSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("아티스트별 관람", systemImage: "person.2.fill")
                    .font(.subheadline.bold())
                Spacer()
            }
            
            if artistRecords.isEmpty {
                Text("아티스트 정보가 있는 기록이 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ForEach(artistRecords) { record in
                    HStack {
                        Text(record.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Text("\(record.count)회")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if record.averageRating > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", record.averageRating))
                                        .font(.caption.bold())
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if record.id != artistRecords.last?.id {
                        Divider()
                    }
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
extension CultureStatsView {
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
                                        .foregroundStyle(.white)
                                }
                            }
                        
                        Text("\(data.month)월")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            HStack(spacing: 12) {
                Spacer()
                Text("적음")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    ForEach(0..<4) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.purple.opacity(0.1 + Double(i) * 0.25))
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
        return Color.purple.opacity(0.2 + intensity * 0.65)
    }
}

// MARK: - 마일스톤 뱃지
extension CultureStatsView {
    private var milestoneSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("관람 마일스톤", systemImage: "trophy.fill")
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
                                  ? Color.purple.opacity(0.08)
                                  : Color.secondary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                milestone.isUnlocked
                                    ? Color.purple.opacity(0.3)
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

// MARK: - 관람 리포트 공유
extension CultureStatsView {
    private var cultureReportButton: some View {
        Button {
            showingSharePreviewSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                Text("관람 리포트 공유하기")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.3, green: 0.1, blue: 0.4), Color(red: 0.15, green: 0.05, blue: 0.3)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    @MainActor
    private func generateReport(style: ShareStyle) -> UIImage? {
        let topArtist = artistRecords.first
        
        let content = CultureReportContent(
            folderName: folder.name,
            cultureType: folder.cultureType,
            averageRating: averageRating,
            totalEvents: totalCompleted,
            cultureEmoji: cultureTitle.emoji,
            cultureTitle: cultureTitle.title,
            topArtistName: topArtist?.name,
            topArtistCount: topArtist?.count,
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

// MARK: - 관람 리포트 이미지 뷰 (라이트/다크 지원)
private struct CultureReportContent: View {
    let folderName: String
    let cultureType: CultureType
    let averageRating: Double
    let totalEvents: Int
    let cultureEmoji: String
    let cultureTitle: String
    let topArtistName: String?
    let topArtistCount: Int?
    let unlockedEmojis: String
    let style: ShareStyle
    
    // 스타일별 색상
    private var bgGradient: LinearGradient {
        style == .dark
            ? LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.04, blue: 0.22),
                    Color(red: 0.2, green: 0.06, blue: 0.35),
                    Color(red: 0.1, green: 0.04, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.95, blue: 1.0),
                    Color(red: 0.98, green: 0.96, blue: 1.0),
                    Color(red: 0.96, green: 0.95, blue: 0.98)
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
    private var titleColor: Color {
        style == .dark ? Color.purple.opacity(0.8) : Color(red: 0.5, green: 0.2, blue: 0.7)
    }
    private var brandColor: Color {
        style == .dark ? .white.opacity(0.2) : Color(red: 0.8, green: 0.8, blue: 0.82)
    }
    private var starColor: Color { .yellow }
    private var ratingSubColor: Color {
        style == .dark ? .white.opacity(0.4) : Color(red: 0.7, green: 0.7, blue: 0.7)
    }
    
    var body: some View {
        VStack(spacing: 28) {
            // 헤더
            VStack(spacing: 8) {
                Text("나의 관람 리포트")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(textSub)
                    .tracking(2)
                
                HStack(spacing: 8) {
                    Image(systemName: cultureType.iconName)
                    Text(folderName)
                }
                .font(.title.bold())
                .foregroundStyle(textMain)
            }
            
            // 평균 별점
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: Double(star) <= averageRating.rounded(.down) ? "star.fill" : (Double(star) - 0.5 <= averageRating ? "star.leadinghalf.filled" : "star"))
                            .font(.title2)
                            .foregroundStyle(starColor)
                    }
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(String(format: "%.1f", averageRating))
                        .font(.system(size: 60, weight: .heavy, design: .rounded))
                        .foregroundStyle(textMain)
                    Text(" / 5")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(ratingSubColor)
                }
                
                Text("평균 별점")
                    .font(.subheadline)
                    .foregroundStyle(textSub)
            }
            
            // 칭호
            Text("\(cultureEmoji) \(cultureTitle)")
                .font(.title3.bold())
                .foregroundStyle(titleColor)
            
            // 구분선
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
                .padding(.horizontal, 40)
            
            // 관람 횟수
            VStack(spacing: 4) {
                Text("\(totalEvents)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(textMain)
                Text("회 관람")
                    .font(.subheadline)
                    .foregroundStyle(textSub)
            }
            
            // 최다 관람 아티스트
            if let artist = topArtistName, let count = topArtistCount {
                VStack(spacing: 6) {
                    Text("최다 관람")
                        .font(.caption)
                        .foregroundStyle(textDim)
                    Text(artist)
                        .font(.headline)
                        .foregroundStyle(textMain)
                    Text("\(count)회")
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
}

// MARK: - 데이터 모델
private struct ArtistRecord: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let averageRating: Double
}

private struct CultureMonthlyRecord: Identifiable {
    let id = UUID()
    let month: Int
    let count: Int
}

private struct CultureMilestone: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let desc: String
    let isUnlocked: Bool
}

// MARK: - Previews
#Preview {
    NavigationStack {
        CultureStatsView(folder: {
            let folder = CultureFanFolder(name: "BTS", cultureType: .concert)
            
            let data: [(String, String, Int, Int)] = [
                ("BTS 콘서트 서울", "BTS", 5, 0),
                ("BTS 팬미팅 2025", "BTS", 4, 30),
                ("BTS Yet To Come", "BTS", 5, 60),
                ("세븐틴 콘서트", "세븐틴", 4, 45),
                ("세븐틴 팬미팅", "세븐틴", 3, 90),
                ("아이유 콘서트", "아이유", 5, 15),
                ("에스파 콘서트", "에스파", 4, 75),
                ("뉴진스 팬미팅", "뉴진스", 5, 20),
                ("르세라핌 콘서트", "르세라핌", 4, 50),
                ("BTS 월드투어", "BTS", 5, 120),
                ("위키드 뮤지컬", "옥주현", 5, 10),
                ("오페라의 유령", "캐스팅 미정", 4, 40),
            ]
            
            for (i, d) in data.enumerated() {
                let e = CultureModel(
                    title: d.0,
                    artist: d.1,
                    date: Calendar.current.date(byAdding: .day, value: -d.3, to: Date()),
                    location: "잠실 올림픽 주경기장",
                    rating: d.2,
                    eventStatus: .completed,
                    orderIndex: i
                )
                e.folder = folder
                folder.events.append(e)
            }
            
            return folder
        }())
    }
}
