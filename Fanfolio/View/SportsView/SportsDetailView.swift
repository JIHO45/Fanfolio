//
//  SportsDetailView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import Kingfisher

struct SportsDetailView: View {
    let match: SportsModel
    
    @State private var showingEditSheet = false
    @State private var showingTicketShareSheet = false
    @State private var showingQRZoomCover = false
    @State private var selectedSavedTicket: SavedTicket?
    
    // MARK: - 선수단 & 즐겨찾기 상태
    @State private var squadPlayers: [PlayerInfo] = []
    @State private var isLoadingSquad = false
    @State private var favorites = FavoritePlayersManager.shared

    /// KBO 상대팀 로고 URL - Firestore 캐시에서 팀 이름으로 동적 조회 (ESPN처럼 SwiftData 무관)
    @State private var kboOpponentLogoURL: String? = nil

    // MARK: - 라인업 포지션 필터 상태
    @State private var selectedGroup: PositionGroup? = nil
    @State private var selectedNFLPhase: NFLPhase? = nil
    
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.autoupdatingCurrent
        fmt.setLocalizedDateFormatFromTemplate("yyyyMMMdEEE")
        return fmt
    }()
    
    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.autoupdatingCurrent
        fmt.timeStyle = .short
        return fmt
    }()
    
    private var sportType: SportType {
        match.folder?.sportType ?? .other
    }
    
    private var team1Name: String { match.team1Display }
    private var team2Name: String { match.team2Display }
    private var team1NameUI: String {
        KBOTeamLogoAsset.uiDisplayName(forTeamName: team1Name, leagueCode: match.folder?.leagueCode)
    }
    private var team2NameUI: String {
        KBOTeamLogoAsset.uiDisplayName(forTeamName: team2Name, leagueCode: match.folder?.leagueCode)
    }
    private var savedTickets: [SavedTicket] {
        match.savedTickets.sorted { $0.createdAt > $1.createdAt }
    }
    
    private var isKBO: Bool {
        (match.folder?.leagueCode ?? "") == "KBO"
    }

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
        let t = ESPNTeamsLoader.team(name: match.opponentTeam, leagueCode: match.folder?.leagueCode)
        // fake ID(kbo_N 등)는 Wikipedia SVG라 로딩 안 됨 → nil 처리해서 opponentLogoURL로 폴백
        guard let t, !t.id.isESPNFakeID else { return nil }
        return t
    }

    /// 상대팀 로고 URL: ESPN JSON → Firestore 동적 조회 → SwiftData 저장값 순으로 우선
    private var resolvedOpponentLogoURL: String? {
        team2Data?.logo_url ?? kboOpponentLogoURL ?? match.opponentLogoURL
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

                // 완료된 경기: 공유 버튼
                if match.matchStatus == .completed {
                    shareCallToAction
                        .padding(.horizontal)
                }
                
                if match.matchStatus == .completed, !savedTickets.isEmpty {
                    savedTicketSection
                        .padding(.horizontal)
                }
                
                // 완료된 경기: 선수 하이라이트 섹션
                if match.matchStatus == .completed {
                    playerHighlightSection
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
                    Text(String(localized: "common.action.edit", defaultValue: "편집"))
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditSportsMatchView(match: match)
        }
        .sheet(isPresented: $showingTicketShareSheet) {
            SportsTicketShareView(match: match)
        }
        .fullScreenCover(item: $selectedSavedTicket) { ticket in
            TicketImageViewerView(ticket: ticket)
        }
        // 예정→완료 전환·폴더(리그/팀) 변경 시 로스터를 다시 로드
        .task(id: match.fanfolioMatchSquadTaskToken) {
            await loadSquadIfNeeded()
        }
        .task(id: match.externalEventID) {
            await fetchKBOOpponentLogoIfNeeded()
        }
    }
    
    // MARK: - 선수단 로드
    // 미국 스포츠: ESPN 팀 로스터 → ESPN CDN 고화질 이미지
    // KBO·유럽 등: API-Sports 팀 로스터

    /// KBO 경기의 상대팀 로고를 Firestore 캐시에서 팀 이름으로 조회합니다.
    /// ESPN이 정적 JSON을 사용하듯, SwiftData 저장 여부와 무관하게 항상 로고를 가져옵니다.
    private func fetchKBOOpponentLogoIfNeeded() async {
        guard (match.folder?.leagueCode ?? "") == "KBO" else { return }
        guard team2Data == nil else { return } // ESPN JSON이 이미 있으면 불필요
        let name = match.opponentTeam
        guard !name.isEmpty else { return }
        let url = await KBOFirestoreService.shared.resolveTeamLogoURL(forTeamName: name)
        if let url, !url.isEmpty {
            await MainActor.run { kboOpponentLogoURL = url }
        }
    }

    private func loadSquadIfNeeded() async {
        guard match.matchStatus == .completed,
              squadPlayers.isEmpty,
              !isLoadingSquad else { return }

        isLoadingSquad = true
        defer { isLoadingSquad = false }

        let folder   = match.folder
        let teamName = folder?.name ?? match.team1Display
        let espnTeam = ESPNTeamsLoader.team(name: teamName, leagueCode: folder?.leagueCode)

        squadPlayers = await PlayerMatchingService.shared.fetchSquadWithCutouts(
            sportType: folder?.sportType ?? .other,
            teamName: teamName,
            espnTeamID: espnTeam?.id,
            leagueCode: folder?.leagueCode,
            apiSportsTeamID: folder?.apiSportsTeamID
        )
    }
    
    // MARK: - 상태 배너 (예정/진행중)
    private var statusBanner: some View {
        HStack {
            Image(systemName: match.matchStatus.iconName)
                .foregroundStyle(match.matchStatus == .live ? .white : match.matchStatus.color)
                .symbolEffect(.pulse, isActive: match.matchStatus == .live)
            
            Text(match.matchStatus.displayName)
                .font(.subheadline.bold())
                .foregroundStyle(match.matchStatus == .live ? .white : match.matchStatus.color)
            
            Spacer()
            
            Text(String(localized: "sports.detail.editBanner.hint", defaultValue: "편집 버튼을 눌러 경기 결과를 입력하세요"))
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
                    Text(sportType.displayName)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())
                
                // 팀 매치업 — 로고 + 대형 타이포
                VStack(spacing: 8) {
                    let team1AssetName = isKBO ? KBOTeamLogoAsset.imageName(forTeamName: team1Name) : nil
                    let team1LogoURL = match.hasFavoriteTeam ? match.folder?.teamLogoUrl : team1Data?.logo_url
                    if team1AssetName != nil || (team1LogoURL != nil && !(team1LogoURL?.isEmpty ?? true)) {
                        ZStack {
                            LinearGradient(
                                colors: match.hasFavoriteTeam ? team1Gradient : (team1Data?.gradientColors ?? [.gray, .gray.opacity(0.7)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            if let assetName = team1AssetName {
                                Image(assetName)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(12)
                            } else if let url = team1LogoURL, !url.isEmpty {
                                KFImage.url(URL(string: url))
                                    .placeholder { ProgressView().tint(.white) }
                                    .onFailureView {
                                        Image(systemName: "photo")
                                            .font(.title2)
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                    .resizable()
                                    .scaledToFit()
                                    .padding(12)
                            }
                        }
                        .frame(width: 64, height: 64)
                    }
                    Text(team1NameUI)
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
                            Text(verbatim: "\(match.myTeamScore)")
                                .font(.system(size: 52, weight: .heavy, design: .rounded))
                                .foregroundStyle(
                                    match.matchResult == .win ? match.matchResult.color : .primary
                                )
                            
                            Text(":")
                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                .foregroundStyle(.quaternary)
                            
                            Text(verbatim: "\(match.opponentScore)")
                                .font(.system(size: 52, weight: .heavy, design: .rounded))
                                .foregroundStyle(
                                    match.matchResult == .loss ? match.matchResult.color : .primary
                                )
                        }
                        
                        Text(match.matchResult.displayName)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .background(match.matchResult.color)
                            .clipShape(Capsule())
                    }
                } else {
                    Text(String(localized: "sports.card.vs", defaultValue: "VS"))
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(.quaternary)
                }
                
                VStack(spacing: 8) {
                    let team2AssetName = isKBO ? KBOTeamLogoAsset.imageName(forTeamName: team2Name) : nil
                    let oppLogoURL = resolvedOpponentLogoURL
                    if team2AssetName != nil || (oppLogoURL != nil && !(oppLogoURL?.isEmpty ?? true)) {
                        ZStack {
                            LinearGradient(
                                colors: team2Data?.gradientColors ?? [.gray, .gray.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            if let assetName = team2AssetName {
                                Image(assetName)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(12)
                            } else if let logoURL = oppLogoURL, !logoURL.isEmpty {
                                KFImage.url(URL(string: logoURL))
                                    .placeholder { ProgressView().tint(.white) }
                                    .onFailureView {
                                        Image(systemName: "photo")
                                            .font(.title2)
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                    .resizable()
                                    .scaledToFit()
                                    .padding(12)
                            }
                        }
                        .frame(width: 64, height: 64)
                    }
                    Text(team2NameUI)
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
                            Text(String(localized: "ticket.detail.qrRow", defaultValue: "티켓 · QR코드"))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(localized: "ticket.detail.tapToEnlarge", defaultValue: "탭하여 확대"))
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
                
                // 직관 사진 갤러리 (photoPaths 우선, 레거시는 photosData)
                let photoPaths = match.photoPaths ?? []
                let legacyPhotos = match.photosData ?? []
                let hasPhotos = !photoPaths.isEmpty || !legacyPhotos.isEmpty
                if hasPhotos {
                    let count = photoPaths.isEmpty ? legacyPhotos.count : photoPaths.count
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(bandColor)
                            Text(String(localized: "ticket.section.attendancePhotos", defaultValue: "직관 사진"))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: String(localized: "ticket.photoCount", defaultValue: "%lld장"), locale: .autoupdatingCurrent, Int64(count)))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                if !photoPaths.isEmpty {
                                    ForEach(photoPaths.indices, id: \.self) { index in
                                        if let uiImage = ArchivePhotoStore.loadImage(path: photoPaths[index]) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 140, height: 140)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                    }
                                } else {
                                    ForEach(legacyPhotos.indices, id: \.self) { index in
                                        if let uiImage = UIImage(data: legacyPhotos[index]) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 140, height: 140)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
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
                            Text(String(localized: "ticket.section.memo", defaultValue: "메모"))
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
                    Text(String(localized: "ticket.brand.name", defaultValue: "Fanfolio"))
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
        let folderKey = match.folder?.folderID.uuidString ?? "__no_folder__"
        let favoriteIDs = favorites.favoriteIDs(inFolder: folderKey)
        let vipPlayers = squadPlayers.filter { favoriteIDs.contains("\($0.id)") }
        let restPlayers = squadPlayers.filter { !favoriteIDs.contains("\($0.id)") }
        let sportType = match.folder?.sportType ?? .other
        
        if isLoadingSquad {
            // 로딩 스켈레톤
            VStack(alignment: .leading, spacing: 14) {
                Label(String(localized: "sports.detail.playerHighlights.loading", defaultValue: "선수 하이라이트"), systemImage: "star.fill")
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
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .groupedCardOutline(cornerRadius: 20)
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
                Label(String(localized: "sports.detail.vip.headline", defaultValue: "최애 선수 활약"), systemImage: "star.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Text(String(localized: "sports.detail.vip.badge", defaultValue: "V.I.P."))
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
                    folder: match.folder
                )) {
                    vipPlayerCard(player: player)
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
    
    private func vipPlayerCard(player: PlayerInfo) -> some View {
        let teamColor = Color.from(hex: match.folder?.teamColor) ?? bandColor
        let gradients = match.folder?.gradientColors ?? [.gray, .gray.opacity(0.7)]
        
        return HStack(spacing: 14) {
            // 누끼 사진 (크게)
            PlayerImageView(
                imageURL: player.imageURL,
                fallbackTeamLogoURL: match.folder?.teamLogoUrl,
                fallbackGradient: gradients,
                size: 60,
                playerName: player.name,
                jerseyNumber: player.number,
                sportType: match.folder?.sportType
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
                        Text(verbatim: "#\(num)")
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
        GroupedPlayerListCard(
            title: String(localized: "sports.detail.lineup.title", defaultValue: "팀 라인업"),
            players: players,
            sportType: sportType,
            teamColorHex: match.folder?.teamColor,
            fallbackTeamLogoURL: match.folder?.teamLogoUrl,
            fallbackGradient: match.folder?.gradientColors ?? [.gray, .gray.opacity(0.7)],
            favoriteFolderKey: match.folder?.folderID.uuidString ?? "__no_folder__",
            selectedGroup: $selectedGroup,
            selectedNFLPhase: $selectedNFLPhase
        ) { player in
            PlayerDetailView(
                player: player,
                folder: match.folder
            )
        }
    }

    // MARK: - 공유 CTA 버튼
    private var shareCallToAction: some View {
        Button {
            showingTicketShareSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                Text(String(localized: "sports.detail.shareTicketImage", defaultValue: "티켓 이미지 공유하기"))
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(bandColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    private var savedTicketSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "sports.detail.savedTickets", defaultValue: "저장한 티켓"), systemImage: "ticket.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: String(localized: "ticket.photoCount", defaultValue: "%lld장"), locale: .autoupdatingCurrent, Int64(savedTickets.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(savedTickets) { ticket in
                        SavedTicketThumbnailView(ticket: ticket)
                            .frame(width: 190)
                            .onTapGesture {
                                selectedSavedTicket = ticket
                            }
                    }
                }
                .padding(.vertical, 2)
            }
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
