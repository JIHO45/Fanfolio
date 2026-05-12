//
//  TicketImageExport.swift
//  Fanfolio
//
//  라이브 티켓 카드 렌더 스케일 + 갤러리에 저장된 래스터 티켓 공유용 처리.
//

import SwiftUI
import UIKit

// MARK: - 라이브 카드(ImageRenderer) 스케일

enum TicketImageExport {
    /// 9:16 카드 디자인의 긴 변(pt)
    static let ticketDesignLongEdge: CGFloat = max(MatchTicketCardView.designWidth, MatchTicketCardView.designHeight)

    /// 갤러리 저장용: 디스크 마스터(긴 변 ~2048)에 맞춘 렌더 스케일
    static var storageRendererScale: CGFloat { 2048.0 / ticketDesignLongEdge }

    /// 무료 공유: 출력 긴 변 ~1024
    static var freeShareRendererScale: CGFloat { 1024.0 / ticketDesignLongEdge }

    /// PRO 공유: 고해상도(업스케일). 실제 픽셀은 소스에 따라 달라짐.
    static let proShareRendererScale: CGFloat = 4.0

    /// 저장된 티켓 이미지 공유: 디스크 로드는 백그라운드, 합성·렌더는 메인.
    /// - `highQualityShare`: Pro급 해상도·업스케일(런칭 전면 개방 등).
    /// - `showWatermark`: Fanfolio 브랜딩 오버레이 — StoreKit 구독으로만 끌 수 있게 호출부에서 넘깁니다.
    static func prepareSavedTicketShareImage(
        relativeMasterPath: String,
        highQualityShare: Bool,
        showWatermark: Bool
    ) async -> UIImage? {
        let master = await Task.detached {
            TicketImageStore.loadImage(path: relativeMasterPath)
        }.value

        guard let master else { return nil }

        return await MainActor.run {
            renderSavedTicketForShare(master: master, highQualityShare: highQualityShare, showWatermark: showWatermark)
        }
    }

    // MARK: - 저장된 래스터 티켓

    @MainActor
    private static func renderSavedTicketForShare(master: UIImage, highQualityShare: Bool, showWatermark: Bool) -> UIImage? {
        let base = highQualityShare ? master : downscaleLongEdge(master, maxLongEdge: 1024)
        let w = base.size.width
        let h = base.size.height
        let longEdge = max(w, h)

        let rendererScale: CGFloat
        if highQualityShare {
            let cap = 4096.0 / max(longEdge, 1)
            rendererScale = min(proShareRendererScale, max(1, cap))
        } else {
            rendererScale = 1
        }

        let content = SavedTicketRasterShareView(image: base, showWatermark: showWatermark)
            .frame(width: w, height: h)

        let renderer = ImageRenderer(content: content)
        renderer.scale = rendererScale
        renderer.isOpaque = false
        renderer.proposedSize = ProposedViewSize(width: w, height: h)
        return renderer.uiImage
    }

    private static func downscaleLongEdge(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longEdge = max(w, h)
        guard longEdge > maxLongEdge else { return image }
        let scale = maxLongEdge / longEdge
        let newSize = CGSize(width: floor(w * scale), height: floor(h * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - 갤러리 래스터 공유용 뷰

private struct SavedTicketRasterShareView: View {
    let image: UIImage
    let showWatermark: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()

            if showWatermark {
                Text("FANFOLIO")
                    .font(.system(size: 10, weight: .black))
                    .tracking(4.5)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.trailing, 16)
                    .padding(.top, 16)
            }
        }
    }
}
