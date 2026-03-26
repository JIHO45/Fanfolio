//
//  APIConfig.swift
//  Fanfolio
//

import Foundation

/// API 키 및 엔드포인트 설정 관리
enum APIConfig {

    // MARK: - API-Sports (https://www.api-sports.io)
    /// 무료 티어: 하루 100회 호출 제한
    /// 빌드 시 `DeveloperSettings.xcconfig` → (선택) `APIKeys.xcconfig`의 `API_SPORTS_KEY`가 Info.plist로 주입됩니다.
    static var apiSportsKey: String {
        Bundle.main.infoDictionary?["API_SPORTS_KEY"] as? String ?? ""
    }

    // MARK: - 종목별 베이스 URL
    static let apiSportsURLs: [String: String] = [
        "NFL":    "https://v1.american-football.api-sports.io",
        "NBA":    "https://v2.nba.api-sports.io",
        "MLB":    "https://v2.baseball.api-sports.io",
        "KBO":    "https://v2.baseball.api-sports.io",
        "soccer": "https://v3.football.api-sports.io",
    ]

    // MARK: - 리그 ID 상수 (API-Sports)
    enum LeagueIDs {
        static let kbo = 6
        static let kbl = 7
    }

    // MARK: - 시즌 기준 월
    enum SeasonBoundary {
        /// NFL/NBA/MLB: 이 월 이전이면 전년도 시즌
        static let generalStartMonth = 3
        /// 유럽 축구: 이 월 이전이면 전년도 시즌
        static let soccerStartMonth = 8
    }

    // MARK: - 캐시 TTL (초)
    enum CacheTTL {
        static let roster: TimeInterval   = 1800  // 30분
        static let schedule: TimeInterval = 3600  // 1시간
    }
}
