//
//  FanfolioEntitlements.swift
//  Fanfolio
//
//  StoreKit 연동 전: 단일 진입점. 나중에 Transaction.currentEntitlements 등으로 교체하면 됩니다.
//

import Foundation

enum FanfolioEntitlements {
    private static let proUserDefaultsKey = "fanfolio.entitlements.isProSubscriber"

    /// PRO 구독 여부. 기본값 false.
    /// - DEBUG: 스토어 연동 전에도 지도·원정 릴 등을 확인할 수 있도록 항상 PRO로 동작합니다.
    static var isPro: Bool {
        #if DEBUG
        true
        #else
        UserDefaults.standard.bool(forKey: proUserDefaultsKey)
        #endif
    }
}
