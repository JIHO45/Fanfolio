//
//  StadiumGeocodingService.swift
//  Fanfolio
//
//  구장·경기장 이름(또는 자연어 주소)을 MKLocalSearch로 좌표로 변환합니다.
//  앱 전역에서 `coordinate` 한 경로로만 호출하면 직렬화·최소 간격이 보장됩니다.
//
//  동명·유사 지명(예: Levi's / 호주, NFL 팀명 / 일본 POI) 오탐을 줄이기 위해
//  리그별 `MKCoordinateRegion` 힌트와, 응답 후보 중 그 안에 들어오는 결과를 우선합니다.
//

import Foundation
import MapKit

enum StadiumGeocodingError: Error {
    case noResults
}

enum StadiumGeocodingService {
    /// 연속 `MKLocalSearch` 호출 사이에 두는 최소 간격. 짧은 간격의 다건 요청은 429·스로틀링 위험이 있습니다.
    static let minimumIntervalBetweenRequests: Duration = .milliseconds(450)

    /// 이전 이름 호환(백필 등 문서·주석 참조용).
    static var minimumIntervalBetweenBackfillRequests: Duration { minimumIntervalBetweenRequests }

    /// 미국 본토(알래스카·하와이 제외) 위주. NFL·NBA·MLB 등 검색 힌트·결과 필터에 사용.
    private static let usContiguousBiasRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 38.0, longitude: -97.0),
        span: MKCoordinateSpan(latitudeDelta: 24.0, longitudeDelta: 58.0)
    )

    private static let southKoreaBiasRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.3, longitude: 127.9),
        span: MKCoordinateSpan(latitudeDelta: 5.5, longitudeDelta: 5.2)
    )

    private static let westernEuropeBiasRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.5, longitude: 8.0),
        span: MKCoordinateSpan(latitudeDelta: 22.0, longitudeDelta: 28.0)
    )

    private static let japanBiasRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.2, longitude: 138.0),
        span: MKCoordinateSpan(latitudeDelta: 12.0, longitudeDelta: 14.0)
    )

    private static let usProLeagueCodes: Set<String> = [
        "NFL", "NBA", "MLB", "WNBA", "NHL", "MLS", "USA.1"
    ]

    private static let europeSoccerLeagueCodes: Set<String> = [
        "ENG.1", "ESP.1", "GER.1", "ITA.1", "FRA.1", "NED.1", "POR.1", "TUR.1", "BEL.1", "GRE.1", "CZE.1", "DEN.1",
        "ENG.FA", "ENG.LEAGUE_CUP", "ESP.COPA", "GER.DFB", "ITA.COPPA", "FRA.COUPE_DE_FRANCE",
        "UEFA.CHAMPIONS", "UEFA.EUROPA"
    ]

    /// 폴더(리그·종목)에 맞는 검색·스코어링 바이어스. 없으면 전 세계 균등(첫 결과).
    static func preferredSearchRegion(folder: SportsFanFolder) -> MKCoordinateRegion? {
        preferredSearchRegion(sportType: folder.sportType, leagueCode: folder.leagueCode)
    }

    /// `MKLocalSearch` 결과가 영역 밖에만 있을 때, 국가 코드로 한 번 더 거릅니다 (예: NFL → US).
    static func preferredISOCountryCode(folder: SportsFanFolder) -> String? {
        preferredISOCountryCode(sportType: folder.sportType, leagueCode: folder.leagueCode)
    }

    static func preferredISOCountryCode(sportType: SportType, leagueCode: String?) -> String? {
        let code = leagueCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        if usProLeagueCodes.contains(code) { return "US" }
        if code == "KBO" { return "KR" }
        if europeSoccerLeagueCodes.contains(code) { return nil }
        if code.contains("NPB") || code == "J1" || code == "J2" { return "JP" }
        switch sportType {
        case .americanFootball: return "US"
        default: return nil
        }
    }

    static func preferredSearchRegion(sportType: SportType, leagueCode: String?) -> MKCoordinateRegion? {
        let code = leagueCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""

        if usProLeagueCodes.contains(code) { return usContiguousBiasRegion }
        if code == "KBO" { return southKoreaBiasRegion }
        if europeSoccerLeagueCodes.contains(code) { return westernEuropeBiasRegion }

        // 일본 프로야구 등 (리그 코드가 늘어나면 여기에 추가)
        if code.contains("NPB") || code == "J1" || code == "J2" { return japanBiasRegion }

        switch sportType {
        case .americanFootball:
            return usContiguousBiasRegion
        default:
            return nil
        }
    }

    /// ESPN 등 **"경기장, 도시, 주"** 형태는 검색어에 이미 지역이 포함되므로 리그 기본(미국 박스·US 필터)을 적용하지 않습니다. 런던·멕시코 원정 등에 대응합니다.
    static func shouldApplyLeagueGeocodeBias(forQuery query: String) -> Bool {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return true }
        return !t.contains(",")
    }

    /// 자연어 검색으로 좌표를 반환합니다. `biasRegion`·`preferredISOCountryCode`는 힌트·후보 정렬에 사용합니다.
    static func coordinate(
        for naturalLanguageQuery: String,
        biasRegion: MKCoordinateRegion? = nil,
        preferredISOCountryCode: String? = nil
    ) async throws -> CLLocationCoordinate2D {
        try await StadiumGeocodingQueue.shared.coordinate(
            for: naturalLanguageQuery,
            biasRegion: biasRegion,
            preferredISOCountryCode: preferredISOCountryCode
        )
    }
}

