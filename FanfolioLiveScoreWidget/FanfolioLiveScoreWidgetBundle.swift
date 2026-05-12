//
//  FanfolioLiveScoreWidgetBundle.swift
//  FanfolioLiveScoreWidget
//
//  Widget Extension 타겟의 진입점.
//  ⚠️ 이 파일은 Widget Extension 타겟에만 포함하세요 (앱 타겟에는 미포함).
//

import WidgetKit
import SwiftUI

@main
struct FanfolioLiveScoreWidgetBundle: WidgetBundle {
    var body: some Widget {
        LiveScoreWidget()
    }
}
