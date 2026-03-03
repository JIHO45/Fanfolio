//
//  AppIntent.swift
//  FanfolioWidget
//
//  Created by 박지호 on 2/15/26.
//

import WidgetKit
import AppIntents

/// 위젯 설정 Intent (현재는 설정 없이 첫 번째 폴더를 자동 표시)
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Fanfolio 위젯" }
    static var description: IntentDescription { "내 팀의 직관 승률과 다음 경기를 확인하세요." }
}
