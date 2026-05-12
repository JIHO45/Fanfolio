//
//  ProSubscriptionView.swift
//  Fanfolio
//
//  Fanfolio Pro 구독 안내·구매·복원 (대형 시트용).
//

import StoreKit
import SwiftUI

struct ProSubscriptionView: View {
    @Environment(StoreSubscriptionManager.self) private var storeSubscription
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasingSubscription = false
    @State private var subscriptionNotice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    heroSection

                    featureCardSection

                    purchaseSection

                    footerSection
                }
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(String(localized: "subscription.paywall.navigationTitle", defaultValue: "Fanfolio Pro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.secondary, Color(uiColor: .tertiarySystemFill))
                    }
                    .accessibilityLabel(String(localized: "common.action.close", defaultValue: "닫기"))
                }
            }
            .task {
                await storeSubscription.loadProducts()
            }
            .alert(String(localized: "subscription.alert.title", defaultValue: "구독"), isPresented: Binding(
                get: { subscriptionNotice != nil },
                set: { if !$0 { subscriptionNotice = nil } }
            )) {
                Button(String(localized: "common.action.ok", defaultValue: "확인"), role: .cancel) {
                    subscriptionNotice = nil
                    if storeSubscription.hasActiveStoreKitProEntitlement {
                        dismiss()
                    }
                }
            } message: {
                Text(subscriptionNotice ?? "")
            }
        }
    }

    // MARK: - Hero
    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .orange.opacity(0.35), radius: 10, x: 0, y: 5)
                .accessibilityHidden(true)

            Text(String(localized: "subscription.paywall.headline", defaultValue: "기록을 더 풍부하게"))
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)

            Text(String(localized: "subscription.paywall.heroSubtitle", defaultValue: "Fanfolio Pro와 함께 모든 직관의 순간을 특별하게 간직하세요."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    // MARK: - Features (card)
    private var featureCardSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            featureRow(
                icon: "point.topleft.down.to.point.bottomright.curvepath",
                title: String(localized: "subscription.paywall.feature.roadTrip.title", defaultValue: "원정 구장 궤적 하이라이트"),
                description: String(localized: "subscription.paywall.feature.roadTrip.desc", defaultValue: "지도 위를 따라가는 원정 경로 애니메이션")
            )
            featureRow(
                icon: "photo.on.rectangle.angled",
                title: String(localized: "subscription.paywall.feature.export.title", defaultValue: "고화질 내보내기"),
                description: String(localized: "subscription.paywall.feature.export.desc", defaultValue: "워터마크 없는 깔끔한 티켓·공유")
            )
            featureRow(
                icon: "star.fill",
                title: String(localized: "subscription.paywall.feature.proUnlock.title", defaultValue: "Pro 기능 한 번에"),
                description: String(localized: "subscription.paywall.feature.proUnlock.desc", defaultValue: "맵·티켓 공유·내보내기 제한을 동시에 해제")
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .groupedCardOutline(cornerRadius: 20)
        .padding(Edge.Set.horizontal)
    }

    // MARK: - Purchase CTA
    private var purchaseSection: some View {
        VStack(spacing: 16) {
            if let err = storeSubscription.loadProductsError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task {
                    isPurchasingSubscription = true
                    let outcome = await storeSubscription.purchaseMonthly()
                    isPurchasingSubscription = false
                    switch outcome {
                    case .purchased:
                        subscriptionNotice = String(localized: "subscription.purchase.success", defaultValue: "구독이 활성화되었습니다.")
                    case .pending:
                        subscriptionNotice = String(localized: "subscription.purchase.pending", defaultValue: "구매가 보류 중입니다. 승인 후 반영됩니다.")
                    case .cancelled:
                        if let msg = storeSubscription.lastErrorMessage, !msg.isEmpty {
                            subscriptionNotice = msg
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if isPurchasingSubscription {
                        ProgressView()
                            .tint(.white)
                    }
                    if let product = storeSubscription.monthlyProduct {
                        Text(SubscriptionPurchaseCopy.monthlySubscribeButtonTitle(for: product))
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.85)
                            .lineLimit(2)
                    } else if storeSubscription.loadProductsError != nil {
                        Text(String(localized: "subscription.purchase.retryLoad", defaultValue: "상품 정보 다시 불러오기"))
                            .font(.headline)
                    } else {
                        Text(String(localized: "subscription.purchase.loadingPrice", defaultValue: "가격 불러오는 중…"))
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .controlSize(.large)
            .clipShape(Capsule())
            .shadow(color: Color.accentColor.opacity(0.28), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 20)
            .disabled(isPurchasingSubscription || (storeSubscription.monthlyProduct == nil && storeSubscription.loadProductsError == nil))

            if let product = storeSubscription.monthlyProduct,
               let introSubtitle = SubscriptionPurchaseCopy.monthlySubscribeSubtitle(for: product) {
                Text(introSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Footer
    private var footerSection: some View {
        VStack(spacing: 14) {
            Button(String(localized: "subscription.restore", defaultValue: "구매 복원")) {
                Task {
                    await storeSubscription.restorePurchases()
                    if let msg = storeSubscription.lastErrorMessage, !msg.isEmpty {
                        subscriptionNotice = msg
                    } else if storeSubscription.hasActiveStoreKitProEntitlement {
                        subscriptionNotice = String(localized: "subscription.restore.success", defaultValue: "구매 내역을 복원했습니다.")
                    }
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.accentColor)

            HStack(spacing: 16) {
                Link(
                    String(localized: "subscription.paywall.link.terms.short", defaultValue: "이용 약관"),
                    destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                )
                Link(
                    String(localized: "subscription.paywall.link.privacy.short", defaultValue: "개인정보 처리방침"),
                    destination: APIConfig.privacyPolicyURL ?? URL(string: "https://www.apple.com/legal/privacy/")!
                )
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Text(String(localized: "settings.section.subscription.footer", defaultValue: "구독은 계정이 아닌 Apple ID에 연결됩니다. 앱스토어에서 구독을 관리할 수 있습니다."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.top, 4)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ProSubscriptionView()
        .environment(StoreSubscriptionManager.shared)
}
