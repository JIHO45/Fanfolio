//
//  SubscriptionPurchaseCopy.swift
//  Fanfolio
//
//  `Product.displayPrice`는 정상가 기준이라, 무료 체험·인트로는 subscription.introductoryOffer로 문구를 만든다.
//

import Foundation
import StoreKit

enum SubscriptionPurchaseCopy {

    /// 설정 화면 구독 CTA 한 줄 (인트로 오퍼 시 “체험 후 정가” 분기).
    static func monthlySubscribeButtonTitle(for product: Product) -> String {
        let regularPrice = product.displayPrice
        let monthlyLabel = String(localized: "subscription.purchase.monthly", defaultValue: "월간 구독")

        guard let subscription = product.subscription,
              let intro = subscription.introductoryOffer
        else {
            return "\(monthlyLabel) — \(regularPrice)"
        }

        switch intro.paymentMode {
        case .freeTrial:
            let dur = introOfferDurationPhrase(intro)
            return String(
                format: String(localized: "subscription.purchase.freeTrialThenPrice", defaultValue: "%1$@ 무료 체험 후 %2$@"),
                dur,
                regularPrice
            )
        case .payAsYouGo:
            return String(
                format: String(localized: "subscription.purchase.introPayAsYouGo", defaultValue: "%1$@부터 이후 %2$@"),
                intro.displayPrice,
                regularPrice
            )
        case .payUpFront:
            return String(
                format: String(localized: "subscription.purchase.introPayUpFront", defaultValue: "%1$@ 첫 기간 후 %2$@"),
                intro.displayPrice,
                regularPrice
            )
        default:
            return "\(monthlyLabel) — \(regularPrice)"
        }
    }

    /// 인트로가 있을 때 보조 설명 (버튼 아래 한 줄).
    static func monthlySubscribeSubtitle(for product: Product) -> String? {
        guard let subscription = product.subscription,
              subscription.introductoryOffer != nil
        else { return nil }
        return String(
            localized: "subscription.purchase.introSubtitle",
            defaultValue: "이후 매 결제 주기마다 자동 갱신됩니다. 앱스토어에서 언제든 해지할 수 있습니다."
        )
    }

    private static func introOfferDurationPhrase(_ offer: Product.SubscriptionOffer) -> String {
        let total = offer.period.value * offer.periodCount
        switch offer.period.unit {
        case .day:
            return String(
                format: String(localized: "subscription.duration.days", defaultValue: "%lld일"),
                Int64(total)
            )
        case .week:
            return String(
                format: String(localized: "subscription.duration.weeks", defaultValue: "%lld주"),
                Int64(total)
            )
        case .month:
            if total == 1 {
                return String(localized: "subscription.duration.oneMonth", defaultValue: "1개월")
            }
            return String(
                format: String(localized: "subscription.duration.months", defaultValue: "%lld개월"),
                Int64(total)
            )
        case .year:
            if total == 1 {
                return String(localized: "subscription.duration.oneYear", defaultValue: "1년")
            }
            return String(
                format: String(localized: "subscription.duration.years", defaultValue: "%lld년"),
                Int64(total)
            )
        default:
            return ""
        }
    }
}
