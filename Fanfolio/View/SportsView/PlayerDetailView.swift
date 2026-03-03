//
//  PlayerDetailView.swift
//  Fanfolio
//
//  선수 상세 정보 화면. 누끼 사진, 기본 정보, 시즌 스탯을 표시하고
//  하트 버튼으로 즐겨찾기 등록/해제가 가능합니다.

import SwiftUI

struct PlayerDetailView: View {
    let player: PlayerInfo
    let sportType: SportType
    let folder: SportsFanFolder?

    @State private var favorites = FavoritePlayersManager.shared

    private var playerIDString: String { "\(player.id)" }
    private var isFavorite: Bool { favorites.isFavorite(playerIDString) }

    private var teamColor: Color {
        Color.from(hex: folder?.teamColor) ?? .blue
    }
    private var gradientColors: [Color] {
        folder?.gradientColors ?? [.gray, .gray.opacity(0.7)]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 상단 히어로 영역
                heroSection
                    .padding(.bottom, 24)

                // 기본 정보 카드
                infoCard
                    .padding(.horizontal)
                    .padding(.bottom, 16)

                // 스탯 카드 (있을 때만)
                if let stats = player.stats {
                    statsCard(stats: stats)
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        favorites.toggleFavorite(playerIDString)
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? .red : .secondary)
                        .font(.title3)
                        .symbolEffect(.bounce, value: isFavorite)
                }
            }
        }
    }

    // MARK: - 히어로 섹션 (누끼 사진 + 이름 + 즐겨찾기 배지)

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            // 배경 그라디언트
            LinearGradient(
                colors: gradientColors.map { $0.opacity(0.6) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(maxWidth: .infinity)
            .frame(height: 280)

            // 누끼 or 일반 사진
            VStack(spacing: 0) {
                if let cutoutStr = player.cutoutImageURL, let url = URL(string: cutoutStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(height: 240)
                        case .empty:
                            playerPlaceholder
                        default:
                            playerPlaceholder
                        }
                    }
                } else if let photoStr = player.photoURL, let url = URL(string: photoStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 180, height: 180)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 2))
                                .padding(.top, 40)
                        default:
                            playerPlaceholder
                        }
                    }
                } else {
                    playerPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 이름 + 포지션 오버레이
            VStack(spacing: 4) {
                // 즐겨찾기 배지
                if isFavorite {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                        Text("최애 선수")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.85))
                    .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    Text(player.name)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)

                    if let num = player.number {
                        Text("#\(num)")
                            .font(.headline.bold())
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(teamColor.opacity(0.7))
                            .clipShape(Capsule())
                    }
                }

                if let pos = player.position {
                    Text(pos)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.4), radius: 3)
                }
            }
            .padding(.bottom, 20)
            .padding(.horizontal)
        }
        .clipped()
    }

    // MARK: - 플레이스홀더

    private var playerPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 120, height: 120)
            Image(systemName: "person.fill")
                .font(.system(size: 50))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 60)
        .padding(.bottom, 60)
    }

    // MARK: - 기본 정보 카드

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("선수 정보", systemImage: "person.text.rectangle")
                .font(.subheadline.bold())

            Divider()

            let rows: [(String, String?)] = [
                ("이름", player.name),
                ("포지션", player.position),
                ("등번호", player.number.map { "#\($0)" }),
                ("나이", player.age.map { "\($0)세" }),
                ("국적", player.nationality),
                ("소속팀", player.teamName)
            ]

            ForEach(rows.filter { $0.1 != nil }, id: \.0) { label, value in
                HStack {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Text(value ?? "")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    // MARK: - 스탯 카드

    private func statsCard(stats: PlayerSeasonStats) -> some View {
        let highlights = stats.highlights(for: sportType)
        guard !highlights.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 14) {
                Label("시즌 스탯", systemImage: "chart.bar.fill")
                    .font(.subheadline.bold())

                Divider()

                // 게임 수 (있을 때)
                if let games = stats.gamesPlayed {
                    HStack {
                        Text("출전 경기")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(games)경기")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                // 핵심 스탯 그리드
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: min(highlights.count, 3)),
                    spacing: 12
                ) {
                    ForEach(highlights, id: \.0) { label, value in
                        statCell(label: label, value: value)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        )
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(teamColor)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(teamColor.opacity(0.07))
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PlayerDetailView(
            player: PlayerInfo(
                id: 34159,
                name: "Nick Bosa",
                position: "DE",
                number: "97",
                cutoutImageURL: nil,
                photoURL: nil,
                nationality: "American",
                age: 26,
                teamName: "San Francisco 49ers",
                stats: PlayerSeasonStats(
                    gamesPlayed: 16,
                    passingTouchdowns: nil,
                    passingYards: nil,
                    rushingTouchdowns: nil,
                    rushingYards: nil,
                    receptions: nil,
                    receivingYards: nil,
                    receivingTouchdowns: nil,
                    sacks: 9.5,
                    interceptions: 1,
                    goals: nil,
                    assists: nil,
                    yellowCards: nil,
                    redCards: nil,
                    minutesPlayed: nil,
                    shotsOnTarget: nil,
                    points: nil,
                    rebounds: nil,
                    basketballAssists: nil,
                    steals: nil,
                    blocks: nil,
                    battingAvg: nil,
                    homeRuns: nil,
                    rbi: nil,
                    era: nil,
                    strikeouts: nil,
                    wins: nil,
                    raceWins: nil,
                    podiums: nil,
                    championshipPoints: nil,
                    polePositions: nil
                )
            ),
            sportType: .americanFootball,
            folder: nil
        )
    }
}
