//
//  PlayerDetailView.swift
//  Fanfolio
//
//  선수 상세 정보 화면. 누끼 사진과 기본 정보를 표시하고
//  하트 버튼으로 즐겨찾기 등록/해제가 가능합니다.

import SwiftUI
import Kingfisher

private struct PlayerInfoRow: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let value: String
}

struct PlayerDetailView: View {
    let player: PlayerInfo
    let folder: SportsFanFolder?

    @State private var favorites = FavoritePlayersManager.shared

    private var playerIDString: String { "\(player.id)" }
    private var folderKey: String { folder?.folderID.uuidString ?? "__no_folder__" }
    private var isFavorite: Bool { favorites.isFavorite(playerIDString, inFolder: folderKey) }

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
                        favorites.toggleFavorite(playerIDString, inFolder: folderKey)
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

    // MARK: - 히어로 섹션 (선수 사진 + 이름 + 즐겨찾기 배지)

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

            // 선수 사진
            VStack(spacing: 0) {
                if let imgStr = player.imageURL, let url = URL(string: imgStr) {
                    KFImage.url(url)
                        .placeholder { playerPlaceholder }
                        .onFailureView { playerPlaceholder }
                        .resizable()
                        .scaledToFit()
                        .frame(height: 240)
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

    // MARK: - 플레이스홀더 (유니폼 실루엣 + 이니셜 + 등번호)

    private var playerPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 120, height: 120)

            // 종목별 유니폼 실루엣
            Group {
                if folder?.sportType == .basketball {
                    BasketballJerseyShape()
                        .fill(Color.white.opacity(0.18))
                } else {
                    ShortSleeveJerseyShape()
                        .fill(Color.white.opacity(0.18))
                }
            }
            .frame(width: 72, height: 72)

            VStack(spacing: 2) {
                if let num = player.number, !num.isEmpty {
                    Text("#\(num)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(teamColor.opacity(0.9))
                }
                Text(extractInitials(from: player.name))
                    .font(.system(
                        size: player.number == nil ? 44 : 36,
                        weight: .heavy,
                        design: .rounded
                    ))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 60)
        .padding(.bottom, 60)
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

    // MARK: - 기본 정보 카드

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("선수 정보", systemImage: "person.text.rectangle")
                .font(.subheadline.bold())

            Divider()

            let validRows: [PlayerInfoRow] = [
                PlayerInfoRow(title: "이름", value: player.name),
                player.position.map { PlayerInfoRow(title: "포지션", value: $0) },
                player.number.map { PlayerInfoRow(title: "등번호", value: "#\($0)") },
                player.age.map { PlayerInfoRow(title: "나이", value: "\($0)") },
                player.nationality.map { PlayerInfoRow(title: "국적", value: $0) },
                player.teamName.map { PlayerInfoRow(title: "소속팀", value: $0) }
            ].compactMap { $0 }

            ForEach(validRows) { row in
                HStack {
                    Text(row.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Text(row.value)
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
                imageURL: nil,
                nationality: "American",
                age: 26,
                teamName: "San Francisco 49ers"
            ),
            folder: nil
        )
    }
}
