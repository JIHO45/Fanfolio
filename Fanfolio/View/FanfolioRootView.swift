//
//  FanfolioRootView.swift
//  Fanfolio
//
//  온보딩 완료 여부에 따라 메인(CategoryView)과 슬라이드 온보딩을 분기합니다.
//

import SwiftUI

struct FanfolioRootView: View {
    @AppStorage("hasSeenFanfolioWelcome") private var hasSeenFanfolioWelcome = false

    var body: some View {
        Group {
            if hasSeenFanfolioWelcome {
                CategoryView()
            } else {
                OnboardingTabView(hasCompletedWelcome: $hasSeenFanfolioWelcome)
            }
        }
    }
}
