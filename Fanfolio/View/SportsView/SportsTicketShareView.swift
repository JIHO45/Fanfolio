//
//  SportsTicketShareView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/24/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import Vision
import CoreImage

// MARK: - 스포츠 티켓 공유 뷰

struct SportsTicketShareView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let match: SportsModel

    // MARK: - 상태

    @State private var photoVM = TicketPhotoViewModel()
    @State private var showingActivityShareSheet = false
    @State private var team1LogoImg: UIImage?
    @State private var team2LogoImg: UIImage?

    // 디자인 스타일 + 커스텀 텍스트
    @State private var designStyle: TicketDesignStyle = .standard
    @State private var customOverlayText: String = ""

    // 공유 렌더링
    @State private var shareImage: UIImage?
    @State private var isRendering = false
    @State private var isSavingToGallery = false

    // 하단 컨트롤 높이 (토스트 위치 계산용)
    @State private var controlsHeight: CGFloat = 0

    // 디자인 패널 펼침/접힘
    @State private var isDesignExpanded: Bool = true

    // MARK: - ESPN 팀 데이터

    private var team1Data: ESPNTeam? {
        ESPNTeamsLoader.team(name: match.team1Display, leagueCode: match.folder?.leagueCode)
    }
    private var team2Data: ESPNTeam? {
        ESPNTeamsLoader.team(name: match.opponentTeam, leagueCode: match.folder?.leagueCode)
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                livePreviewSection(
                    containerWidth: geometry.size.width,
                    containerHeight: geometry.size.height
                )
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.08).ignoresSafeArea())
            .navigationTitle("티켓 이미지 공유")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if photoVM.userPhoto != nil {
                        Button { photoVM.clearPhoto() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white.opacity(0.9), .white.opacity(0.2))
                                .font(.system(size: 18))
                        }
                    }
                    // Toolbar 안에 PhotosPicker를 직접 쓰면 사진첩 닫힐 때
                    // 부모 시트까지 같이 닫히는 iOS 버그가 있어 일반 Button으로 대체
                    Button { photoVM.showingPhotoPicker = true } label: {
                        Image(systemName: photoVM.userPhoto == nil ? "photo.badge.plus" : "photo.fill")
                            .foregroundStyle(.white)
                            .font(.system(size: 18))
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                overlayControlsSection
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { controlsHeight = geo.size.height }
                                .onChange(of: geo.size.height) { _, h in controlsHeight = h }
                        }
                    )
            }
            .photosPicker(
                isPresented: $photoVM.showingPhotoPicker,
                selection: $photoVM.userPhotoItem,
                matching: .images
            )
            .onChange(of: photoVM.userPhotoItem) { _, newItem in
                guard let item = newItem else { return }
                Task { @MainActor in await photoVM.loadPhoto(from: item) }
            }
            .task(id: match.fanfolioTicketShareStaticToken) {
                await loadStaticImages()
            }
            .onDisappear {
                shareImage = nil
            }
            .sheet(isPresented: $showingActivityShareSheet) {
                if let shareImage {
                    FanfolioShareSheet(items: [shareImage])
                }
            }
            .alert("저장 실패", isPresented: Binding(
                get: { photoVM.saveErrorMessage != nil },
                set: { if !$0 { photoVM.saveErrorMessage = nil } }
            )) {
                Button("확인", role: .cancel) { photoVM.saveErrorMessage = nil }
            } message: {
                Text(photoVM.saveErrorMessage ?? "")
            }
            .overlay(alignment: .bottom) {
                if let saveToastMessage = photoVM.saveToastMessage {
                    Text(saveToastMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.8))
                        .clipShape(Capsule())
                        .padding(.bottom, controlsHeight + 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - 라이브 프리뷰

    private func livePreviewSection(containerWidth: CGFloat, containerHeight: CGFloat) -> some View {
        let displayW = max(containerWidth - 40, 1)
        let scaleByWidth  = displayW / MatchTicketCardView.designWidth
        let scaleByHeight = max(containerHeight - 24, 1) / MatchTicketCardView.designHeight
        let previewScale  = min(scaleByWidth, scaleByHeight)
        let cardW = MatchTicketCardView.designWidth * previewScale
        let cardH = MatchTicketCardView.designHeight * previewScale

        return VStack {
            Spacer()
            ZStack {
                MatchTicketCardView(model: previewCardModel)
                    .frame(
                        width: MatchTicketCardView.designWidth,
                        height: MatchTicketCardView.designHeight
                    )
                    .scaleEffect(previewScale, anchor: .center)
                    .frame(width: cardW, height: cardH)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                    // 드래그 제스처 — 사진 위치 이동 (사진 없으면 무시)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                guard photoVM.userPhoto != nil else { return }
                                let dx = value.translation.width / previewScale
                                let dy = value.translation.height / previewScale
                                photoVM.photoOffset = photoVM.clampPhotoOffset(
                                    CGSize(
                                        width:  photoVM.lastPhotoOffset.width  + dx,
                                        height: photoVM.lastPhotoOffset.height + dy
                                    ),
                                    designWidth: MatchTicketCardView.designWidth,
                                    designHeight: MatchTicketCardView.designHeight
                                )
                            }
                            .onEnded { _ in photoVM.lastPhotoOffset = photoVM.photoOffset }
                    )
                    // 핀치 제스처 — 사진 확대/축소
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                guard photoVM.userPhoto != nil else { return }
                                photoVM.photoScale = max(1.0, min(4.0, photoVM.lastPhotoScale * value))
                                photoVM.photoOffset = photoVM.clampPhotoOffset(
                                    photoVM.photoOffset,
                                    designWidth: MatchTicketCardView.designWidth,
                                    designHeight: MatchTicketCardView.designHeight
                                )
                            }
                            .onEnded { _ in photoVM.lastPhotoScale = photoVM.photoScale }
                    )

                TicketPhotoOverlayView(
                    isExtractingCutout: photoVM.isExtractingCutout,
                    hasPhoto: photoVM.userPhoto != nil,
                    cardWidth: cardW,
                    cardHeight: cardH
                )
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 현재 카드 모델 조립

    private var previewCardModel: MatchTicketModel {
        makeCardModel(showsBrandingWatermark: true)
    }

    private func makeCardModel(showsBrandingWatermark: Bool) -> MatchTicketModel {
        MatchTicketModel(
            teamName: match.team1Display,
            opponentTeam: match.team2Display,
            myTeamScore: match.myTeamScore,
            opponentScore: match.opponentScore,
            matchResult: match.matchResult,
            matchStatus: match.matchStatus,
            sportType: match.folder?.sportType ?? .other,
            teamColor: resolvedTeamColor,
            teamLogoImage: team1LogoImg,
            opponentLogoImage: team2LogoImg,
            userPhoto: photoVM.userPhoto,
            userPhotoCutout: photoVM.userPhotoCutout,
            photoOffset: photoVM.photoOffset,
            photoScale: photoVM.photoScale,
            date: match.date,
            leagueCode: match.folder?.leagueCode,
            designStyle: designStyle,
            customOverlayText: designStyle == .customText
                ? (customOverlayText.isEmpty ? nil : customOverlayText)
                : nil,
            showsBrandingWatermark: showsBrandingWatermark
        )
    }

    private var resolvedTeamColor: Color {
        if match.hasFavoriteTeam, let hex = match.folder?.teamColor {
            return Color.from(hex: hex) ?? .red
        }
        return team1Data.flatMap { Color.from(hex: $0.color) } ?? .red
    }

    // MARK: - 하단 컨트롤 패널 (디자인 캐러셀 + 저장/공유 버튼)

    private var overlayControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 디자인 헤더 — 탭으로 펼침/접힘 토글
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    isDesignExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("디자인")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    // 현재 선택된 스타일 레이블 (접혔을 때 힌트)
                    if !isDesignExpanded {
                        HStack(spacing: 0) {
                                Text("· ")
                                Text(designStyle.label)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .transition(.opacity)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .rotationEffect(isDesignExpanded ? .degrees(0) : .degrees(-90))
                }
            }
            .buttonStyle(.plain)

            // 접히면 캐러셀 + customText 입력 숨김
            if isDesignExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(TicketDesignStyle.allCases, id: \.self) { style in
                            designStyleItem(style: style)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))

                if designStyle == .customText {
                    customTextInputSection
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            actionButtonsSection
        }
        .padding(14)
        .background(.black.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - 디자인 스타일 아이템

    private func designStyleItem(style: TicketDesignStyle) -> some View {
        let isSelected = designStyle == style
        let thumbW: CGFloat = 52
        let thumbH: CGFloat = 92

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                designStyle = style
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(resolvedTeamColor.opacity(0.85))

                    switch style {
                    case .standard:
                        VStack(spacing: 2) {
                            Text("WIN")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.top, 10)
                            Spacer()
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.white.opacity(0.85))
                                .frame(height: 16)
                                .padding(.horizontal, 5)
                                .padding(.bottom, 5)
                        }
                    case .rotatedText:
                        ZStack {
                            HStack(spacing: 0) {
                                Text("WIN")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(.white)
                                    .rotationEffect(.degrees(-90))
                                    .padding(.leading, 4)
                                Spacer()
                            }
                            VStack {
                                Spacer()
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.white.opacity(0.85))
                                    .frame(height: 16)
                                    .padding(.horizontal, 5)
                                    .padding(.bottom, 5)
                            }
                        }
                    case .customText:
                        VStack(spacing: 2) {
                            Image(systemName: "text.cursor")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.top, 16)
                            Spacer()
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.white.opacity(0.85))
                                .frame(height: 16)
                                .padding(.horizontal, 5)
                                .padding(.bottom, 5)
                        }
                    }
                }
                .frame(width: thumbW, height: thumbH)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: isSelected ? .white.opacity(0.25) : .clear, radius: 6)
                .scaleEffect(isSelected ? 1.05 : 1.0)

                Text(style.label)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.45))
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: designStyle)
    }

    // MARK: - 커스텀 텍스트 입력

    private var customTextInputSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.cursor")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            TextField("직관 한마디를 적어보세요", text: $customOverlayText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .tint(.white)
                .onChange(of: customOverlayText) { _, newVal in
                    if newVal.count > 20 {
                        customOverlayText = String(newVal.prefix(20))
                    }
                }

            if !customOverlayText.isEmpty {
                Text(String(format: String(localized: "ticket.overlay.charCount", defaultValue: "%lld/20"), locale: .autoupdatingCurrent, Int64(customOverlayText.count)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - 저장 / 공유 버튼

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button {
                Task { @MainActor in
                    await saveCurrentTicketToGallery()
                }
            } label: {
                HStack(spacing: 8) {
                    if isSavingToGallery {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(isSavingToGallery ? "저장 중..." : "내 갤러리에 저장")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(isSavingToGallery || isRendering)
            .opacity((isSavingToGallery || isRendering) ? 0.7 : 1)

            Button {
                Task { @MainActor in
                    await shareRenderedImage()
                }
            } label: {
                HStack(spacing: 8) {
                    if isRendering {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text("공유")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(isSavingToGallery || isRendering)
            .opacity((isSavingToGallery || isRendering) ? 0.7 : 1)
        }
    }

    // MARK: - 정적 이미지 로드

    private func loadStaticImages() async {
        let team1LogoURL = match.hasFavoriteTeam
            ? match.folder?.teamLogoUrl
            : team1Data?.logo_url
        let team2LogoURL = team2Data?.logo_url

        async let logoTask1 = loadURLOptional(team1LogoURL)
        async let logoTask2 = loadURLOptional(team2LogoURL)

        let (logo1, logo2) = await (logoTask1, logoTask2)
        team1LogoImg = logo1
        team2LogoImg = logo2
    }

    // MARK: - ImageRenderer 렌더링 (공유 버튼 탭 시에만 호출)

    @MainActor
    private func renderTicketImage(model: MatchTicketModel, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(
            content: MatchTicketCardView(model: model)
                .frame(
                    width: MatchTicketCardView.designWidth,
                    height: MatchTicketCardView.designHeight
                )
        )
        renderer.scale = scale
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(
            width: MatchTicketCardView.designWidth,
            height: MatchTicketCardView.designHeight
        )
        return renderer.uiImage
    }

    @MainActor
    private func buildImageForStorage() async -> UIImage? {
        let model = makeCardModel(showsBrandingWatermark: false)
        return renderTicketImage(model: model, scale: TicketImageExport.storageRendererScale)
    }

    @MainActor
    private func buildImageForSharing() async -> UIImage? {
        let isPro = FanfolioEntitlements.isPro
        let scale = isPro ? TicketImageExport.proShareRendererScale : TicketImageExport.freeShareRendererScale
        let model = makeCardModel(showsBrandingWatermark: !isPro)
        return renderTicketImage(model: model, scale: scale)
    }

    // MARK: - 유틸

    private func loadURLOptional(_ urlString: String?) async -> UIImage? {
        guard let urlString else { return nil }
        return await loadImage(from: urlString)
    }

    @MainActor
    private func shareRenderedImage() async {
        isRendering = true
        shareImage = await buildImageForSharing()
        isRendering = false
        if shareImage != nil {
            showingActivityShareSheet = true
        }
    }

    @MainActor
    private func saveCurrentTicketToGallery() async {
        isSavingToGallery = true
        defer { isSavingToGallery = false }

        guard let image = await buildImageForStorage() else {
            photoVM.saveErrorMessage = String(localized: "ticket.share.error.renderFailed", defaultValue: "티켓 이미지를 생성하지 못했습니다.")
            return
        }

        do {
            let storedFiles = try TicketImageStore.save(image: image)
            let venueSnapshot: String? = {
                let t = match.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return t.isEmpty ? nil : t
            }()
            let savedTicket = SavedTicket(
                ticketID: storedFiles.ticketID,
                imagePath: storedFiles.imagePath,
                thumbnailPath: storedFiles.thumbnailPath,
                team1Name: match.team1Display,
                team2Name: match.team2Display,
                myTeamScore: match.myTeamScore,
                opponentScore: match.opponentScore,
                matchResult: match.matchResult,
                sportType: match.folder?.sportType ?? .other,
                matchDate: match.date,
                venueSearchQuery: venueSnapshot,
                match: match
            )
            modelContext.insert(savedTicket)

            do {
                try modelContext.save()
                photoVM.showSaveToast(String(localized: "ticket.share.toast.savedToGallery", defaultValue: "내 갤러리에 저장했어요."))
                if venueSnapshot != nil {
                    Task {
                        await geocodeSavedTicket(savedTicket)
                    }
                }
            } catch {
                TicketImageStore.delete(paths: [storedFiles.imagePath, storedFiles.thumbnailPath])
                modelContext.delete(savedTicket)
                photoVM.saveErrorMessage = String(format: String(localized: "ticket.share.error.saveFailedReason", defaultValue: "티켓을 저장하지 못했습니다.\n%@"), locale: .autoupdatingCurrent, error.localizedDescription)
            }
        } catch {
            photoVM.saveErrorMessage = error.localizedDescription
        }
    }

    /// 갤러리 저장 직후 구장명으로 좌표를 채웁니다. 실패해도 사용자 메시지는 띄우지 않습니다.
    private func geocodeSavedTicket(_ ticket: SavedTicket) async {
        guard let query = ticket.resolvedVenueSearchQuery else { return }
        let fanFolder = ticket.match?.folder
        let applyLeagueBias = StadiumGeocodingService.shouldApplyLeagueGeocodeBias(forQuery: query)
        let biasRegion = applyLeagueBias ? fanFolder.flatMap { StadiumGeocodingService.preferredSearchRegion(folder: $0) } : nil
        let countryCode = applyLeagueBias ? fanFolder.flatMap { StadiumGeocodingService.preferredISOCountryCode(folder: $0) } : nil
        guard let coord = try? await StadiumGeocodingService.coordinate(
            for: query,
            biasRegion: biasRegion,
            preferredISOCountryCode: countryCode
        ) else { return }
        await MainActor.run {
            ticket.latitude = coord.latitude
            ticket.longitude = coord.longitude
            if let m = ticket.match {
                m.venueLatitude = coord.latitude
                m.venueLongitude = coord.longitude
            }
            try? modelContext.save()
        }
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

#Preview("공유 시트 - LG 트윈스 (KBO)") {
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
