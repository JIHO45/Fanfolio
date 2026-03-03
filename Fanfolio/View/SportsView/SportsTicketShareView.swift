//
//  SportsTicketShareView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/24/26.
//

import SwiftUI

// MARK: - 스포츠 티켓 공유 뷰

/// 스포츠 경기 티켓 이미지를 생성·미리보기·공유하는 시트.
/// ESPN 비공식 API로 팀 로스터를 불러와 선수 선택 피커를 제공한다.
struct SportsTicketShareView: View {
    @Environment(\.dismiss) private var dismiss

    let match: SportsModel

    // MARK: 상태

    @State private var espnAthletes: [ESPNAthlete] = []
    @State private var isLoadingPlayers = false
    @State private var selectedAthlete: ESPNAthlete? = nil
    @State private var selectedStyle: ShareStyle = .dark
    @State private var currentImage: UIImage?
    @State private var isGenerating = false
    @State private var showingActivityShareSheet = false

    // MARK: ESPN 팀 데이터

    private var team1Data: ESPNTeam? {
        ESPNTeamsLoader.team(name: match.team1Display, leagueCode: match.folder?.leagueCode)
    }
    private var team2Data: ESPNTeam? {
        ESPNTeamsLoader.team(name: match.opponentTeam, leagueCode: match.folder?.leagueCode)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.06, blue: 0.08).ignoresSafeArea()

                VStack(spacing: 0) {
                    // 스타일 선택 (라이트 / 다크)
                    Picker("스타일", selection: $selectedStyle) {
                        ForEach(ShareStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    // ESPN 선수 피커
                    playerPickerSection
                        .padding(.bottom, 12)

                    // 티켓 이미지 미리보기
                    ScrollView {
                        if let image = currentImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 20)
                        } else if isGenerating {
                            VStack(spacing: 12) {
                                ProgressView().tint(.white)
                                Text("이미지 생성 중...")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .padding(.top, 60)
                        }
                    }

                    // 공유 버튼
                    shareButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
            .navigationTitle("티켓 이미지 공유")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .onChange(of: selectedStyle) { _, _ in regenerate() }
            .onChange(of: selectedAthlete?.id) { _, _ in regenerate() }
            .task {
                await loadESPNRoster()
                regenerate()
            }
            .sheet(isPresented: $showingActivityShareSheet) {
                if let currentImage {
                    FanfolioShareSheet(items: [currentImage])
                }
            }
        }
    }

    // MARK: - 선수 피커 섹션

