//
//  SportsDetailView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import SwiftData

struct SportsDetailView: View {
    let match: SportsModel
    
    @State private var showingEditSheet = false
    @State private var showingTicketShareSheet = false
    @State private var showingQRZoomCover = false
    
    // MARK: - 선수단 & 즐겨찾기 상태
    @State private var squadPlayers: [PlayerInfo] = []
    @State private var isLoadingSquad = false
    @State private var showAllLineup = false
    @State private var favorites = FavoritePlayersManager.shared
    
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy년 M월 d일 (E)"
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt
    }()
    
    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt
    }()
    
    private var sportType: SportType {
        match.folder?.sportType ?? .other
    }
    
    private var team1Name: String { match.team1Display }
    private var team2Name: String { match.team2Display }
    
    private var bandColor: Color {
        match.matchStatus == .completed
            ? match.matchResult.color
            : match.matchStatus.color
    }
    
    private var team1Gradient: [Color] {
        match.folder?.gradientColors ?? [.gray, .gray.opacity(0.7)]
    }
    
    private var team1Data: ESPNTeam? {
        ESPNTeamsLoader.team(name: match.team1Display, leagueCode: match.folder?.leagueCode)
    }
    private var team2Data: ESPNTeam? {
        ESPNTeamsLoader.team(name: match.opponentTeam, leagueCode: match.folder?.leagueCode)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 경기 예정/진행중 배너
                if match.matchStatus != .completed {
                    statusBanner
                        .padding(.horizontal)
                }
                
                // 메인 티켓 카드
                ticketCard
                    .padding(.horizontal)
                
                // 완료된 경기: 선수 하이라이트 섹션
                if match.matchStatus == .completed {
                    playerHighlightSection
                        .padding(.horizontal)
                }
                
                // 완료된 경기: 공유 버튼
                if match.matchStatus == .completed {
                    shareCallToAction
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(match.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditSheet = true
                } label: {
                    Text("편집")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditSportsMatchView(match: match)
        }
        .sheet(isPresented: $showingTicketShareSheet) {
            SportsTicketShareView(match: match)
        }
        .task {
            await loadSquadIfNeeded()
        }
    }
    
    // MARK: - 선수단 로드
    
    private func loadSquadIfNeeded() async {
        guard match.matchStatus == .completed,
              squadPlayers.isEmpty,
              !isLoadingSquad else { return }
        
        isLoadingSquad = true
        defer { isLoadingSquad = false }
        
        let teamName = match.folder?.name ?? match.team1Display
        do {
            let players = try await TheSportsDBService.shared.fetchSquadByTeamName(teamName)
            squadPlayers = players
        } catch {
            // 로드 실패 시 빈 배열 유지 (UI에서 조용히 처리)
        }
    }
    
    // MARK: - 상태 배너 (예정/진행중)
    private var statusBanner: some View {
        HStack {
            Image(systemName: match.matchStatus.iconName)
                .foregroundStyle(match.matchStatus == .live ? .white : match.matchStatus.color)
                .symbolEffect(.pulse, isActive: match.matchStatus == .live)
            
            Text(match.matchStatus.rawValue)
                .font(.subheadline.bold())
                .foregroundStyle(match.matchStatus == .live ? .white : match.matchStatus.color)
            
            Spacer()
            
            Text("편집 버튼을 눌러 경기 결과를 입력하세요")
                .font(.caption)
                .foregroundStyle(match.matchStatus == .live ? .white.opacity(0.8) : .secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(match.matchStatus == .live
                      ? match.matchStatus.color
                      : match.matchStatus.color.opacity(0.1))
        )
    }
    
    // MARK: - 티켓 카드
    private var ticketCard: some View {
        VStack(spacing: 0) {
            // ── 상단 컬러 밴드 ──
            bandColor
                .frame(height: 10)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 20, topTrailingRadius: 20
                ))
            
            // ── 상단 영역: 팀 브랜딩 + 점수 ──
            VStack(spacing: 20) {
                // 종목 배지
                HStack(spacing: 6) {
                    Image(systemName: sportType.iconName)
                        .font(.caption)
                    Text(sportType.rawValue)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())
                
                // 팀 매치업 — 로고 + 대형 타이포
                VStack(spacing: 8) {
                    if let url = match.hasFavoriteTeam ? match.folder?.teamLogoUrl : team1Data?.logo_url, !url.isEmpty {
                        ZStack {
                            LinearGradient(
                                colors: match.hasFavoriteTeam ? team1Gradient : (team1Data?.gradientColors ?? [.gray, .gray.opacity(0.7)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            AsyncImage(url: URL(string: url)) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFit().padding(12)
                                case .failure:
                                    Image(systemName: "photo")
                                        .font(.title2)
                                        .foregroundStyle(.white.opacity(0.8))
                                case .empty:
                                    ProgressView().tint(.white)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                        .frame(width: 64, height: 64)
                    }
                    Text(team1Name)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(match.isHomeGame ? "HOME" : "AWAY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(2)
                }
                
                // 점수 또는 VS
                if match.matchStatus == .completed {
                    VStack(spacing: 10) {
                        HStack(spacing: 16) {
                            Text("\(match.myTeamScore)")
                                .font(.system(size: 52, weight: .heavy, design: .rounded))
                                .foregroundStyle(
                                    match.matchResult == .win ? match.matchResult.color : .primary
                                )
                            
                            Text(":")
                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                .foregroundStyle(.quaternary)
                            
                            Text("\(match.opponentScore)")
                                .font(.system(size: 52, weight: .heavy, design: .rounded))
                                .foregroundStyle(
                                    match.matchResult == .loss ? match.matchResult.color : .primary
                                )
                        }
                        
                        Text(match.matchResult.rawValue)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .background(match.matchResult.color)
                            .clipShape(Capsule())
                    }
                } else {
                    Text("VS")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(.quaternary)
                }
                
                VStack(spacing: 8) {
                    if let opp = team2Data {
                        ZStack {
                            LinearGradient(
                                colors: opp.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            AsyncImage(url: URL(string: opp.logo_url)) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFit().padding(12)
                                case .failure:
                                    Image(systemName: "photo")
                                        .font(.title2)
                                        .foregroundStyle(.white.opacity(0.8))
                                case .empty:
                                    ProgressView().tint(.white)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                        .frame(width: 64, height: 64)
                    }
                    Text(team2Name)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(match.isHomeGame ? "AWAY" : "HOME")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
            
            // ── 절취선 ──
            ticketDivider
            
            // ── 하단 영역: 정보 ──
            VStack(alignment: .leading, spacing: 18) {
                // 날짜 + 장소
                if match.date != nil || match.location != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        if let date = match.date {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar")
                                    .frame(width: 20)
                                    .foregroundStyle(bandColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.dateFormatter.string(from: date))
                                        .font(.subheadline.weight(.medium))
                                    Text(Self.timeFormatter.string(from: date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let location = match.location {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.and.ellipse")
                                    .frame(width: 20)
                                    .foregroundStyle(bandColor)
                                Text(location)
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                    }
                }
                
                // QR / 티켓 이미지 (탭 시 확대)
                if let data = match.qrCodeImageData,
                   let uiImage = UIImage(data: data) {
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: "qrcode")
                                .foregroundStyle(bandColor)
                            Text("티켓 · QR코드")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("탭하여 확대")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        
                        Button {
                            showingQRZoomCover = true
                        } label: {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                    .fullScreenCover(isPresented: $showingQRZoomCover) {
                        QRZoomView(imageData: data)
                    }
                }
                
                // 직관 사진 갤러리
                if let photos = match.photosData, !photos.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(bandColor)
                            Text("직관 사진")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(photos.count)장")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(photos.indices, id: \.self) { index in
                                    if let uiImage = UIImage(data: photos[index]) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 140, height: 140)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, -20)
                        .padding(.leading, 20)
                    }
                }
                
                // 메모
                if let memo = match.memo, !memo.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "quote.opening")
                                .foregroundStyle(bandColor)
                            Text("메모")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(memo)
                            .font(.body)
                            .italic()
                            .foregroundStyle(.primary.opacity(0.8))
                            .padding(.leading, 4)
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
            .clipShape(UnevenRoundedRectangle(
                bottomLeadingRadius: 20, bottomTrailingRadius: 20
            ))
        }
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 6)
    }
    
    // MARK: - 절취선 (점선 + 양쪽 반원 노치)
    private var ticketDivider: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
                .frame(height: 28)
            
            ShareTicketDashLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(.secondary.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 28)
            
            HStack {
                Circle()
                    .fill(Color(uiColor: .systemGroupedBackground))
                    .frame(width: 28, height: 28)
                    .offset(x: -14)
                Spacer()
                Circle()
                    .fill(Color(uiColor: .systemGroupedBackground))
                    .frame(width: 28, height: 28)
                    .offset(x: 14)
            }
        }
        .frame(height: 28)
        .clipped()
    }
    
    // MARK: - 선수 하이라이트 섹션 (V.I.P. + 전체 라인업)
    
    @ViewBuilder
    private var playerHighlightSection: some View {
        let favoriteIDs = favorites.favoriteIDs
        let vipPlayers = squadPlayers.filter { favoriteIDs.contains("\($0.id)") }
        let restPlayers = squadPlayers.filter { !favoriteIDs.contains("\($0.id)") }
        let sportType = match.folder?.sportType ?? .other
        
        if isLoadingSquad {
            // 로딩 스켈레톤
            VStack(alignment: .leading, spacing: 14) {
                Label("선수 하이라이트", systemImage: "star.fill")
                    .font(.subheadline.bold())
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: 120, height: 12)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: 60, height: 10)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        } else if !squadPlayers.isEmpty {
            VStack(spacing: 12) {
                // V.I.P. 섹션 (즐겨찾기 선수)
                if !vipPlayers.isEmpty {
                    vipSection(players: vipPlayers, sportType: sportType)
                }
                
                // 전체 라인업 섹션
                if !restPlayers.isEmpty || vipPlayers.isEmpty {
                    lineupSection(players: restPlayers.isEmpty ? squadPlayers : restPlayers, sportType: sportType)
                }
            }
        }
        // squadPlayers가 비어있고 로딩도 아니면 아무것도 표시 안 함
    }
    
    // MARK: - V.I.P. 카드 섹션
    
    private func vipSection(players: [PlayerInfo], sportType: SportType) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("최애 선수 활약", systemImage: "star.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Text("V.I.P.")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
            
            ForEach(players) { player in
                NavigationLink(destination: PlayerDetailView(
                    player: player,
                    sportType: sportType,
                    folder: match.folder
                )) {
                    vipPlayerCard(player: player, sportType: sportType)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.05),
                            Color(uiColor: .secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func vipPlayerCard(player: PlayerInfo, sportType: SportType) -> some View {
        let teamColor = Color.from(hex: match.folder?.teamColor) ?? bandColor
        let gradients = match.folder?.gradientColors ?? [.gray, .gray.opacity(0.7)]
        let highlights = player.stats?.highlights(for: sportType) ?? []
        
        return HStack(spacing: 14) {
            // 누끼 사진 (크게)
            PlayerImageView(
                cutoutURL: player.cutoutImageURL,
                photoURL: player.photoURL,
                fallbackTeamLogoURL: match.folder?.teamLogoUrl,
                fallbackGradient: gradients,
                size: 60
            )
            
            // 이름 + 포지션
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(player.name)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    if let num = player.number {
                        Text("#\(num)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(teamColor.opacity(0.8)))
                    }
                }
                if let pos = player.position {
                    Text(pos)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // 스탯 (최대 2개)
            if !highlights.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(highlights.prefix(2), id: \.0) { label, value in
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(value)
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundStyle(teamColor)
                                .monospacedDigit()
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.red.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.red.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - 전체 라인업 섹션
    
    private func lineupSection(players: [PlayerInfo], sportType: SportType) -> some View {
        let displayed = showAllLineup ? players : Array(players.prefix(5))
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("팀 라인업", systemImage: "person.3.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(players.count)명")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ForEach(displayed) { player in
                NavigationLink(destination: PlayerDetailView(
                    player: player,
                    sportType: sportType,
                    folder: match.folder
                )) {
                    lineupPlayerRow(player: player, sportType: sportType)
                }
                .buttonStyle(.plain)
                
                if player.id != displayed.last?.id {
                    Divider()
                }
            }
            
            if players.count > 5 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAllLineup.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(showAllLineup ? "접기" : "전체 \(players.count)명 보기")
                            .font(.caption.bold())
                        Image(systemName: showAllLineup ? "chevron.up" : "chevron.down")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    private func lineupPlayerRow(player: PlayerInfo, sportType: SportType) -> some View {
        let isFav = favorites.isFavorite("\(player.id)")
        let gradients = match.folder?.gradientColors ?? [.gray, .gray.opacity(0.7)]
        
        return HStack(spacing: 12) {
            PlayerImageView(
                cutoutURL: player.cutoutImageURL,
                photoURL: player.photoURL,
                fallbackTeamLogoURL: match.folder?.teamLogoUrl,
                fallbackGradient: gradients
            )
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(player.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let num = player.number {
                        Text("#\(num)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill((Color.from(hex: match.folder?.teamColor) ?? .blue).opacity(0.8))
                            )
                    }
                    if isFav {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                if let pos = player.position {
                    Text(pos)
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
    
    // MARK: - 공유 CTA 버튼
    private var shareCallToAction: some View {
        Button {
            showingTicketShareSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                Text("티켓 이미지 공유하기")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(bandColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
}

// MARK: - Previews

#Preview("완료 - 승리") {
    let folder = SportsFanFolder(name: "LG 트윈스", sportType: .baseball)
    let match = SportsModel(
        title: "LG vs 두산 잠실 직관",
        opponentTeam: "두산 베어스",
        myTeamScore: 5,
        opponentScore: 2,
        matchResult: .win,
        matchStatus: .completed,
        date: Date(),
        location: "잠실 야구장",
        memo: "오지환 끝내기 홈런! 역전승으로 짜릿한 경기였다."
    )
    match.folder = folder
    return NavigationStack {
        SportsDetailView(match: match)
    }
}

#Preview("예정") {
    let folder = SportsFanFolder(name: "FC서울", sportType: .soccer)
    let match = SportsModel(
        title: "FC서울 vs 수원",
        opponentTeam: "수원 삼성",
        matchStatus: .upcoming,
        date: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
        location: "상암 월드컵 경기장"
    )
    match.folder = folder
    return NavigationStack {
        SportsDetailView(match: match)
    }
}
