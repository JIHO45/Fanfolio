//
//  StoreProductID.swift
//  Fanfolio
//
//  App Store Connect 및 FanfolioStore.storekit과 동일한 문자열을 유지하세요.
//

import Foundation

enum StoreProductID {
    /// 자동 갱신 구독(월간) — PRO 권한
    static let monthly = "com.fanfolio.pro.monthly"

    /// PRO로 인정되는 모든 상품 ID (향후 연간 등 추가 시 여기만 확장)
    static var proSubscriptionIDs: Set<String> {
        [monthly]
    }

    static var allProductIDs: [String] {
        [monthly]
    }
}
