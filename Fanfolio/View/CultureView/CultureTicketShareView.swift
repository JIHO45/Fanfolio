//
//  CultureTicketShareView.swift
//  Fanfolio
//
//  Created by 박지호 on 3/15/26.
//

import SwiftUI
import Photos
import PhotosUI
import Vision
import CoreImage

// MARK: - Culture 티켓 공유 뷰

struct CultureTicketShareView: View {
    @Environment(\.dismiss) private var dismiss

    let event: CultureModel

    // MARK: - 상태

    @State private var photoVM = TicketPhotoViewModel()
    @State private var showingActivityShareSheet = false

    // 커스텀 텍스트
    @State private var customOverlayText: String = ""

    // 공유 렌더링
    @State private var shareImage: UIImage?
    @State private var isRendering = false
    @State private var isSavingToLibrary = false

    // 하단 컨트롤 높이 (토스트 위치 계산용)
    @State private var controlsHeight: CGFloat = 0

    // 한마디 패널 펼침/접힘
    @State private var isTextExpanded: Bool = true

    // MARK: - 팀 컬러 (CultureType 기준)

    private var bandColor: Color {
        switch event.folder?.cultureType ?? .other {
        case .concert:    return .purple
        case .musical:    return .red
        case .movie:      return .blue
        case .exhibition: return .teal
        case .festival:   return .orange
        case .other:      return .secondary
        }
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
            // 스포츠 티켓 공유와 동일: 저장된 이벤트가 편집되면 이전 공유 이미지 캐시 제거
            .task(id: event.fanfolioCultureShareTaskToken) {
                shareImage = nil
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
        let scaleByWidth  = displayW / CultureTicketCardView.designWidth
        let scaleByHeight = max(containerHeight - 24, 1) / CultureTicketCardView.designHeight
        let previewScale  = min(scaleByWidth, scaleByHeight)
        let cardW = CultureTicketCardView.designWidth * previewScale
        let cardH = CultureTicketCardView.designHeight * previewScale

        return VStack {
            Spacer()
            ZStack {
                CultureTicketCardView(model: currentCardModel)
                    .frame(
                        width: CultureTicketCardView.designWidth,
                        height: CultureTicketCardView.designHeight
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
                                    designWidth: CultureTicketCardView.designWidth,
                                    designHeight: CultureTicketCardView.designHeight
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
                                    designWidth: CultureTicketCardView.designWidth,
                                    designHeight: CultureTicketCardView.designHeight
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

    // MARK: - 하단 컨트롤 패널 (텍스트 입력 + 저장/공유 버튼)

    private var overlayControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 한마디 헤더 — 탭으로 펼침/접힘 토글
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    isTextExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("한마디")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    // 접혔을 때 입력된 내용 힌트
                    if !isTextExpanded && !customOverlayText.isEmpty {
                        Text("· \(customOverlayText)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                            .transition(.opacity)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .rotationEffect(isTextExpanded ? .degrees(0) : .degrees(-90))
                }
            }
            .buttonStyle(.plain)

            if isTextExpanded {
                textInputField
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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

    // MARK: - 텍스트 입력 필드 (헤더 제외)

    private var textInputField: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.cursor")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            TextField("소감을 적어보세요", text: $customOverlayText)
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
                    await saveToPhotoLibrary()
                }
            } label: {
                HStack(spacing: 8) {
                    if isSavingToLibrary {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(isSavingToLibrary ? "저장 중..." : "사진 앱에 저장")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(bandColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(isSavingToLibrary || isRendering)
            .opacity((isSavingToLibrary || isRendering) ? 0.7 : 1)

            Button {
                Task { @MainActor in
                    await shareRenderedImage()
                }
            } label: {
                HStack(spacing: 8) {
                    if isRendering {
                        ProgressView().tint(.white).scaleEffect(0.8)
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
            .disabled(isSavingToLibrary || isRendering)
            .opacity((isSavingToLibrary || isRendering) ? 0.7 : 1)
        }
    }

    // MARK: - 현재 카드 모델 조립

    private var currentCardModel: CultureTicketModel {
        CultureTicketModel(
            title: event.title,
            artist: event.artist,
            cultureType: event.folder?.cultureType ?? .other,
            rating: event.rating,
            eventStatus: event.eventStatus,
            seatInfo: event.seatInfo,
            date: event.date,
            location: event.location,
            bandColor: bandColor,
            userPhoto: photoVM.userPhoto,
            userPhotoCutout: photoVM.userPhotoCutout,
            photoOffset: photoVM.photoOffset,
            photoScale: photoVM.photoScale,
            customOverlayText: customOverlayText.isEmpty ? nil : customOverlayText
        )
    }

    // MARK: - 이미지 렌더링

    @MainActor
    private func buildImage() async -> UIImage? {
        let model = currentCardModel
        let renderer = ImageRenderer(
            content: CultureTicketCardView(model: model)
                .frame(
                    width: CultureTicketCardView.designWidth,
                    height: CultureTicketCardView.designHeight
                )
        )
        renderer.scale = 3
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(
            width: CultureTicketCardView.designWidth,
            height: CultureTicketCardView.designHeight
        )
        return renderer.uiImage
    }

    @MainActor
    private func shareRenderedImage() async {
        isRendering = true
        shareImage = await buildImage()
        isRendering = false
        if shareImage != nil {
            showingActivityShareSheet = true
        }
    }

    @MainActor
    private func saveToPhotoLibrary() async {
        isSavingToLibrary = true
        defer { isSavingToLibrary = false }

        guard let image = await buildImage() else {
            photoVM.saveErrorMessage = String(localized: "ticket.share.error.renderFailed", defaultValue: "티켓 이미지를 생성하지 못했습니다.")
            return
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
            if !granted {
                photoVM.saveErrorMessage = String(localized: "ticket.share.error.photoAccessRequired", defaultValue: "사진 접근 권한이 필요합니다. 설정에서 허용해 주세요.")
                return
            }
        } else if status == .denied || status == .restricted {
            photoVM.saveErrorMessage = String(localized: "ticket.share.error.photoAccessRequired", defaultValue: "사진 접근 권한이 필요합니다. 설정에서 허용해 주세요.")
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            photoVM.showSaveToast(String(localized: "ticket.share.toast.savedToPhotos", defaultValue: "사진 앱에 저장했어요."))
        } catch {
            photoVM.saveErrorMessage = String(format: String(localized: "ticket.share.error.genericSaveFailedReason", defaultValue: "저장에 실패했습니다.\n%@"), locale: .autoupdatingCurrent, error.localizedDescription)
        }
    }
}

// MARK: - Preview

#Preview("공유 시트 - BTS") {
    let folder = CultureFanFolder(name: "BTS", cultureType: .concert)
    let event = CultureModel(
        title: "BTS 월드투어 서울",
        artist: "BTS",
        date: Date(),
        location: "잠실 올림픽 주경기장",
        seatInfo: "VIP A구역 3열 15번",
        rating: 5,
        eventStatus: .completed,
        memo: "인생 최고의 콘서트!"
    )
    event.folder = folder
    return CultureTicketShareView(event: event)
}

#Preview("공유 시트 - 위키드") {
    let folder = CultureFanFolder(name: "위키드", cultureType: .musical)
    let event = CultureModel(
        title: "위키드 내한 뮤지컬",
        artist: "옥주현, 정선아",
        date: Date(),
        location: "블루스퀘어",
        seatInfo: "1층 R석 12열",
        rating: 4,
        eventStatus: .completed
    )
    event.folder = folder
    return CultureTicketShareView(event: event)
}
