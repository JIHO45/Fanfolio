//
//  GolfRoundDetailView.swift
//  Fanfolio
//

import SwiftUI
import SwiftData

// MARK: - GolfRoundDetailView

struct GolfRoundDetailView: View {
    let round: GolfRoundModel

    @State private var showingEditSheet = false
    @State private var showingQRZoomCover = false

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy년 M월 d일 (E)"
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt
    }()

    private var teamColor: Color {
        Color.from(hex: round.folder?.teamColor) ?? .green
    }

    private var teamLogoURL: String? { round.folder?.teamLogoUrl }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 예정/진행중 배너
                if round.roundStatus != .completed {
                    statusBanner.padding(.horizontal)
                }

                // 메인 카드
                roundCard.padding(.horizontal)

                // 완료 시: 스코어 카드
                if round.roundStatus == .completed {
                    if round.totalScore != nil {
                        scoreCard.padding(.horizontal)
                    }

                    // 세부 스코어
                    if round.hasDetailScore {
                        detailScoreCard.padding(.horizontal)
                    }

                    // 퍼팅/페어웨이/GIR
                    if round.putts != nil || round.fairwaysHit != nil || round.greensInRegulation != nil {
                        statsCard.padding(.horizontal)
                    }
                }

                // 직관 사진
                if let photos = round.photosData, !photos.isEmpty {
                    photosSection(photos).padding(.horizontal)
                }

                // 메모
                if let memo = round.memo, !memo.isEmpty {
                    memoSection(memo).padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(round.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("편집") { showingEditSheet = true }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            AddGolfRoundView(
                folder: round.folder ?? SportsFanFolder(name: "", sportType: .golf),
                nextOrderIndex: round.orderIndex,
                editingRound: round
            )
        }
        .fullScreenCover(isPresented: $showingQRZoomCover) {
            if let data = round.qrCodeImageData {
                QRZoomView(imageData: data)
            }
        }
    }

    // MARK: - 상태 배너

    private var statusBanner: some View {
        HStack {
            Image(systemName: round.roundStatus.iconName)
                .foregroundStyle(round.roundStatus.color)
                .symbolEffect(.pulse, isActive: round.roundStatus == .live)
            Text(round.roundStatus.rawValue)
                .font(.subheadline.bold())
                .foregroundStyle(round.roundStatus.color)
            Spacer()
            Text("편집 버튼을 눌러 결과를 입력하세요")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(round.roundStatus.color.opacity(0.1))
        )
    }

    // MARK: - 메인 라운드 카드

    private var roundCard: some View {
        VStack(spacing: 0) {
            // 컬러 밴드
            teamColor
                .frame(height: 10)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))

            VStack(spacing: 20) {
                // 종목 배지
                HStack(spacing: 6) {
                    Image(systemName: "figure.golf")
                        .font(.caption)
                    Text("골프")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())

                // 골프장 로고 + 라운드 제목
                VStack(spacing: 12) {
                    if let logoURL = teamLogoURL, !logoURL.isEmpty {
                        ZStack {
                            LinearGradient(
                                colors: round.folder?.gradientColors ?? [teamColor, teamColor.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                            AsyncImage(url: URL(string: logoURL)) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFit().padding(12)
                                case .failure: Image(systemName: "figure.golf").font(.title2).foregroundStyle(.white.opacity(0.8))
                                default: ProgressView().tint(.white)
                                }
                            }
                        }
                        .frame(width: 68, height: 68)
                    }

                    Text(round.title)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)

                    if let course = round.courseName, !course.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(teamColor)
                                .font(.caption)
                            Text(course)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 홀 수 + 대회 여부 배지
                    HStack(spacing: 8) {
                        Text(round.holesText)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(teamColor.opacity(0.8))
                            .clipShape(Capsule())

                        if round.isTournament {
                            Label("대회", systemImage: "trophy.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.yellow.opacity(0.8))
                                .clipShape(Capsule())
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
                if let date = round.date {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .frame(width: 20)
                            .foregroundStyle(teamColor)
                        Text(Self.dateFormatter.string(from: date))
                            .font(.subheadline.weight(.medium))
                    }
                }

                if let data = round.qrCodeImageData, let uiImage = UIImage(data: data) {
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

                // 브랜딩 푸터
                HStack {
                    Spacer()
                    Text("Fanfolio")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.quaternary)
                        .tracking(1)
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20))
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    // MARK: - 스코어 카드

    private var scoreCard: some View {
        VStack(spacing: 16) {
            HStack {
                Label("스코어", systemImage: "flag.fill")
                    .font(.subheadline.bold())
                Spacer()
                if let pos = round.myPosition {
                    Text("\(pos)위")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(positionColor(pos))
                        .clipShape(Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // 총 타수
                VStack(spacing: 4) {
                    Text(round.totalScoreText)
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(teamColor)
                    Text("타")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 파 대비
                VStack(alignment: .center, spacing: 4) {
                    Text(round.scoreToParText)
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(round.scoreColor)
                    Text("파 대비")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 코스 파
                if let p = round.par {
                    VStack(spacing: 4) {
                        Text("Par \(p)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(round.holesText)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
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

    // MARK: - 세부 스코어 카드

    private var detailScoreCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("홀별 결과", systemImage: "chart.bar.fill")
                .font(.subheadline.bold())

            let items: [(String, String, Int?, Color)] = [
                ("🦅", "이글 이하", round.eagleCount, .yellow),
                ("🐦", "버디", round.birdieCount, .green),
                ("⚪️", "파", round.parCount, .secondary),
                ("🟠", "보기", round.bogeyCount, .orange),
                ("🔴", "더블보기+", round.doubleBogeyPlusCount, .red),
            ]

            ForEach(items, id: \.1) { icon, label, count, color in
                if let c = count {
                    HStack {
                        Text(icon)
                        Text(label)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        // 막대
                        GeometryReader { geo in
                            let total = CGFloat(max(round.numberOfHoles, 1))
                            let width = geo.size.width * CGFloat(min(c, round.numberOfHoles)) / total
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.1))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(color == .secondary ? Color.secondary.opacity(0.4) : color.opacity(0.7))
                                    .frame(width: max(width, c > 0 ? 8 : 0))
                            }
                        }
                        .frame(width: 80, height: 10)

                        Text("\(c)홀")
                            .font(.subheadline.bold())
                            .foregroundStyle(color == .secondary ? Color.secondary : color)
                            .frame(width: 36, alignment: .trailing)
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

    // MARK: - 퍼팅/페어웨이/GIR 통계 카드

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("어프로치 통계", systemImage: "target")
                .font(.subheadline.bold())

            HStack(spacing: 0) {
                if let putts = round.putts {
                    statCell(value: "\(putts)", label: "총 퍼팅")
                }
                if round.putts != nil && (round.fairwaysHit != nil || round.greensInRegulation != nil) {
                    Divider().frame(height: 40)
                }
                if let fw = round.fairwaysHit {
                    let total = round.numberOfHoles == 18 ? 14 : 7
                    statCell(value: "\(fw)/\(total)", label: "페어웨이")
                }
                if round.fairwaysHit != nil && round.greensInRegulation != nil {
                    Divider().frame(height: 40)
                }
                if let gir = round.greensInRegulation {
                    statCell(value: "\(gir)/\(round.numberOfHoles)", label: "GIR")
                }
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

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(teamColor)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

    // MARK: - 순위 색상

    private func positionColor(_ pos: Int) -> Color {
        switch pos {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return .secondary
        }
    }
}

// MARK: - Preview

#Preview("골프 상세 - 완료") {
    let folder = SportsFanFolder(name: "골프", sportType: .golf)
    folder.teamColor = "2E7D32"

    let round = GolfRoundModel(
        title: "버디힐스 CC 봄 라운드",
        date: Date(),
        courseName: "버디힐스 컨트리클럽",
        roundStatus: .completed,
        numberOfHoles: 18,
        isTournament: false,
        totalScore: 79,
        par: 72,
        eagleCount: 0,
        birdieCount: 3,
        parCount: 8,
        bogeyCount: 6,
        doubleBogeyPlusCount: 1,
        putts: 32,
        fairwaysHit: 9,
        greensInRegulation: 8,
        memo: "오늘 드라이버 감이 좋았다. 퍼팅에서 3퍼팅이 좀 나온 게 아쉽다."
    )
    round.folder = folder

    return NavigationStack {
        GolfRoundDetailView(round: round)
    }
}

#Preview("골프 상세 - 대회") {
    let folder = SportsFanFolder(name: "골프", sportType: .golf)
    folder.teamColor = "2E7D32"

    let round = GolfRoundModel(
        title: "클럽 챔피언십 1라운드",
        date: Date(),
        courseName: "파인힐스 GC",
        roundStatus: .completed,
        numberOfHoles: 18,
        isTournament: true,
        myPosition: 2,
        totalScore: 71,
        par: 72,
        birdieCount: 4,
        parCount: 11,
        bogeyCount: 3
    )
    round.folder = folder

    return NavigationStack {
        GolfRoundDetailView(round: round)
    }
}

#Preview("골프 상세 - 예정") {
    let folder = SportsFanFolder(name: "골프", sportType: .golf)
    folder.teamColor = "2E7D32"

    let round = GolfRoundModel(
        title: "주말 라운드",
        date: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
        courseName: "선셋 힐스 GC",
        roundStatus: .upcoming,
        numberOfHoles: 18
    )
    round.folder = folder

    return NavigationStack {
        GolfRoundDetailView(round: round)
    }
}
