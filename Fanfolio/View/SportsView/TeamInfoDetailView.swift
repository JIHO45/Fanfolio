//
//  TeamInfoDetailView.swift
//  Fanfolio
//
//  팀 정보 상세 페이지 - 팀 스탯, 최애 선수, 전체 선수단을 표시합니다.

import SwiftUI

struct TeamInfoDetailView: View {
    let folder: SportsFanFolder

    @State private var squadPlayers: [PlayerInfo] = []
    @State private var isLoadingSquad = false
    @State private var showAllPlayers = false
    @State private var favorites = FavoritePlayersManager.shared

    // MARK: - 통계 계산

    private var completedMatches: [SportsModel] {
        folder.matches.filter { $0.matchStatus == .completed }
    }
    private var wins: Int   { completedMatches.filter { $0.matchResult == .win   }.count }
    private var losses: Int { completedMatches.filter { $0.matchResult == .loss  }.count }
    private var draws: Int  { completedMatches.filter { $0.matchResult == .draw  }.count }
    private var totalCompleted: Int { completedMatches.count }

    private var winRate: Double {
        guard totalCompleted > 0 else { return 0 }
        return Double(wins) / Double(totalCompleted) * 100
    }

    private var currentStreak: (count: Int, type: MatchResult)? {
        let sorted = completedMatches.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        guard let first = sorted.first, first.matchResult != .draw else { return nil }
        let streakType = first.matchResult
        var count = 0
        for m in sorted {
            if m.matchResult == streakType { count += 1 } else { break }
        }
        return count >= 2 ? (count, streakType) : nil
    }

    private var favPlayers: [PlayerInfo] {
        let ids = favorites.favoriteIDs
        return squadPlayers.filter { ids.contains("\($0.id)") }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // 팀 스탯
                if totalCompleted > 0 {
                    teamStatsCard
                }

                // 최애 선수
                if !favPlayers.isEmpty {
                    favoritesCard
                }

                // 전체 선수단
                squadCard
            }
            .padding()
        }
        .navigationTitle("팀 정보")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await loadSquadIfNeeded()
        }
    }

    // MARK: - 선수단 로드

    private func loadSquadIfNeeded() async {
        guard squadPlayers.isEmpty, !isLoadingSquad else { return }
        isLoadingSquad = true
        defer { isLoadingSquad = false }
        do {
            squadPlayers = try await TheSportsDBService.shared.fetchSquadByTeamName(folder.name)
        } catch {
            // 조용히 실패
        }
    }
}

// MARK: - 팀 스탯 카드

extension TeamInfoDetailView {
    private var teamStatsCard: some View {
        let homeMatches = completedMatches.filter { $0.isHomeGame }
        let awayMatches = completedMatches.filter { !$0.isHomeGame }
        let homeWins    = homeMatches.filter { $0.matchResult == .win  }.count
        let homeLosses  = homeMatches.filter { $0.matchResult == .loss }.count
        let awayWins    = awayMatches.filter { $0.matchResult == .win  }.count
        let awayLosses  = awayMatches.filter { $0.matchResult == .loss }.count
        let rateColor: Color = winRate >= 50 ? .green : (winRate >= 30 ? .orange : .red)

        return VStack(spacing: 16) {
            HStack {
                Label("팀 스탯", systemImage: "chart.bar.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(totalCompleted)경기")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                // 원형 승률
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
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                        Text("승률")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 84, height: 84)

                VStack(spacing: 12) {
                    HStack(spacing: 0) {
                        statItem(value: "\(wins)",   label: "승", color: .green)
                        statItem(value: "\(losses)", label: "패", color: .red)
                        statItem(value: "\(draws)",  label: "무", color: .orange)
                    }
                    GeometryReader { geo in
                        let total = CGFloat(max(totalCompleted, 1))
                        HStack(spacing: 2) {
                            if wins > 0 {
                                RoundedRectangle(cornerRadius: 3).fill(MatchResult.win.color)
                                    .frame(width: max(geo.size.width * CGFloat(wins) / total, 6))
                            }
                            if losses > 0 {
                                RoundedRectangle(cornerRadius: 3).fill(MatchResult.loss.color)
                                    .frame(width: max(geo.size.width * CGFloat(losses) / total, 6))
                            }
                            if draws > 0 {
                                RoundedRectangle(cornerRadius: 3).fill(MatchResult.draw.color)
                            }
                        }
                    }
                    .frame(height: 6)
                }
            }

            Divider()

            // 홈 / 원정 / 연승연패
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("홈")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Text("\(homeWins)승 \(homeLosses)패")
                        .font(.subheadline.weight(.semibold))
                    Text("\(homeMatches.count)경기")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 44).padding(.horizontal, 8)

