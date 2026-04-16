//
//  GroupedCardChrome.swift
//  Fanfolio
//
//  systemGroupedBackground 위 secondarySystemBackground 카드 가장자리 대비,
//  라이트 모드에서의 승률 링 배경 트랙 보강.
//

import SwiftUI

enum GroupedCardChrome {
    /// 그룹화 리스트 배경 위 일반 카드 외곽선 (다크는 기존과 비슷하게 유지).
    static func outlineStrokeColor(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.11)
        case .dark:
            return Color.white.opacity(0.10)
        @unknown default:
            return Color.primary.opacity(0.10)
        }
    }

    /// 승률 링의 배경 원(두께 10pt 근처).
    static func winRateRingTrackColorWide(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.13)
        case .dark:
            return Color.secondary.opacity(0.12)
        @unknown default:
            return Color.secondary.opacity(0.12)
        }
    }

    /// 팬 허브 등 두께 8pt 승률 링 배경.
    static func winRateRingTrackColorHub(colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.15)
        case .dark:
            return Color.secondary.opacity(0.18)
        @unknown default:
            return Color.secondary.opacity(0.18)
        }
    }
}

private struct GroupedCardOutlineModifier: ViewModifier {
    var cornerRadius: CGFloat
    var style: RoundedCornerStyle

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: style)
                .strokeBorder(GroupedCardChrome.outlineStrokeColor(colorScheme: colorScheme), lineWidth: 1)
        }
    }
}

extension View {
    /// `systemGroupedBackground` 위 `secondarySystemBackground` 카드의 윤곽을 보강합니다.
    func groupedCardOutline(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) -> some View {
        modifier(GroupedCardOutlineModifier(cornerRadius: cornerRadius, style: style))
    }
}