    private var playerPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if isLoadingPlayers {
                    ProgressView().scaleEffect(0.7).tint(.white)
                }
                Text(isLoadingPlayers
                     ? "ESPN 로스터 불러오는 중…"
                     : espnAthletes.isEmpty
                         ? "선수 정보 없음 (팀 로고 사용)"
                         : "선수 선택")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 24)

            if !espnAthletes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        // "선수 없음" 옵션
                        athletePickerCell(athlete: nil)

                        ForEach(espnAthletes) { athlete in
                            athletePickerCell(athlete: athlete)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    private func athletePickerCell(athlete: ESPNAthlete?) -> some View {
        let isSelected: Bool = {
            if athlete == nil { return selectedAthlete == nil }
            return athlete?.id == selectedAthlete?.id
        }()

        return Button {
            selectedAthlete = athlete
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(isSelected
                              ? Color.blue.opacity(0.3)
                              : Color.white.opacity(0.08))
                        .frame(width: 54, height: 54)

                    if let athlete, let urlString = athlete.headshotURL,
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                personIcon(selected: isSelected)
                            }
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                    } else if athlete != nil {
                        personIcon(selected: isSelected)
                    } else {
                        // "선수 없음" 아이콘
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.blue : .white.opacity(0.45))
                    }
                }
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? Color.blue : Color.clear,
                        lineWidth: 2
                    )
                )

                // 이름 라벨
                VStack(spacing: 1) {
                    if let num = athlete?.jerseyNumber {
                        Text("#\(num)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(isSelected ? Color.blue : .white.opacity(0.35))
                    }
                    Text(athlete?.shortName ?? "없음")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                        .lineLimit(1)
                        .frame(width: 56)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func personIcon(selected: Bool) -> some View {
        Image(systemName: "person.fill")
            .font(.title3)
            .foregroundStyle(selected ? .white : .white.opacity(0.45))
    }

    // MARK: - 공유 버튼

    private var shareButton: some View {
        Button {
            showingActivityShareSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                Text("공유하기")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(currentImage == nil)
        .opacity(currentImage == nil ? 0.5 : 1)
    }

    // MARK: - ESPN 로스터 / 선수 목록 로드

    private func loadESPNRoster() async {
        guard let leagueCode = match.folder?.leagueCode else { return }

        isLoadingPlayers = true

        if ESPNPlayerService.shared.isIndividualSport(leagueCode) {
            // 개인 종목 (F1·UFC·ATP·WTA·PGA): 리그 전체 선수 목록
            espnAthletes = await ESPNPlayerService.shared.fetchLeagueAthletes(leagueCode: leagueCode)
        } else if let teamId = team1Data?.id, !teamId.isESPNFakeID {
            // 팀 종목 + 진짜 ESPN ID: 팀 로스터
            espnAthletes = await ESPNPlayerService.shared.fetchRoster(
                teamESPNId: teamId,
                leagueCode: leagueCode
            )
        }

        // ESPN에 데이터가 없는 리그(KBO·K리그 등) → TheSportsDB fallback
        if espnAthletes.isEmpty {
            await loadTheSportsDBFallback()
        }

        isLoadingPlayers = false
    }

    /// TheSportsDB에서 선수단을 불러와 ESPNAthlete 배열로 변환 (KBO·K리그 등 ESPN 미지원 리그용)
    /// TheSportsDB는 영문 팀명으로 검색하므로 name_en을 우선 사용
    private func loadTheSportsDBFallback() async {
        let teamName = team1Data?.name_en ?? match.folder?.name ?? match.team1Display
        guard !teamName.isEmpty else { return }
        let players = (try? await TheSportsDBService.shared.fetchSquadByTeamName(teamName)) ?? []
        espnAthletes = players.compactMap { p in
            ESPNAthlete(
                id: "\(p.id)",
                name: p.name,
                position: p.position,
                jerseyNumber: p.number,
                headshotURL: p.cutoutImageURL ?? p.photoURL
            )
        }
    }

    // MARK: - 이미지 생성

    private func regenerate() {
        Task { @MainActor in
            isGenerating = true
            withAnimation(.easeInOut(duration: 0.15)) { currentImage = nil }
            let img = await buildImage()
            withAnimation(.easeInOut(duration: 0.25)) {
                currentImage = img
                isGenerating = false
            }
        }
    }

    @MainActor
    private func buildImage() async -> UIImage? {
        // 팀 로고 + ESPN 선수 헤드샷 병렬 로드
        let team1LogoURL = match.hasFavoriteTeam
            ? match.folder?.teamLogoUrl
            : team1Data?.logo_url
        let team2LogoURL = team2Data?.logo_url
        let athleteHeadshotURL = selectedAthlete?.headshotURL

        async let logoTask1 = loadURLOptional(team1LogoURL)
        async let logoTask2 = loadURLOptional(team2LogoURL)
        async let headshotTask = loadURLOptional(athleteHeadshotURL)

        let (myLogo, oppLogo, headshot) = await (logoTask1, logoTask2, headshotTask)

        // 팀 컬러 결정
        let teamColor: Color = {
            if match.hasFavoriteTeam, let hex = match.folder?.teamColor {
                return Color.from(hex: hex) ?? .red
            }
            return team1Data.flatMap { Color.from(hex: $0.color) } ?? .red
        }()

        // 팀 닉네임 결정
        let nickname = nonEmpty(match.folder?.teamNickname) ?? match.team1Display

        // 좌석 정보 (match 데이터 해시로 안정적인 값 생성)
        let sectionLetters = ["A","B","C","D","E","F","G","H","J","K"]
        let secIdx = match.title.unicodeScalars
            .reduce(0) { ($0 &+ Int($1.value)) } % sectionLetters.count
        let sec = sectionLetters[abs(secIdx)]
        let row = "\(abs(match.myTeamScore &* 7 &+ match.opponentScore &* 3) % 20 + 1)"
        let seat = "\(abs(match.opponentScore &* 11 &+ match.orderIndex &* 7) % 40 + 1)"

        let model = MatchTicketModel(
            teamName: match.team1Display,
            teamNickname: nickname,
            opponentTeam: match.team2Display,
            myTeamScore: match.myTeamScore,
            opponentScore: match.opponentScore,
            matchResult: match.matchResult,
            matchStatus: match.matchStatus,
            sportType: match.folder?.sportType ?? .other,
            isHomeGame: match.isHomeGame,
            gameNumber: max(1, match.orderIndex + 1),
            teamColor: teamColor,
            teamLogoImage: myLogo,
            opponentLogoImage: oppLogo,
            playerCutoutImage: headshot,
            date: match.date,
            location: match.location,
            style: selectedStyle,
            sec: sec,
            row: row,
            seat: seat
        )

        let outerBg: Color = selectedStyle == .light
            ? Color(red: 0.92, green: 0.92, blue: 0.92)
            : Color(red: 0.06, green: 0.06, blue: 0.08)

        let renderer = ImageRenderer(
            content: MatchTicketCardView(model: model)
                .padding(20)
                .background(outerBg)
                .frame(width: 390)
        )
        renderer.scale = 3
        return renderer.uiImage
    }

    // MARK: - 유틸

    private func loadURLOptional(_ urlString: String?) async -> UIImage? {
        guard let urlString else { return nil }
        return await loadImage(from: urlString)
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s
    }
}

// MARK: - Preview

#Preview("공유 시트 - Pistons (NBA)") {
    let folder = SportsFanFolder(name: "Detroit Pistons", sportType: .basketball)
    folder.teamNickname = "Pistons"
    folder.teamColor = "003EA0"
    folder.teamAlternateColor = "C8102E"
    folder.leagueCode = "NBA"

    let match = SportsModel(
        title: "Pistons vs Lakers Game 1",
        opponentTeam: "LA Lakers",
        myTeamScore: 87,
        opponentScore: 75,
        matchResult: .win,
        matchStatus: .completed,
        isHomeGame: false,
        date: Date(),
        location: "Little Caesars Arena",
        orderIndex: 0
    )
    match.folder = folder
    return SportsTicketShareView(match: match)
}

#Preview("공유 시트 - 49ers (NFL)") {
    let folder = SportsFanFolder(name: "San Francisco 49ers", sportType: .americanFootball)
    folder.teamNickname = "49ers"
    folder.teamColor = "AA0000"
    folder.teamAlternateColor = "B3995D"
    folder.leagueCode = "NFL"

    let match = SportsModel(
        title: "49ers vs Chiefs - Super Bowl",
        opponentTeam: "Kansas City Chiefs",
        myTeamScore: 31,
        opponentScore: 20,
        matchResult: .win,
        matchStatus: .completed,
        isHomeGame: true,
        date: Date(),
        location: "Levi's Stadium",
        orderIndex: 0
    )
    match.folder = folder
    return SportsTicketShareView(match: match)
}

#Preview("공유 시트 - LG 트윈스 (KBO, 선수 없음)") {
    let folder = SportsFanFolder(name: "LG 트윈스", sportType: .baseball)
    folder.teamNickname = "트윈스"
    folder.teamColor = "C30038"
    folder.leagueCode = "KBO"

    let match = SportsModel(
        title: "LG vs 두산 잠실 직관",
        opponentTeam: "두산 베어스",
        myTeamScore: 5,
        opponentScore: 2,
        matchResult: .win,
        matchStatus: .completed,
        isHomeGame: true,
        date: Date(),
        location: "잠실 야구장",
        orderIndex: 2
    )
    match.folder = folder
    return SportsTicketShareView(match: match)
}
