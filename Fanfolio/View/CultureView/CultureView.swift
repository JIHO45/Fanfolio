//
//  CultureView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import SwiftData

struct CultureView: View {
    let folder: CultureFanFolder
    
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddEventSheet = false
    @State private var eventToDelete: CultureModel?
    @State private var showingDeleteEventAlert = false
    
    /// 예정 이벤트 (가까운 날짜가 위에)
    private var upcomingEvents: [CultureModel] {
        folder.events
            .filter { $0.eventStatus == .upcoming }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    
    /// 완료된 이벤트 (최근이 위에)
    private var completedEvents: [CultureModel] {
        folder.events
            .filter { $0.eventStatus == .completed }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    
    // MARK: - 통계
    private var totalCompleted: Int { completedEvents.count }
    
    private var averageRating: Double {
        let rated = completedEvents.filter { $0.rating > 0 }
        guard !rated.isEmpty else { return 0 }
        return Double(rated.map(\.rating).reduce(0, +)) / Double(rated.count)
    }
    
    /// 가장 많이 기록된 작품/아티스트
    private var favoriteTitle: String? {
        let titles = completedEvents.compactMap { $0.artist }.filter { !$0.isEmpty }
        guard !titles.isEmpty else { return nil }
        let grouped = Dictionary(grouping: titles, by: { $0 })
        return grouped.max(by: { $0.value.count < $1.value.count })?.key
    }
    
    var body: some View {
        Group {
            if folder.events.isEmpty {
                ContentUnavailableView(
                    "기록이 없습니다",
                    systemImage: folder.cultureType.iconName,
                    description: Text("+ 버튼을 눌러 첫 관람을 기록해보세요!")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // 통계 배너 (탭하면 상세 통계)
                        if totalCompleted > 0 {
                            NavigationLink(destination: CultureStatsView(folder: folder)) {
                                statsHeader
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // 예정 이벤트 (상단)
                        if !upcomingEvents.isEmpty {
                            sectionHeader(
                                title: "예정",
                                iconName: "clock",
                                count: upcomingEvents.count
                            )
                            
                            ForEach(upcomingEvents) { event in
                                eventRow(event: event)
                            }
                        }
                        
                        // 완료된 이벤트
                        if !completedEvents.isEmpty {
                            sectionHeader(
                                title: "완료",
                                iconName: "checkmark.circle",
                                count: completedEvents.count
                            )
                            
                            ForEach(completedEvents) { event in
                                eventRow(event: event)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddEventSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddEventSheet) {
            AddCultureView(
                folder: folder,
                nextOrderIndex: folder.events.count
            )
        }
    }
    
    // MARK: - 통계 배너
    private var statsHeader: some View {
        VStack(spacing: 14) {
            // 상단: 칭호 + 자세히 보기
            HStack {
                HStack(spacing: 6) {
                    Text(cultureTitle.emoji)
                    Text(cultureTitle.title)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("자세히 보기")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            // 평균 별점 + 관람 수
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("\(averageRating, format: .number.precision(.fractionLength(1)))")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                }
                
                Text("평균")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(totalCompleted)회 관람")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            
            // 별점 분포 바
            GeometryReader { geometry in
                let total = CGFloat(max(totalCompleted, 1))
                let high = CGFloat(completedEvents.filter { $0.rating >= 4 }.count)
                let mid = CGFloat(completedEvents.filter { $0.rating == 3 }.count)
                let low = CGFloat(completedEvents.filter { $0.rating > 0 && $0.rating <= 2 }.count)
                
                HStack(spacing: 2) {
                    if high > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.yellow)
                            .frame(width: max(geometry.size.width * high / total, 8))
                    }
                    if mid > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange)
                            .frame(width: max(geometry.size.width * mid / total, 8))
                    }
                    if low > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.6))
                    }
                }
            }
            .frame(height: 8)
            
            // 하단
            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    ratingLabel(emoji: "5", text: "최고", count: completedEvents.filter { $0.rating == 5 }.count, color: .yellow)
                    ratingLabel(emoji: "4+", text: "좋음", count: completedEvents.filter { $0.rating == 4 }.count, color: .orange)
                }
                
                Spacer()
                
                if let fav = favoriteTitle {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.pink)
                        Text(fav)
                            .font(.caption.bold())
                            .foregroundStyle(.pink)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.pink.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    // MARK: - 문화팬 칭호
    private var cultureTitle: (emoji: String, title: LocalizedStringKey) {
        switch totalCompleted {
        case 50...: return ("👑", "문화계의 왕")
        case 30..<50: return ("🎭", "문화 마니아")
        case 15..<30: return ("🌟", "열정적인 관객")
        case 5..<15: return ("🎵", "문화 애호가")
        default: return ("🎬", "문화 입문자")
        }
    }
    
    private func ratingLabel(emoji: String, text: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 8))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
    
    // MARK: - 섹션 헤더
    private func sectionHeader(title: LocalizedStringKey, iconName: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: iconName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            Text("\(count)")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
            
            Spacer()
        }
        .padding(.top, 8)
    }
    
    // MARK: - 이벤트 행 (네비게이션 + 삭제)
    private func eventRow(event: CultureModel) -> some View {
        NavigationLink(destination: CultureDetailView(event: event)) {
            CultureEventCard(event: event)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                eventToDelete = event
                showingDeleteEventAlert = true
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .alert("기록 삭제", isPresented: $showingDeleteEventAlert) {
            Button("취소", role: .cancel) {
                eventToDelete = nil
            }
            Button("삭제", role: .destructive) {
                if let event = eventToDelete {
                    ArchivePhotoStore.delete(paths: event.photoPaths ?? [])
                    withAnimation {
                        modelContext.delete(event)
                    }
                    eventToDelete = nil
                }
            }
        } message: {
            if let event = eventToDelete {
                Text("'\(event.title)' 기록을 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.")
            }
        }
    }
}

// MARK: - 이벤트 카드
private struct CultureEventCard: View {
    let event: CultureModel
    
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.autoupdatingCurrent
        fmt.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return fmt
    }()
    
    private var cultureType: CultureType {
        event.folder?.cultureType ?? .other
    }
    
    private var folderName: String {
        event.folder?.name ?? ""
    }
    
    private var isUpcoming: Bool {
        event.eventStatus == .upcoming
    }
    
    /// D-day 계산
    private var dDayText: String? {
        guard event.eventStatus == .upcoming,
              let date = event.date else { return nil }
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        if days > 0 { return "D-\(days)" }
        if days == 0 { return "D-Day" }
        return nil
    }
    
    var body: some View {
        if isUpcoming {
            upcomingCard
        } else {
            completedCard
        }
    }
    
    // MARK: - 예정 카드
    private var upcomingCard: some View {
        VStack(spacing: 12) {
            // 상단: D-day + 카테고리 + 상태 배지
            HStack {
                if let dDay = dDayText {
                    Text(dDay)
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }
                
                Label(cultureType.displayName, systemImage: cultureType.iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(event.eventStatus.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
            }
            
            // 제목 + 아티스트
            VStack(spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                if let artist = event.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            
            // 날짜 + 장소
            HStack {
                if let date = event.date {
                    Label(Self.dateFormatter.string(from: date), systemImage: "calendar")
                }
                Spacer()
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.08),
                            Color(uiColor: .secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    Color.blue.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 5])
                )
        )
    }
    
    // MARK: - 완료 카드
    private var completedCard: some View {
        VStack(spacing: 0) {
            // 상단: 카테고리 + 별점
            HStack {
                Label(cultureType.displayName, systemImage: cultureType.iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if event.rating > 0 {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= event.rating ? "star.fill" : "star")
                                .font(.system(size: 10))
                                .foregroundStyle(star <= event.rating ? .yellow : .secondary.opacity(0.3))
                        }
                    }
                }
            }
            .padding(.bottom, 12)
            
            // 제목 + 아티스트
            VStack(spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                if let artist = event.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
            
            // 하단: 날짜 + 장소
            Divider()
                .padding(.bottom, 10)
            
            HStack {
                if let date = event.date {
                    Label(Self.dateFormatter.string(from: date), systemImage: "calendar")
                }
                Spacer()
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                bottomLeadingRadius: 16
            )
            .fill(ratingColor)
            .frame(width: 4)
        }
    }
    
    private var ratingColor: Color {
        switch event.rating {
        case 5: return .yellow
        case 4: return .orange
        case 3: return .blue
        case 2: return .gray
        default: return .secondary
        }
    }
}

#Preview {
    NavigationStack {
        CultureView(folder: {
            let folder = CultureFanFolder(name: "BTS", cultureType: .concert)
            
            let upcoming = CultureModel(
                title: "BTS 월드투어 서울",
                artist: "BTS",
                date: Calendar.current.date(byAdding: .day, value: 10, to: Date()),
                location: "잠실 올림픽 주경기장",
                eventStatus: .upcoming,
                orderIndex: 0
            )
            upcoming.folder = folder
            
            let events: [(String, String, Int, Int)] = [
                ("BTS 콘서트 부산", "BTS", 5, 1),
                ("BTS 팬미팅", "BTS", 4, 2),
                ("BTS Yet To Come in 부산", "BTS", 5, 3),
            ]
            
            for (title, artist, rating, idx) in events {
                let e = CultureModel(
                    title: title,
                    artist: artist,
                    date: Calendar.current.date(byAdding: .day, value: -idx * 30, to: Date()),
                    location: "잠실 올림픽 주경기장",
                    rating: rating,
                    eventStatus: .completed,
                    orderIndex: idx
                )
                e.folder = folder
                folder.events.append(e)
            }
            
            folder.events.append(upcoming)
            return folder
        }())
    }
    .modelContainer(SportsPreviewSampleData.container)
}
