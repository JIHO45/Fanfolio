//
//  FanfolioApp.swift
//  Fanfolio
//
//  Created by 박지호 on 12/10/25.
//

import MapboxMaps
import os.log
import SwiftData
import SwiftUI
import UIKit

/// `UIRequiresFullScreen` 없이 앱 전체를 세로(Portrait)로 고정한다. (iPad 멀티태스킹·향후 키 deprecation 대비)
final class FanfolioAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct FanfolioApp: App {
    @UIApplicationDelegateAdaptor(FanfolioAppDelegate.self) private var appDelegate

    let container: ModelContainer
    @State private var authService = AuthService()
    @State private var networkMonitor = NetworkMonitor.shared

    init() {
        if let token = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String,
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            MapboxOptions.accessToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let schema = Schema([
            SportsFanFolder.self,
            SportsModel.self,
            SavedTicket.self,
            CultureFanFolder.self,
            CultureModel.self
        ])

        // CloudKit 자동 동기화 (iCloud 계정이 있으면 기기 간 동기화)
        // Xcode에서 CloudKit Capability가 설정되지 않으면 로컬 저장소로 자동 fallback
        let cloudConfig = ModelConfiguration(cloudKitDatabase: .automatic)

        if let cloudContainer = try? ModelContainer(for: schema, configurations: cloudConfig) {
            container = cloudContainer
            Logger.data.info("ModelContainer initialized with CloudKit sync")
        } else if let localContainer = try? ModelContainer(for: schema, configurations: ModelConfiguration(cloudKitDatabase: .none)) {
            container = localContainer
            Logger.data.warning("CloudKit unavailable, using local storage only")
        } else {
            fatalError("SwiftData ModelContainer 초기화에 실패했습니다. 스키마를 확인하세요.")
        }

        _ = StoreSubscriptionManager.shared

        // 앱 강제 종료 후 재실행 시, 시스템에 남아있는 우리 라이브 액티비티를 다시 추적.
        Task { @MainActor in
            LiveActivityManager.shared.reattachOnLaunch()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isSignedIn || authService.isGuest {
                    FanfolioRootView()
                        .environment(authService)
                        .environment(networkMonitor)
                        .environment(StoreSubscriptionManager.shared)
                } else {
                    SignInView()
                        .environment(authService)
                        .environment(StoreSubscriptionManager.shared)
                }
            }
            .modelContainer(container)
        }
    }
}
