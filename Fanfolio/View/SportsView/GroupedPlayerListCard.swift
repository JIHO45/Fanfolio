//
//  GroupedPlayerListCard.swift
//  Fanfolio
//

import SwiftUI

struct GroupedPlayerListCard<Destination: View>: View {
    let title: LocalizedStringKey
    let players: [PlayerInfo]
    let sportType: SportType
    let teamColorHex: String?
    let fallbackTeamLogoURL: String?
    let fallbackGradient: [Color]
    let favoriteFolderKey: String
    @Binding var selectedGroup: PositionGroup?
    @Binding var selectedNFLPhase: NFLPhase?
    let destination: (PlayerInfo) -> Destination

    @State private var favorites = FavoritePlayersManager.shared

    private var teamColor: Color {
        Color.from(hex: teamColorHex) ?? .blue
    }

    private var groupedPlayers: [(group: PositionGroup, players: [PlayerInfo])] {
        let all = groupedByPosition(players, sport: sportType)

        if sportType == .americanFootball {
            if let phase = selectedNFLPhase {
                let phaseFiltered = all.filter { $0.group.nflPhase == phase }
                if let detail = selectedGroup {
                    return phaseFiltered.filter { $0.group == detail }
                }
                return phaseFiltered
            }
            return all
        }

        if let selectedGroup {
            return all.filter { $0.group == selectedGroup }
        }
        return all
    }

    private var filteredPlayerCount: Int {
        groupedPlayers.reduce(0) { $0 + $1.players.count }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: "person.3.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: String(localized: "playerList.count.players", defaultValue: "%lld명"), locale: .autoupdatingCurrent, Int64(filteredPlayerCount)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            positionFilterChips

            if sportType == .americanFootball, let phase = selectedNFLPhase {
                nflDetailChips(for: phase)
            }

            ForEach(groupedPlayers, id: \.group.displayName) { section in
                positionSectionHeader(group: section.group, count: section.players.count)

                ForEach(section.players) { player in
                    NavigationLink(destination: destination(player)) {
                        playerRow(player: player)
                    }
                    .buttonStyle(.plain)

                    if player.id != section.players.last?.id {
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

    @ViewBuilder
    private var positionFilterChips: some View {
        if sportType == .americanFootball {
            let phases: [NFLPhase?] = [nil] + NFLPhase.allCases.map { Optional($0) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(phases, id: \.self) { phase in
                        nflPhaseChip(phase: phase)
                    }
                }
                .padding(.horizontal, 2)
            }
        } else {
            let allGroups: [PositionGroup?] = [nil] + sportType.allPositionGroups.map { Optional($0) }
            if allGroups.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allGroups, id: \.self) { group in
                            positionChip(group: group)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private func positionChip(group: PositionGroup?) -> some View {
        let label = group?.displayName ?? String(localized: "playerList.filter.all", defaultValue: "전체")
        let isSelected = selectedGroup == group
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedGroup = group
            }
        } label: {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? teamColor : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func nflPhaseChip(phase: NFLPhase?) -> some View {
        let label = phase?.displayName ?? String(localized: "playerList.filter.all", defaultValue: "전체")
        let isSelected = selectedNFLPhase == phase
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedNFLPhase = phase
                selectedGroup = nil
            }
        } label: {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? teamColor : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func nflDetailChips(for phase: NFLPhase) -> some View {
        let detailGroups: [PositionGroup?] = [nil] + sportType.nflDetailGroups(for: phase).map { Optional($0) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(detailGroups, id: \.self) { group in
                    let label = group?.displayName ?? String(localized: "playerList.filter.all", defaultValue: "전체")
                    let isSelected = selectedGroup == group
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedGroup = group
                        }
                    } label: {
                        Text(label)
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(isSelected
                                          ? teamColor.opacity(0.75)
                                          : Color.secondary.opacity(0.10))
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func positionSectionHeader(group: PositionGroup, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(group.displayName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.5)))
            Spacer()
        }
        .padding(.top, 4)
    }

    private func playerRow(player: PlayerInfo) -> some View {
        let isFavorite = favorites.isFavorite("\(player.id)", inFolder: favoriteFolderKey)

        return HStack(spacing: 12) {
            PlayerImageView(
                imageURL: player.imageURL,
                fallbackTeamLogoURL: fallbackTeamLogoURL,
                fallbackGradient: fallbackGradient,
                playerName: player.name,
                jerseyNumber: player.number,
                sportType: sportType
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(player.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let number = player.number {
                        Text("#\(number)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(teamColor.opacity(0.8)))
                    }
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                if let position = player.position {
                    Text(position)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
