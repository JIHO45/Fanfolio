//
//  F1RaceDetailView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/24/26.
//

import SwiftUI
import SwiftData

// MARK: - F1RaceDetailView

struct F1RaceDetailView: View {
    let race: F1RaceModel

    @State private var showingEditSheet = false
    @State private var showingQRZoomCover = false

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy년 M월 d일 (E)"
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt
    }()

    private var teamColor: Color {
        Color.from(hex: race.folder?.teamColor) ?? .red
    }

    private var teamLogoURL: String? { race.folder?.teamLogoUrl }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 예정/진행중 배너
                if race.raceStatus != .completed {
                    statusBanner.padding(.horizontal)
                }

                // 메인 카드 (헤더 + 날짜 + QR)
                raceCard.padding(.horizontal)

                // 포디움 섹션
                if race.raceStatus == .completed {
                    if race.podium1DriverName != nil || race.podium2DriverName != nil {
                        podiumSection.padding(.horizontal)
                    }

                    // 내 드라이버 결과
                    if race.myDriverName != nil {
                        myResultCard.padding(.horizontal)
                    }
                }

                // 직관 사진
                if let photos = race.photosData, !photos.isEmpty {
                    photosSection(photos).padding(.horizontal)
                }

                // 메모
                if let memo = race.memo, !memo.isEmpty {
                    memoSection(memo).padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(race.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("편집") { showingEditSheet = true }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            AddF1RaceView(
                folder: race.folder ?? SportsFanFolder(name: "", sportType: .racing),
                nextOrderIndex: race.orderIndex,
                editingRace: race
            )
        }
        .fullScreenCover(isPresented: $showingQRZoomCover) {
            if let data = race.qrCodeImageData {
                QRZoomView(imageData: data)
            }
        }
    }

    // MARK: - 상태 배너

    private var statusBanner: some View {
        HStack {
            Image(systemName: race.raceStatus.iconName)
                .foregroundStyle(race.raceStatus.color)
                .symbolEffect(.pulse, isActive: race.raceStatus == .live)
            Text(race.raceStatus.rawValue)
                .font(.subheadline.bold())
                .foregroundStyle(race.raceStatus.color)
            Spacer()
            Text("편집 버튼을 눌러 결과를 입력하세요")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(race.raceStatus.color.opacity(0.1))
        )
    }

    // MARK: - 메인 레이스 카드

    private var raceCard: some View {
        VStack(spacing: 0) {
            // 컬러 밴드
            teamColor
                .frame(height: 10)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))

            VStack(spacing: 20) {
                // 종목 배지
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.caption)
                    Text("F1 모터스포츠")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())

                // 컨스트럭터 로고 + 레이스명
                VStack(spacing: 12) {
                    if let logoURL = teamLogoURL, !logoURL.isEmpty {
                        ZStack {
                            LinearGradient(
                                colors: race.folder?.gradientColors ?? [teamColor, teamColor.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                            AsyncImage(url: URL(string: logoURL)) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFit().padding(12)
                                case .failure: Image(systemName: "flag.checkered").font(.title2).foregroundStyle(.white.opacity(0.8))
                                default: ProgressView().tint(.white)
                                }
                            }
                        }
                        .frame(width: 68, height: 68)
                    }

                    Text(race.title)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)

                    if let circuit = race.circuitName, !circuit.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(teamColor)
                                .font(.caption)
                            Text(circuit)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))

            // 절취선
            ticketDivider

            // 날짜 + QR
            VStack(alignment: .leading, spacing: 16) {
                if let date = race.date {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .frame(width: 20)
                            .foregroundStyle(teamColor)
                        Text(Self.dateFormatter.string(from: date))
                            .font(.subheadline.weight(.medium))
                    }
                }

                if let data = race.qrCodeImageData, let uiImage = UIImage(data: data) {
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: "qrcode").foregroundStyle(teamColor)
                            Text("티켓 · QR코드")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            Spacer()
                            Text("탭하여 확대")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Button { showingQRZoomCover = true } label: {
                            Image(uiImage: uiImage)
                                .resizable().scaledToFit()
                                .frame(maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20))
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    // MARK: - 포디움 섹션

    private var podiumSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("포디움", systemImage: "trophy.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 0) {
                // 2위
                podiumBlock(
                    position: 2,
                    driverName: race.podium2DriverName,
                    height: 80
                )

                // 1위 (가장 높음)
                podiumBlock(
                    position: 1,
                    driverName: race.podium1DriverName,
                    height: 110
                )

                // 3위
                podiumBlock(
                    position: 3,
                    driverName: race.podium3DriverName,
                    height: 60
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }

    private func podiumBlock(position: Int, driverName: String?, height: CGFloat) -> some View {
        let (color, medal): (Color, String) = switch position {
        case 1: (Color(red: 1.0, green: 0.84, blue: 0.0), "🥇")
        case 2: (Color(red: 0.75, green: 0.75, blue: 0.75), "🥈")
        default: (Color(red: 0.8, green: 0.5, blue: 0.2), "🥉")
        }

        return VStack(spacing: 6) {
            Text(medal).font(.title2)
            Text(driverName ?? "-")
                .font(.system(size: 11, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(driverName != nil ? .primary : .tertiary)
                .frame(width: 80)

            Text("\(position)위")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)

            // 단상 블록
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(color.opacity(0.5), lineWidth: 1.5)
                )
                .frame(height: height)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 내 드라이버 결과 카드

    private var myResultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("내 결과", systemImage: "person.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                // 드라이버 헤드샷
                ZStack {
                    Circle()
                        .fill(race.positionBadgeColor.opacity(0.15))
                        .frame(width: 72, height: 72)

                    if let url = race.myDriverHeadshotURL {
                        AsyncImage(url: URL(string: url)) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                                    .frame(width: 68, height: 68)
                                    .clipShape(Circle())
                            default:
                                driverPlaceholder
                            }
                        }
                    } else {
                        driverPlaceholder
                    }
                }
                .overlay(Circle().strokeBorder(race.positionBadgeColor, lineWidth: 2))

                // 드라이버 정보
                VStack(alignment: .leading, spacing: 4) {
                    Text(race.myDriverName ?? "")
                        .font(.title3.bold())
                    if let team = race.myConstructorName, !team.isEmpty {
                        Text(team)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // 순위 뱃지
                    HStack(spacing: 6) {
                        if race.isDNF {
                            Label("DNF", systemImage: "xmark.circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.red)
                                .clipShape(Capsule())
                        } else if race.myFinishPosition != nil {                            Text(race.positionText)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(race.positionBadgeColor)
                                .clipShape(Capsule())

                            if race.isPodiumFinish {
                                Text("포디움!")
                                    .font(.caption.bold())
                                    .foregroundStyle(race.positionBadgeColor)
                            }
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }

    private var driverPlaceholder: some View {
        Image(systemName: "person.fill")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
    }

    // MARK: - 직관 사진

    private func photosSection(_ photos: [Data]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("직관 사진", systemImage: "photo.stack.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos.indices, id: \.self) { i in
                        if let uiImage = UIImage(data: photos[i]) {
                            Image(uiImage: uiImage)
                                .resizable().scaledToFill()
                                .frame(width: 140, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }

    // MARK: - 메모

    private func memoSection(_ memo: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("메모", systemImage: "text.quote")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Text(memo)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }

    // MARK: - 절취선

    private var ticketDivider: some View {
        HStack(spacing: 0) {
            Circle().fill(Color(uiColor: .systemGroupedBackground)).frame(width: 20, height: 20)
                .offset(x: -10)
            Rectangle()
                .fill(Color(uiColor: .systemGroupedBackground))
                .frame(height: 1.5)
                .overlay(
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                )
            Circle().fill(Color(uiColor: .systemGroupedBackground)).frame(width: 20, height: 20)
                .offset(x: 10)
        }
        .frame(height: 20)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

// MARK: - Preview

#Preview("F1 상세 - 완료 (포디움 O)") {
    let folder = SportsFanFolder(name: "Ferrari", sportType: .racing)
    folder.teamColor = "DC0000"
    folder.teamAlternateColor = "FFFFFF"
    folder.teamLogoUrl = "https://a.espncdn.com/i/teamlogos/f1/500/ferrari.png"
    folder.leagueCode = "F1"

    let race = F1RaceModel(
        title: "2026 일본 그랑프리",
        date: Date(),
        circuitName: "스즈카 서킷",
        raceStatus: .completed,
        myDriverName: "Charles Leclerc",
        myDriverESPNId: "4848",
        myConstructorName: "Ferrari",
        myFinishPosition: 2,
        podium1DriverName: "Max Verstappen",
        podium2DriverName: "Charles Leclerc",
        podium3DriverName: "Lando Norris"
    )
    race.folder = folder

    return NavigationStack {
        F1RaceDetailView(race: race)
    }
}

#Preview("F1 상세 - DNF") {
    let folder = SportsFanFolder(name: "Mercedes", sportType: .racing)
    folder.teamColor = "00D2BE"
    folder.leagueCode = "F1"

    let race = F1RaceModel(
        title: "2026 모나코 그랑프리",
        date: Date(),
        circuitName: "몬테카를로 서킷",
        raceStatus: .completed,
        myDriverName: "George Russell",
        myDriverESPNId: "4731",
        myConstructorName: "Mercedes",
        myFinishPosition: 0
    )
    race.folder = folder

    return NavigationStack {
        F1RaceDetailView(race: race)
    }
}

#Preview("F1 상세 - 예정") {
    let folder = SportsFanFolder(name: "McLaren", sportType: .racing)
    folder.teamColor = "FF8700"
    folder.leagueCode = "F1"

    let race = F1RaceModel(
        title: "2026 바레인 그랑프리",
        date: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
        circuitName: "바레인 인터내셔널 서킷",
        raceStatus: .upcoming
    )
    race.folder = folder

    return NavigationStack {
        F1RaceDetailView(race: race)
    }
}