                VStack(spacing: 4) {
                    Text("원정")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Text("\(awayWins)승 \(awayLosses)패")
                        .font(.subheadline.weight(.semibold))
                    Text("\(awayMatches.count)경기")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                if let streak = currentStreak {
                    Divider().frame(height: 44).padding(.horizontal, 8)
                    VStack(spacing: 4) {
                        Text(streak.type == .win ? "연승" : "연패")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        Text("\(streak.count)연속")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(streak.type.color)
                        Text(streak.type == .win ? "🔥" : "💧")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 최애 선수 카드

extension TeamInfoDetailView {
    private var favoritesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("최애 선수", systemImage: "heart.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(favPlayers.count)명")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.red)
                    .clipShape(Capsule())
            }

            ForEach(favPlayers) { player in
                NavigationLink(destination: PlayerDetailView(
                    player: player, sportType: folder.sportType, folder: folder
                )) {
                    favPlayerRow(player: player)
                }
                .buttonStyle(.plain)

                if player.id != favPlayers.last?.id { Divider() }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [Color.red.opacity(0.05), Color(uiColor: .secondarySystemBackground)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
        )
    }

    private func favPlayerRow(player: PlayerInfo) -> some View {
        let teamColor = Color.from(hex: folder.teamColor) ?? .blue
        let highlights = player.stats?.highlights(for: folder.sportType) ?? []

        return HStack(spacing: 12) {
            PlayerImageView(
                cutoutURL: player.cutoutImageURL,
                photoURL: player.photoURL,
                fallbackTeamLogoURL: folder.teamLogoUrl,
                fallbackGradient: folder.gradientColors,
                size: 56
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.red)
                    Text(player.name).font(.subheadline.weight(.bold)).lineLimit(1)
                    if let num = player.number {
                        Text("#\(num)")
                            .font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(teamColor.opacity(0.8)))
                    }
                }
                if let pos = player.position {
                    Text(pos).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !highlights.isEmpty {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(highlights.prefix(2), id: \.0) { label, value in
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(value)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(teamColor).monospacedDigit()
                            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 전체 선수단 카드

extension TeamInfoDetailView {
    @ViewBuilder
    private var squadCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("팀 선수단", systemImage: "person.3.fill")
                    .font(.subheadline.bold())
                Spacer()
                if isLoadingSquad {
                    ProgressView().scaleEffect(0.7)
                } else if !squadPlayers.isEmpty {
                    Text("\(squadPlayers.count)명")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if isLoadingSquad {
                ForEach(0..<3, id: \.self) { _ in squadRowSkeleton }
            } else if squadPlayers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.slash").font(.title2).foregroundStyle(.secondary)
                    Text("선수단 정보를 찾을 수 없습니다")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                let favIDs    = favorites.favoriteIDs
                let rest      = squadPlayers.filter { !favIDs.contains("\($0.id)") }
                let displayed = showAllPlayers ? rest : Array(rest.prefix(5))

                ForEach(displayed) { player in
                    NavigationLink(destination: PlayerDetailView(
                        player: player, sportType: folder.sportType, folder: folder
                    )) {
                        squadPlayerRow(player: player)
                    }
                    .buttonStyle(.plain)
                    if player.id != displayed.last?.id { Divider() }
                }

                if rest.count > 5 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllPlayers.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showAllPlayers ? "접기" : "전체 \(rest.count)명 보기")
                                .font(.caption.bold())
                            Image(systemName: showAllPlayers ? "chevron.up" : "chevron.down")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity).padding(.top, 4)
                    }
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func squadPlayerRow(player: PlayerInfo) -> some View {
        let isFav      = favorites.isFavorite("\(player.id)")
        let teamColor  = Color.from(hex: folder.teamColor) ?? .blue

        return HStack(spacing: 12) {
            PlayerImageView(
                cutoutURL: player.cutoutImageURL,
                photoURL: player.photoURL,
                fallbackTeamLogoURL: folder.teamLogoUrl,
                fallbackGradient: folder.gradientColors
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(player.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let num = player.number {
                        Text("#\(num)")
                            .font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(teamColor.opacity(0.8)))
                    }
                    if isFav {
                        Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.red)
                    }
                }
                if let pos = player.position {
                    Text(pos).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let stats = player.stats {
                let highlights = stats.highlights(for: folder.sportType)
                if !highlights.isEmpty {
                    VStack(alignment: .trailing, spacing: 3) {
                        ForEach(highlights.prefix(2), id: \.0) { label, value in
                            HStack(spacing: 4) {
                                Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(value)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }

            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var squadRowSkeleton: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1)).frame(width: 44, height: 44).shimmer()
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1)).frame(width: 120, height: 12).shimmer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1)).frame(width: 60, height: 10).shimmer()
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TeamInfoDetailView(folder: {
            let f = SportsFanFolder(name: "San Francisco 49ers", sportType: .americanFootball)
            f.teamLogoUrl = "https://a.espncdn.com/i/teamlogos/nfl/500/sf.png"
            f.teamColor = "AA0000"
            return f
        }())
    }
}