// MARK: - Region / 결과 선택

private extension MKCoordinateRegion {
    /// 본 서비스에서 쓰는 단순 직사각형 포함 판정(날짜변경선 비특수 케이스).
    func fanfolioContains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let halfLat = span.latitudeDelta / 2
        let halfLon = span.longitudeDelta / 2
        let latOk = abs(coordinate.latitude - center.latitude) <= halfLat
        let lonOk = abs(coordinate.longitude - center.longitude) <= halfLon
        return latOk && lonOk
    }
}

// MARK: - MKMapItem (iOS 26+ placemark 대체)

private extension MKMapItem {
    /// `placemark` 대신 `location` 기준 좌표.
    var fanfolioCoordinate: CLLocationCoordinate2D {
        location.coordinate
    }

    /// `placemark.isoCountryCode` 대체. `addressRepresentations.region`(Locale.Region) 식별자에서 국가 코드를 씁니다.
    /// 식별자가 `US-CA` 형태면 하이픈 앞을, 그 외는 전체를 대문자로 반환합니다.
    var fanfolioISOCountryCode: String? {
        guard let id = addressRepresentations?.region?.identifier else { return nil }
        let upper = id.uppercased()
        guard !upper.isEmpty else { return nil }
        if let dash = upper.firstIndex(of: "-") {
            return String(upper[..<dash])
        }
        return upper
    }
}

private func fanfolioPickMapItem(
    from response: MKLocalSearch.Response,
    biasRegion: MKCoordinateRegion?,
    preferredISOCountryCode: String?
) -> MKMapItem? {
    let items = response.mapItems
    guard !items.isEmpty else { return nil }
    if let bias = biasRegion {
        if let best = items.first(where: { bias.fanfolioContains($0.fanfolioCoordinate) }) {
            return best
        }
    }
    if let cc = preferredISOCountryCode?.uppercased() {
        if let hit = items.first(where: { $0.fanfolioISOCountryCode == cc }) {
            return hit
        }
    }
    return items.first
}

// MARK: - 전역 직렬 큐 (재진입 안전 예약 패턴)

private actor StadiumGeocodingQueue {
    static let shared = StadiumGeocodingQueue()

    private let clock: ContinuousClock
    private var nextAvailableTime: ContinuousClock.Instant

    private init() {
        let c = ContinuousClock()
        clock = c
        nextAvailableTime = c.now
    }

    func coordinate(
        for naturalLanguageQuery: String,
        biasRegion: MKCoordinateRegion?,
        preferredISOCountryCode: String?
    ) async throws -> CLLocationCoordinate2D {
        let trimmed = naturalLanguageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StadiumGeocodingError.noResults }

        let now = clock.now
        let gap = StadiumGeocodingService.minimumIntervalBetweenRequests

        let scheduledTime = max(nextAvailableTime, now)
        nextAvailableTime = scheduledTime + gap

        let waitDuration = now.duration(to: scheduledTime)
        if waitDuration > .zero {
            try await Task.sleep(for: waitDuration)
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let bias = biasRegion {
            request.region = bias
        }

        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        guard let item = fanfolioPickMapItem(
            from: response,
            biasRegion: biasRegion,
            preferredISOCountryCode: preferredISOCountryCode
        ) else {
            throw StadiumGeocodingError.noResults
        }
        return item.fanfolioCoordinate
    }
}
