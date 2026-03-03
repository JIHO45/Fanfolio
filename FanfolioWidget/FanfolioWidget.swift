//
//  FanfolioWidget.swift
//  FanfolioWidget
//
//  Created by 박지호 on 2/15/26.
//

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Timeline Entry
struct FanfolioEntry: TimelineEntry {
    let date: Date
    let teamName: String
    let sportIcon: String
    let totalGames: Int
    let wins: Int
    let losses: Int
    let draws: Int
    let winRate: Int
    let nextMatchTitle: String?
    let nextMatchDate: Date?
    let currentStreak: Int
    let isWinStreak: Bool
    
    static let placeholder = FanfolioEntry(
        date: .now,
        teamName: "LG 트윈스",
        sportIcon: "figure.baseball",
        totalGames: 10,
        wins: 7,
        losses: 2,
        draws: 1,
        winRate: 70,
        nextMatchTitle: "vs 두산 베어스",
        nextMatchDate: Calendar.current.date(byAdding: .day, value: 2, to: .now),
        currentStreak: 3,
        isWinStreak: true
    )
    
    static let empty = FanfolioEntry(
        date: .now,
        teamName: "팀 없음",
        sportIcon: "sportscourt",
        totalGames: 0,
        wins: 0,
        losses: 0,
        draws: 0,
        winRate: 0,
        nextMatchTitle: nil,
        nextMatchDate: nil,
        currentStreak: 0,
        isWinStreak: true
    )
}

// MARK: - Timeline Provider
struct FanfolioTimelineProvider: AppIntentTimelineProvider {
    
    /// 공유 ModelContainer (App Group 경유)
    @MainActor
    private var sharedContainer: ModelContainer? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.fanfolio.shared")?
            .appending(path: "Fanfolio.sqlite") else { return nil }
        
        let config = ModelConfiguration(url: url)
        return try? ModelContainer(
            for: SportsFanFolder.self, SportsModel.self,
            configurations: config
        )
    }
    
    func placeholder(in context: Context) -> FanfolioEntry {
        .placeholder
    }
    
    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> FanfolioEntry {
        await loadEntry() ?? .placeholder
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<FanfolioEntry> {
        let entry = await loadEntry() ?? .empty
        // 1시간마다 갱신
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
    
    @MainActor
    private func loadEntry() -> FanfolioEntry? {
        guard let container = sharedContainer else { return nil }
        
        let context = container.mainContext
        let descriptor = FetchDescriptor<SportsFanFolder>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        
        guard let folders = try? context.fetch(descriptor),
              let folder = folders.first else { return nil }
        
        let completed = folder.matches.filter { $0.matchStatus == .completed }
        let wins = completed.filter { $0.matchResult == .win }.count
        let losses = completed.filter { $0.matchResult == .loss }.count
        let draws = completed.filter { $0.matchResult == .draw }.count
        let total = completed.count
        let winRate = total > 0 ? Int(Double(wins) / Double(total) * 100) : 0
        
        // 다음 경기 (예정/진행중 중 가장 빠른 날짜)
        let upcoming = folder.matches
            .filter { $0.matchStatus != .completed }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            .first
        
        // 현재 연승/연패 계산
        let sorted = completed.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        var streak = 0
        var isWin = true
        if let first = sorted.first, first.matchResult != .draw {
            isWin = first.matchResult == .win
            for m in sorted {
                if m.matchResult == first.matchResult { streak += 1 } else { break }
            }
        }
        
        return FanfolioEntry(
            date: .now,
            teamName: folder.displayName,
            sportIcon: folder.sportType.iconName,
            totalGames: total,
            wins: wins,
            losses: losses,
            draws: draws,
            winRate: winRate,
            nextMatchTitle: upcoming.map { "vs \($0.opponentTeam)" },
            nextMatchDate: upcoming?.date,
            currentStreak: streak,
            isWinStreak: isWin
        )
    }
}

// MARK: - 위젯 뷰 (Small)
struct FanfolioWidgetSmallView: View {
    let entry: FanfolioEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 팀명 + 종목
            HStack(spacing: 4) {
                Image(systemName: entry.sportIcon)
                    .font(.caption2)
                Text(entry.teamName)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            
            Spacer()
            
            // 승률
            Text("\(entry.winRate)%")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(entry.winRate >= 50 ? .green : .orange)
            
            // 전적
            Text("\(entry.wins)승 \(entry.losses)패 \(entry.draws)무")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            
            // 연승/연패
            if entry.currentStreak >= 2 {
                HStack(spacing: 2) {
                    Text(entry.isWinStreak ? "🔥" : "💧")
                        .font(.caption2)
                    Text("\(entry.currentStreak)\(entry.isWinStreak ? "연승" : "연패")")
                        .font(.caption2.bold())
                        .foregroundStyle(entry.isWinStreak ? .green : .red)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - 위젯 뷰 (Medium)
struct FanfolioWidgetMediumView: View {
    let entry: FanfolioEntry
    
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d (E)"
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt
    }()
    
    var body: some View {
        HStack(spacing: 16) {
            // 좌측: 승률 + 전적
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: entry.sportIcon)
                        .font(.caption2)
                    Text(entry.teamName)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(entry.winRate)%")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(entry.winRate >= 50 ? .green : .orange)
                
                Text("\(entry.wins)승 \(entry.losses)패 \(entry.draws)무")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // 우측: 다음 경기 + 연승
            VStack(alignment: .leading, spacing: 8) {
                if let title = entry.nextMatchTitle {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("다음 경기")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        if let date = entry.nextMatchDate {
                            Text(Self.dateFormatter.string(from: date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("예정된 경기 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if entry.currentStreak >= 2 {
                    HStack(spacing: 4) {
                        Text(entry.isWinStreak ? "🔥" : "💧")
                        Text("\(entry.currentStreak)\(entry.isWinStreak ? "연승" : "연패")")
                            .font(.caption.bold())
                            .foregroundStyle(entry.isWinStreak ? .green : .red)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - 위젯 EntryView (widgetFamily 분기)
struct FanfolioWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: FanfolioEntry
    
    var body: some View {
        switch family {
        case .systemMedium:
            FanfolioWidgetMediumView(entry: entry)
        default:
            FanfolioWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - 위젯 정의
struct FanfolioWidget: Widget {
    let kind = "FanfolioWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigurationAppIntent.self,
            provider: FanfolioTimelineProvider()
        ) { entry in
            FanfolioWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fanfolio")
        .description("내 팀의 직관 승률과 다음 경기를 확인하세요.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview
#Preview("Small", as: .systemSmall) {
    FanfolioWidget()
} timeline: {
    FanfolioEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    FanfolioWidget()
} timeline: {
    FanfolioEntry.placeholder
}
