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
    static var isPro: Bool {
        UserDefaults.standard.bool(forKey: proUserDefaultsKey)
    }
}
