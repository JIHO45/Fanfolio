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
    @State private var favorites = FavoritePlayersManager.shared

    // MARK: - 포지션 필터 상태
    @State private var selectedGroup: PositionGroup? = nil
    @State private var selectedNFLPhase: NFLPhase? = nil

    // MARK: - 통계 (DTO 매핑 후 백그라운드 계산 결과)
    @State private var teamStatsResult: FanStatsResult?

    private var favPlayers: [PlayerInfo] {
        let ids = favorites.favoriteIDs(inFolder: folder.folderID.uuidString)
        let fav = squadPlayers.filter { ids.contains("\($0.id)") }
        // 포지션 순서로 정렬
        return fav.sorted {
            folder.sportType.positionGroup(for: $0.position).sortOrder <
            folder.sportType.positionGroup(for: $1.position).sortOrder
        }
    }

    private var nonFavoriteSquadPlayers: [PlayerInfo] {
        let favoriteIDs = favorites.favoriteIDs(inFolder: folder.folderID.uuidString)
        return squadPlayers.filter { !favoriteIDs.contains("\($0.id)") }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let r = teamStatsResult {
                    teamStatsCard(r)
                }
                if !favPlayers.isEmpty {
                    favoritesCard
                }
                squadCard
            }
            .padding()
        }
        .navigationTitle("팀 정보")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: folder.fanfolioFolderTaskToken) {
            squadPlayers = []
            await loadSquadIfNeeded()
        }
        .task(id: folder.fanfolioFolderTaskToken) {
            let dto = folder.matches.map { MatchStatDTO(from: $0) }
            let result = await Task.detached(priority: .userInitiated) {
                FanStatsCalculator(data: dto).compute()
            }.value
            teamStatsResult = result
        }
    }

    // MARK: - 선수단 로드

    private func loadSquadIfNeeded() async {
        guard squadPlayers.isEmpty, !isLoadingSquad else { return }
        isLoadingSquad = true
        defer { isLoadingSquad = false }

        // ESPN ID가 있는 US 스포츠는 ESPN roster 우선 사용 (무제한 무료)
        let espnTeam = ESPNTeamsLoader.team(name: folder.name, leagueCode: folder.leagueCode)
        squadPlayers = await PlayerMatchingService.shared.fetchSquadWithCutouts(
            sportType: folder.sportType,
            teamName: folder.name,
            espnTeamID: espnTeam?.id,
            leagueCode: folder.leagueCode,
            apiSportsTeamID: folder.apiSportsTeamID
        )
    }
}

// MARK: - 팀 스탯 카드

extension TeamInfoDetailView {
    private func teamStatsCard(_ r: FanStatsResult) -> some View {
        let rateColor: Color = r.winRate >= 50 ? .green : (r.winRate >= 30 ? .orange : .red)
        return VStack(spacing: 16) {
            HStack {
                Label("팀 스탯", systemImage: "chart.bar.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(r.totalCompleted)경기")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
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
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                        Text("승률")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 84, height: 84)

                VStack(spacing: 12) {
                    HStack(spacing: 0) {
                        statItem(value: "\(r.wins)",   label: "승", color: .green)
                        statItem(value: "\(r.losses)", label: "패", color: .red)
                        statItem(value: "\(r.draws)",  label: "무", color: .orange)
                    }
                    GeometryReader { geo in
                        let total = CGFloat(max(r.totalCompleted, 1))
                        HStack(spacing: 2) {
                            if r.wins > 0 {
                                RoundedRectangle(cornerRadius: 3).fill(MatchResult.win.color)
                                    .frame(width: max(geo.size.width * CGFloat(r.wins) / total, 6))
                            }
                            if r.losses > 0 {
                                RoundedRectangle(cornerRadius: 3).fill(MatchResult.loss.color)
                                    .frame(width: max(geo.size.width * CGFloat(r.losses) / total, 6))
                            }
                            if r.draws > 0 {
                                RoundedRectangle(cornerRadius: 3).fill(MatchResult.draw.color)
                            }
                        }
                    }
                    .frame(height: 6)
                }
            }

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("홈")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Text("\(r.homeWins)승 \(r.homeLosses)패")
                        .font(.subheadline.weight(.semibold))
                    Text("\(r.homeWins + r.homeLosses + r.homeDraws)경기")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 44).padding(.horizontal, 8)

                VStack(spacing: 4) {
                    Text("원정")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Text("\(r.awayWins)승 \(r.awayLosses)패")
                        .font(.subheadline.weight(.semibold))
                    Text("\(r.awayWins + r.awayLosses + r.awayDraws)경기")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                if let streak = r.currentStreak {
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

    private func statItem(value: String, label: LocalizedStringKey, color: Color) -> some View {
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
                    player: player,
                    folder: folder
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

        return HStack(spacing: 12) {
            PlayerImageView(
                imageURL: player.imageURL,
                fallbackTeamLogoURL: folder.teamLogoUrl,
                fallbackGradient: folder.gradientColors,
                size: 56,
                playerName: player.name,
                jerseyNumber: player.number,
                sportType: folder.sportType
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

            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 전체 선수단 카드

extension TeamInfoDetailView {
    @ViewBuilder
    private var squadCard: some View {
        if isLoadingSquad {
            VStack(alignment: .leading, spacing: 14) {
                Label("팀 선수단", systemImage: "person.3.fill")
                    .font(.subheadline.bold())

                ForEach(0..<3, id: \.self) { _ in
                    squadRowSkeleton
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(uiColor: .secondarySystemBackground)))
        } else if squadPlayers.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Label("팀 선수단", systemImage: "person.3.fill")
                    .font(.subheadline.bold())

                VStack(spacing: 8) {
                    Image(systemName: "person.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("선수단 정보를 찾을 수 없습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(uiColor: .secondarySystemBackground)))
        } else {
            GroupedPlayerListCard(
                title: "팀 선수단",
                players: nonFavoriteSquadPlayers,
                sportType: folder.sportType,
                teamColorHex: folder.teamColor,
                fallbackTeamLogoURL: folder.teamLogoUrl,
                fallbackGradient: folder.gradientColors,
                favoriteFolderKey: folder.folderID.uuidString,
                selectedGroup: $selectedGroup,
                selectedNFLPhase: $selectedNFLPhase
            ) { player in
                PlayerDetailView(
                    player: player,
                    folder: folder
                )
            }
        }
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
