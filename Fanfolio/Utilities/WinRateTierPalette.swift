//
//  WinRateTierPalette.swift
//  Fanfolio
//
//  직관 승률(0~100%)을 5구간으로 나누어 링·숫자·지도 핀 등에서 동일하게 씁니다.
//

import SwiftUI

/// 승률(%) 기준 5단계. 스포츠에서 흔한 `.500` 경계를 반영해 구간을 나눕니다.
enum WinRateTier: Int, CaseIterable, Sendable {
    /// 0% 이상 ~ 25% 미만
    case veryLow
    /// 25% 이상 ~ 40% 미만
    case low
    /// 40% 이상 ~ 50% 미만 (500 미만)
    case fair
    /// 50% 이상 ~ 60% 미만 (500~600)
    case good
    /// 60% 이상 ~ 100%
    case excellent

    static func tier(forPercent percent: Double) -> WinRateTier {
        let p = min(max(percent, 0), 100)
        switch p {
        case ..<25: return .veryLow
        case ..<40: return .low
        case ..<50: return .fair
        case ..<60: return .good
        default: return .excellent
        }
    }

    /// 링 호·큰 %·핀 등에 쓰는 대표색 (지호 님 스펙 Hex, `Color.from` 실패 시 동일 RGB 폴백).
    ///
    /// | 구간   | 톤        | Hex     |
    /// |--------|-----------|---------|
    /// | 0~25   | 침체 레드 | #B01B1B |
    /// | 25~40  | 버밀리언  | #E65100 |
    /// | 40~50  | 어두운 앰버 | #C29200 |
    /// | 50~60  | 틸        | #008080 |
    /// | 60~100 | 에메랄드  | #2E7D32 |
    var accent: Color {
        switch self {
        case .veryLow:
            return Color.from(hex: "B01B1B") ?? Color(red: 176 / 255, green: 27 / 255, blue: 27 / 255)
        case .low:
            return Color.from(hex: "E65100") ?? Color(red: 230 / 255, green: 81 / 255, blue: 0 / 255)
        case .fair:
            return Color.from(hex: "C29200") ?? Color(red: 194 / 255, green: 146 / 255, blue: 0 / 255)
        case .good:
            return Color.from(hex: "008080") ?? Color(red: 0 / 255, green: 128 / 255, blue: 128 / 255)
        case .excellent:
            return Color.from(hex: "2E7D32") ?? Color(red: 46 / 255, green: 125 / 255, blue: 50 / 255)
        }
    }

    /// 링 진행부용 살짝 입체감 있는 그라데이션.
    var ringStrokeGradient: LinearGradient {
        let c = accent
        return LinearGradient(
            colors: [c.opacity(0.55), c],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum WinRateTierPalette {
    /// `FanWinRateRingView` 등: 경기 수가 0이면 중립색.
    static func accentColor(forPercent percent: Double, hasCompletedGames: Bool) -> Color {
        guard hasCompletedGames else { return Color.secondary }
        return WinRateTier.tier(forPercent: percent).accent
    }

    static func ringStrokeGradient(forPercent percent: Double, hasCompletedGames: Bool) -> LinearGradient {
        guard hasCompletedGames else {
            return LinearGradient(
                colors: [Color.secondary.opacity(0.28), Color.secondary.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return WinRateTier.tier(forPercent: percent).ringStrokeGradient
    }

    /// 시즌 리포트 카드 등 항상 색을 쓰는 경우(경기 0이면 가장 낮은 구간 톤 대신 dim).
    static func reportAccentColor(forPercent percent: Double, totalGames: Int) -> Color {
        guard totalGames > 0 else {
            return Color.secondary
        }
        return WinRateTier.tier(forPercent: percent).accent
    }

    /// 구장 핀: 경기 없음.
    static var pinNoMatches: Color {
        Color(red: 0.48, green: 0.48, blue: 0.50)
    }
}
