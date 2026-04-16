//
//  TeamInfoDetailView.swift
//  Fanfolio
//
//  팀 정보 상세 페이지 - 팀 스탯, 최애 선수, 전체 선수단을 표시합니다.

import SwiftUI
import SwiftData

struct TeamInfoDetailView: View {
    let folder: SportsFanFolder

    @Environment(\.colorScheme) private var colorScheme

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

    /// ESPN 순위 API 지원 리그 또는 KBO (Firestore 집계)
    private var showsLeagueStandingsLink: Bool {
        guard folder.sportType != .other,
              let code = folder.leagueCode,
              !code.isEmpty
        else { return false }
        return code == "KBO" || ESPNPlayerService.shared.supportsLiveScoreboard(code)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let r = teamStatsResult {
                    teamStatsCard(r)
                }
                if showsLeagueStandingsLink {
                    NavigationLink(destination: LeagueStandingsView(folder: folder)) {
                        leagueStandingsLinkRow
                    }
                    .buttonStyle(.plain)
                }
                if !favPlayers.isEmpty {
                    favoritesCard
                }
                squadCard
            }
            .padding()
        }
        .navigationTitle(String(localized: "teamInfo.navTitle", defaultValue: "팀 정보"))
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: "\(folder.persistentModelID)\u{1f}\(folder.leagueCode ?? "")\u{1f}\(folder.name)\u{1f}\(folder.apiSportsTeamID ?? 0)") {
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

// MARK: - 리그 순위

extension TeamInfoDetailView {
    private var leagueStandingsLinkRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.number")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "standings.title", defaultValue: "리그 순위"))
                    .font(.subheadline.bold())
                Text(String(localized: "standings.subtitle", defaultValue: "현재 시즌 순위표"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
        .groupedCardOutline(cornerRadius: 20)
    }
}

// MARK: - 팀 스탯 카드

extension TeamInfoDetailView {
    private func teamStatsCard(_ r: FanStatsResult) -> some View {
        let rateColor: Color = WinRateTierPalette.accentColor(
            forPercent: r.winRate,
            hasCompletedGames: r.totalCompleted > 0
        )
        return VStack(spacing: 16) {
            HStack {
                Label(String(localized: "teamInfo.header.stats", defaultValue: "팀 스탯"), systemImage: "chart.bar.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: String(localized: "teamInfo.gamesShort", defaultValue: "%lld경기"), locale: .autoupdatingCurrent, Int64(r.totalCompleted)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(GroupedCardChrome.winRateRingTrackColorWide(colorScheme: colorScheme), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: r.winRate / 100)
                        .stroke(rateColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.8), value: r.winRate)
                    VStack(spacing: 2) {
                        Text(verbatim: "\(Int(r.winRate))%")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                        Text(String(localized: "teamInfo.winRate", defaultValue: "승률"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 84, height: 84)

                VStack(spacing: 12) {
                    HStack(spacing: 0) {
                        statItem(value: "\(r.wins)",   label: String(localized: "sports.stats.label.win", defaultValue: "승"), color: .green)
                        statItem(value: "\(r.losses)", label: String(localized: "sports.stats.label.loss", defaultValue: "패"), color: .red)
                        statItem(value: "\(r.draws)",  label: String(localized: "sports.stats.label.draw", defaultValue: "무"), color: .orange)
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
                    Text(String(localized: "teamInfo.home", defaultValue: "홈"))
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Text(String(format: String(localized: "teamInfo.record.wl", defaultValue: "%1$lld승 %2$lld패"), locale: .autoupdatingCurrent, r.homeWins, r.homeLosses))
                        .font(.subheadline.weight(.semibold))
                    Text(String(format: String(localized: "teamInfo.gamesShort", defaultValue: "%lld경기"), locale: .autoupdatingCurrent, Int64(r.homeWins + r.homeLosses + r.homeDraws)))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 44).padding(.horizontal, 8)

                VStack(spacing: 4) {
                    Text(String(localized: "teamInfo.away", defaultValue: "원정"))
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Text(String(format: String(localized: "teamInfo.record.wl", defaultValue: "%1$lld승 %2$lld패"), locale: .autoupdatingCurrent, r.awayWins, r.awayLosses))
                        .font(.subheadline.weight(.semibold))
                    Text(String(format: String(localized: "teamInfo.gamesShort", defaultValue: "%lld경기"), locale: .autoupdatingCurrent, Int64(r.awayWins + r.awayLosses + r.awayDraws)))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                if let streak = r.currentStreak {
                    Divider().frame(height: 44).padding(.horizontal, 8)
                    VStack(spacing: 4) {
                        Text(streak.type == .win ? String(localized: "teamInfo.streak.win", defaultValue: "연승") : String(localized: "teamInfo.streak.loss", defaultValue: "연패"))
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        Text(String(format: String(localized: "teamInfo.streak.count", defaultValue: "%lld연속"), locale: .autoupdatingCurrent, Int64(streak.count)))
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
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
        .groupedCardOutline(cornerRadius: 20)
    }

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(verbatim: value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(verbatim: label)
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
                Label(String(localized: "teamInfo.favoritePlayers", defaultValue: "최애 선수"), systemImage: "heart.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: String(localized: "teamInfo.favoriteCount", defaultValue: "%lld명"), locale: .autoupdatingCurrent, Int64(favPlayers.count)))
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
                        Text(verbatim: "#\(num)")
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
                Label(String(localized: "teamInfo.roster", defaultValue: "팀 선수단"), systemImage: "person.3.fill")
                    .font(.subheadline.bold())

                ForEach(0..<3, id: \.self) { _ in
                    squadRowSkeleton
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
            .groupedCardOutline(cornerRadius: 20)
        } else if squadPlayers.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Label(String(localized: "teamInfo.roster", defaultValue: "팀 선수단"), systemImage: "person.3.fill")
                    .font(.subheadline.bold())

                VStack(spacing: 8) {
                    Image(systemName: "person.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "teamInfo.rosterUnavailable", defaultValue: "선수단 정보를 찾을 수 없습니다"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
            .groupedCardOutline(cornerRadius: 20)
        } else {
            GroupedPlayerListCard(
                title: String(localized: "teamInfo.roster", defaultValue: "팀 선수단"),
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
