//
//  FanfolioApp.swift
//  Fanfolio
//
//  Created by 박지호 on 12/10/25.
//

import SwiftUI
import SwiftData
import os.log

@main
struct FanfolioApp: App {
    let container: ModelContainer
    @State private var authService = AuthService()
    @State private var networkMonitor = NetworkMonitor.shared

    init() {
        let schema = Schema([
            SportsFanFolder.self,
            SportsModel.self,
            F1RaceModel.self,
            GolfRoundModel.self,
            CultureFanFolder.self,
            CultureModel.self
        ])

        // CloudKit 자동 동기화 (iCloud 계정이 있으면 기기 간 동기화)
        // Xcode에서 CloudKit Capability가 설정되지 않으면 로컬 저장소로 자동 fallback
        let cloudConfig = ModelConfiguration(cloudKitDatabase: .automatic)

        if let cloudContainer = try? ModelContainer(for: schema, configurations: cloudConfig) {
            container = cloudContainer
            Logger.data.info("ModelContainer initialized with CloudKit sync")
        } else if let localContainer = try? ModelContainer(for: schema) {
            container = localContainer
            Logger.data.warning("CloudKit unavailable, using local storage only")
        } else {
            fatalError("SwiftData ModelContainer 초기화에 실패했습니다. 스키마를 확인하세요.")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isSignedIn || authService.isGuest {
                    CategoryView()
                        .environment(authService)
                        .environment(networkMonitor)
                } else {
                    SignInView()
                        .environment(authService)
                }
            }
            .modelContainer(container)
        }
    }
}
