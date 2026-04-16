//
//  PaywallPresentation.swift
//  Fanfolio
//
//  단일 paywall 시트를 CategoryView에서 띄우기 위해 하위 뷰에 “열기”만 주입합니다.
//

import SwiftUI

private struct PresentPaywallKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// `CategoryView`에서 주입. 기본값은 no-op(프리뷰·단독 테스트용).
    var presentPaywall: () -> Void {
        get { self[PresentPaywallKey.self] }
        set { self[PresentPaywallKey.self] = newValue }
    }
}
