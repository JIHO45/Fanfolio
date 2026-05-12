//
//  FanfolioSubscriptionFlags.swift
//  Fanfolio
//
//  구독·페이월 ON/OFF를 코드 한 곳에서 전환합니다.
//

import Foundation

enum FanfolioSubscriptionFlags {
    /// `true`: App Store 구독 없이도 Pro 기능(맵 하이라이트·고화질·워터마크 제거 등)을 모두 사용 가능.
    /// 페이월·Pro 업셀 UI는 표시하지 않습니다. 1.0 런칭 전면 무료 개방 등에 사용하세요.
    /// 유료 구독을 다시 켤 때는 `false`로 바꾸면 됩니다.
    static let launchProFeaturesFreeForEveryone: Bool = true
}
