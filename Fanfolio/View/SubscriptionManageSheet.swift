//
//  SubscriptionManageSheet.swift
//  Fanfolio
//
//  구독 중일 때 설정에서 열리는 안내 시트 → App Store 구독 관리로 이어짐.
//

import SwiftUI

private enum ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SubscriptionManageSheet: View {
    @Environment(StoreSubscriptionManager.self) private var storeSubscription
    @Environment(\.dismiss) private var dismiss

    @State private var isPresentingAppleManageUI = false
    @State private var notice: String?
    @State private var detentHeight: CGFloat = 400

    var body: some View {
        NavigationStack {
            content
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                    }
                }
                .navigationTitle(String(localized: "subscription.manage.sheet.title", defaultValue: "구독 관리"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.action.close", defaultValue: "닫기")) {
                            dismiss()
                        }
                    }
                }
        }
        .onPreferenceChange(ContentHeightKey.self) { h in
            guard h > 1 else { return }
            // 네비게이션 바 높이(약 56) + 상단 핸들 + 하단 여유
            let total = h + 56 + 8 + 16
            detentHeight = min(total, 700)
        }
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
        .alert(String(localized: "subscription.alert.title", defaultValue: "구독"), isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button(String(localized: "common.action.ok", defaultValue: "확인"), role: .cancel) {
                notice = nil
            }
        } message: {
            Text(notice ?? "")
        }
        .task {
            await storeSubscription.refreshEntitlements()
        }
    }

    // MARK: - 본문

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let until = storeSubscription.proEntitlementExpiresAt {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "subscription.manage.periodEndTitle", defaultValue: "Pro 유지 종료일"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(until, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(String(localized: "subscription.manage.periodEndExplain", defaultValue: "구독을 해지하거나 자동 갱신을 끄면 다음 결제는 없어지고, 위 날짜의 끝까지 이번에 결제한 기간으로 Pro가 유지됩니다."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }

            Text(String(localized: "subscription.manage.sheet.body", defaultValue: "Fanfolio Pro는 Apple ID로 결제됩니다. 구독을 해지하거나 자동 갱신을 끄려면 App Store의 구독 관리 화면에서 Fanfolio를 선택하세요."))
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    isPresentingAppleManageUI = true
                    await storeSubscription.presentSystemManageSubscriptions()
                    isPresentingAppleManageUI = false
                    if let msg = storeSubscription.lastErrorMessage, !msg.isEmpty {
                        notice = msg
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if isPresentingAppleManageUI {
                        ProgressView()
                    }
                    Text(String(localized: "subscription.manage.sheet.primaryButton", defaultValue: "구독 관리 화면 열기"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPresentingAppleManageUI)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

#Preview {
    SubscriptionManageSheet()
        .environment(StoreSubscriptionManager.shared)
}
