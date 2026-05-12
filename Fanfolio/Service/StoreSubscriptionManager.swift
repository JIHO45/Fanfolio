//
//  StoreSubscriptionManager.swift
//  Fanfolio
//
//  StoreKit 2: 상품 로드, 구매, Transaction.updates, currentEntitlements 기반 PRO 여부.
//

import Foundation
import Observation
import StoreKit
import UIKit

/// 맵 원정 경로·고화질·워터마크 제거 등 PRO 기능의 단일 진입점(관측 가능).
@MainActor
@Observable
final class StoreSubscriptionManager {

    static let shared = StoreSubscriptionManager()

    /// App Store(StoreKit)에서 확인된 유효 Pro 구독·거래만 반영. 설정의 «구독 관리»·페이월 복원 판별에 사용.
    private(set) var hasActiveStoreKitProEntitlement: Bool = false

    /// Pro 전용 **기능** 사용 가능 여부. `FanfolioSubscriptionFlags.launchProFeaturesFreeForEveryone`이면 구독 없이도 true.
    var hasProFeatureAccess: Bool {
        FanfolioSubscriptionFlags.launchProFeaturesFreeForEveryone || hasActiveStoreKitProEntitlement
    }

    /// 페이월·사이드바 Pro 배너·설정의 «알아보기» 등 **구매 유도 UI** 표시 여부.
    var shouldOfferProPurchase: Bool {
        !FanfolioSubscriptionFlags.launchProFeaturesFreeForEveryone && !hasActiveStoreKitProEntitlement
    }

    /// 현재 유효한 Pro 구독 거래 중 가장 늦은 만료 시각(이번 결제·갱신 기간 종료). 해지 후에도 이 날짜까지는 Pro 유지.
    private(set) var proEntitlementExpiresAt: Date?

    /// 로드된 월간 구독 상품. 가격·인트로 문구는 `SubscriptionPurchaseCopy`가 `introductoryOffer`를 참고해 만든다.
    var monthlyProduct: Product?
    var loadProductsError: String?
    var lastErrorMessage: String?

    private init() {
        Task { @MainActor in
            await self.listenForTransactionUpdates()
        }
        Task { @MainActor in
            await self.refreshEntitlements()
        }
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        var hasPro = false
        var latestExpiration: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard StoreProductID.proSubscriptionIDs.contains(transaction.productID) else { continue }
            hasPro = true
            if let exp = transaction.expirationDate {
                if let current = latestExpiration {
                    latestExpiration = max(current, exp)
                } else {
                    latestExpiration = exp
                }
            }
        }
        if hasActiveStoreKitProEntitlement != hasPro {
            hasActiveStoreKitProEntitlement = hasPro
        }
        let newExpiry = hasPro ? latestExpiration : nil
        if proEntitlementExpiresAt != newExpiry {
            proEntitlementExpiresAt = newExpiry
        }
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: StoreProductID.allProductIDs)
            monthlyProduct = products.first { $0.id == StoreProductID.monthly }
            // 빈 배열·ID 불일치는 catch로 안 잡힘 → 오류로 표시해야 페이월이 영구 비활성에 걸리지 않음
            if monthlyProduct == nil {
                loadProductsError = String(localized: "subscription.error.productNotFound", defaultValue: "구독 상품을 찾을 수 없습니다. 스토어 설정·네트워크를 확인한 뒤 다시 시도해 주세요.")
            } else {
                loadProductsError = nil
            }
        } catch {
            loadProductsError = error.localizedDescription
            monthlyProduct = nil
        }
    }

    // MARK: - Purchase & restore

    enum PurchaseOutcome: Sendable {
        case purchased
        case cancelled
        case pending
    }

    func purchaseMonthly() async -> PurchaseOutcome {
        lastErrorMessage = nil
        let product: Product?
        if let cached = monthlyProduct {
            product = cached
        } else {
            await loadProducts()
            product = monthlyProduct
        }
        guard let product else {
            lastErrorMessage = loadProductsError ?? String(localized: "subscription.error.productUnavailable", defaultValue: "상품을 불러오지 못했습니다.")
            return .cancelled
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastErrorMessage = String(localized: "subscription.error.unverified", defaultValue: "구매를 확인하지 못했습니다.")
                    return .cancelled
                }
                await transaction.finish()
                await refreshEntitlements()
                return .purchased
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .cancelled
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return .cancelled
        }
    }

    func restorePurchases() async {
        lastErrorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// App Store 구독 관리(자동 갱신 해지·플랜 변경). 사용자가 닫으면 반환되며, 이후 권한을 다시 읽는다.
    func presentSystemManageSubscriptions() async {
        lastErrorMessage = nil
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            lastErrorMessage = String(localized: "subscription.manage.error.noWindow", defaultValue: "구독 관리 화면을 열 수 없습니다.")
            return
        }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
            await refreshEntitlements()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Transaction listener

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await refreshEntitlements()
        }
    }
}
