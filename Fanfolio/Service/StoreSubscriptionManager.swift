//
//  StoreSubscriptionManager.swift
//  Fanfolio
//
//  StoreKit 2: 상품 로드, 구매, Transaction.updates, currentEntitlements 기반 PRO 여부.
//

import Foundation
import StoreKit
import Observation

/// 맵 원정 경로·고화질·워터마크 제거 등 PRO 기능의 단일 진입점(관측 가능).
@MainActor
@Observable
final class StoreSubscriptionManager {

    static let shared = StoreSubscriptionManager()

    /// 유효한 PRO 구독(또는 인정되는 거래)이 있으면 true
    private(set) var isPro: Bool = false

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
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if StoreProductID.proSubscriptionIDs.contains(transaction.productID) {
                hasPro = true
                break
            }
        }
        if isPro != hasPro {
            isPro = hasPro
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

    // MARK: - Transaction listener

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await refreshEntitlements()
        }
    }
}
