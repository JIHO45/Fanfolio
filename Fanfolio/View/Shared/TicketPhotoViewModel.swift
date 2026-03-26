//
//  TicketPhotoViewModel.swift
//  Fanfolio
//
//  SportsTicketShareView와 CultureTicketShareView에서 공통으로 사용하는
//  사진 상호작용 상태 및 Vision 누끼 추출 로직.
//

import SwiftUI
import PhotosUI
import Vision
import CoreImage

@Observable
@MainActor
final class TicketPhotoViewModel {

    // MARK: - 사진 상태
    var userPhotoItem: PhotosPickerItem?
    var showingPhotoPicker = false
    var userPhoto: UIImage?

    // 드래그/핀치줌
    var photoOffset: CGSize = .zero
    var lastPhotoOffset: CGSize = .zero
    var photoScale: CGFloat = 1.0
    var lastPhotoScale: CGFloat = 1.0

    // Vision 누끼
    var userPhotoCutout: UIImage?
    var isExtractingCutout = false

    // 저장/공유 상태
    var saveToastMessage: String?
    var saveErrorMessage: String?

    // MARK: - 사진 초기화

    func clearPhoto() {
        userPhoto = nil
        userPhotoItem = nil
        userPhotoCutout = nil
        photoOffset = .zero
        lastPhotoOffset = .zero
        photoScale = 1.0
        lastPhotoScale = 1.0
    }

    // MARK: - 사진 로드 + 누끼 추출

    func loadPhoto(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        userPhoto = image
        photoOffset = .zero
        lastPhotoOffset = .zero
        photoScale = 1.0
        lastPhotoScale = 1.0
        userPhotoCutout = nil
        isExtractingCutout = true
        userPhotoCutout = await Self.extractCutout(from: image)
        isExtractingCutout = false
    }

    // MARK: - Vision 누끼 추출 (백그라운드)

    static func extractCutout(from image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        return await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do { try handler.perform([request]) } catch { return nil }

            guard let result = request.results?.first else { return nil }

            do {
                let maskedBuffer = try result.generateMaskedImage(
                    ofInstances: result.allInstances,
                    from: handler,
                    croppedToInstancesExtent: false
                )
                let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
                let context = CIContext()
                guard let cgOut = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
                return UIImage(cgImage: cgOut, scale: image.scale, orientation: image.imageOrientation)
            } catch {
                return nil
            }
        }.value
    }

    // MARK: - offset 클램핑 (카드 밖으로 빠져나가지 않도록)

    func clampPhotoOffset(_ offset: CGSize, designWidth: CGFloat, designHeight: CGFloat) -> CGSize {
        guard let photo = userPhoto,
              photo.size.width > 0, photo.size.height > 0 else { return .zero }
        let fillScale = max(designWidth / photo.size.width, designHeight / photo.size.height) * photoScale
        let drawW = photo.size.width  * fillScale
        let drawH = photo.size.height * fillScale
        let maxX = max(0, (drawW - designWidth)  / 2)
        let maxY = max(0, (drawH - designHeight) / 2)
        return CGSize(
            width:  max(-maxX, min(maxX, offset.width)),
            height: max(-maxY, min(maxY, offset.height))
        )
    }

    // MARK: - 토스트

    func showSaveToast(_ message: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            saveToastMessage = message
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard self?.saveToastMessage == message else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self?.saveToastMessage = nil
            }
        }
    }
}

// MARK: - 공통 오버레이: Vision 처리 중 표시 + 드래그 힌트

struct TicketPhotoOverlayView: View {
    let isExtractingCutout: Bool
    let hasPhoto: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    var body: some View {
        ZStack {
            if isExtractingCutout {
                VStack(spacing: 6) {
                    ProgressView().tint(.white)
                    Text(String(localized: "ticket.subjectRecognizing", defaultValue: "피사체 인식 중…"))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if hasPhoto {
                VStack {
                    Spacer()
                    Text(String(localized: "ticket.dragHint", defaultValue: "드래그로 이동 · 핀치로 확대/축소"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.bottom, 8)
                }
                .frame(width: cardWidth, height: cardHeight)
                .allowsHitTesting(false)
            }
        }
    }
}
