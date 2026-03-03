//
//  APIConfig.swift
//  Fanfolio
//

import Foundation

/// API 키 및 엔드포인트 설정 관리
/// Phase 3에서 유료 키로 전환 시 Info.plist 값만 교체하면 됩니다.
enum APIConfig {
    
    // MARK: - API-Sports (https://www.api-sports.io)
    /// 무료 티어: 하루 100회 호출 제한
    /// Info.plist의 API_SPORTS_KEY 값을 사용합니다.
    static var apiSportsKey: String {
        Bundle.main.infoDictionary?["API_SPORTS_KEY"] as? String ?? ""
    }
    
    static let apiSportsBaseURL = "https://v1.american-football.api-sports.io"
    // 종목별 베이스 URL
    static let apiSportsURLs: [String: String] = [
        "NFL": "https://v1.american-football.api-sports.io",
        "NBA": "https://v2.nba.api-sports.io",
        "MLB": "https://v2.baseball.api-sports.io",
        "KBO": "https://v2.baseball.api-sports.io",
        "F1":  "https://v1.formula-1.api-sports.io",
        "soccer": "https://v3.football.api-sports.io",
    ]
    
    // MARK: - TheSportsDB (https://www.thesportsdb.com)
    /// 무료 테스트 키: "3" (워터마크 있음)
    /// Phase 3에서 $9/월 유료 키로 교체 시 워터마크 자동 제거
    static var sportsDBKey: String {
        let key = Bundle.main.infoDictionary?["SPORTS_DB_KEY"] as? String ?? ""
        return key.isEmpty ? "3" : key
    }
    
    static var sportsDBBaseURL: String {
        "https://www.thesportsdb.com/api/v1/json/\(sportsDBKey)"
    }
}
