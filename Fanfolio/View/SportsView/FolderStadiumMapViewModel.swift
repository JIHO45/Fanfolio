//
//  FolderStadiumMapViewModel.swift
//  Fanfolio
//
//  직관 지도용 스냅샷: 필터·폴더가 바뀔 때만 무거운 배열·거리 합계를 재계산합니다.
//  PRO 원정 릴은 `roadTripVisualSegments`를 미리 계산해 두고, 뷰는 prefix만 갱신합니다.
//

import CoreLocation
import Observation
import SwiftData

/// PRO 하이라이트 릴용 — 경기일 순 **연쇄 구간**(이전 구장→다음 구장) 시각적 아크 좌표열.
struct RoadTripVisualSegment: Identifiable {
    let id: String
    /// 출발지가 저장 홈과 가까우면 true.
    let departureIsHome: Bool
    /// 출발 구장 핀 id(홈이면 빈 문자열).
    let departureVenuePinGroupId: String
    /// 도착 구장이 원정 핀이면 `StadiumMapVenuePinGroup.id`. 저장된 홈 좌표와 가까우면 빈 문자열(집 별 펄스).
    let venuePinGroupId: String
    /// true면 도착 펄스를 홈 마커에 표시.
    let arrivalIsHome: Bool
    /// 해당 구간 **편도** 거리(m).
    let oneWayMeters: Double
    let coordinates: [CLLocationCoordinate2D]
    /// 같은 구장에서 연속으로 치른 경기(시간순 인덱스) — 출발/도착 콜아웃에 모두 표시.
    let calloutDepartureItineraryIndices: [Int]
    let calloutArrivalItineraryIndices: [Int]
}

/// 같은 구장 좌표(반올림 키)에 묶인 완료 경기들. 지도에는 핀 하나만 표시.
struct StadiumMapVenuePinGroup: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    /// 최신 경기가 앞(내림차순)
    let matches: [SportsModel]

}

@Observable
@MainActor
final class FolderStadiumMapViewModel {
    private(set) var totalCompletedInFolder: Int = 0
    private(set) var seasonYearsInFolder: [Int] = []
    private(set) var filteredCompletedMatches: [SportsModel] = []
    private(set) var mappableMatches: [SportsModel] = []
    private(set) var venuePinGroups: [StadiumMapVenuePinGroup] = []
    /// 릴·거리 합계용: 필터된 완료 경기 중 좌표 있는 것만 **경기일 오름차순**(홈/원정 모두 시간순 여정).
    private(set) var roadTripItineraryMatchesChronological: [SportsModel] = []
    private(set) var roadTripRoundTripMeters: Double = 0
    /// PRO 궤적 애니메이션용(빈 배열이면 미계산).
    private(set) var roadTripVisualSegments: [RoadTripVisualSegment] = []
    private(set) var matchesMissingVenueCoordinates: [SportsModel] = []
    private(set) var geocodeBackfillTaskToken: String = ""
    private(set) var venuePinGroupIdsSignature: String = ""

    /// 필터·폴더 데이터가 바뀔 때만 호출합니다.
    /// - Parameter computeRoadTripVisuals: PRO 지도에서만 `true` — 시각적 아크 좌표를 미리 채웁니다.
    func rebuild(
        folder: SportsFanFolder,
        selectedSeasonYear: Int?,
        filterWinsOnly: Bool,
        filterAwayOnly: Bool,
        computeRoadTripVisuals: Bool = false
    ) {
        let cal = Calendar.current
        let completedAll = folder.matches.filter { $0.matchStatus == .completed }
        totalCompletedInFolder = completedAll.count

        let years = Set(completedAll.compactMap { $0.date.map { cal.component(.year, from: $0) } })
        seasonYearsInFolder = years.sorted(by: >)

        var list = completedAll
        if let y = selectedSeasonYear {
            list = list.filter { cal.component(.year, from: $0.date ?? .distantPast) == y }
        }
        if filterWinsOnly {
            list = list.filter { $0.matchResult == .win }
        }
        if filterAwayOnly {
            list = list.filter { !$0.isHomeGame }
        }
        filteredCompletedMatches = list.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        mappableMatches = filteredCompletedMatches.filter(\.hasVenueCoordinate)
        venuePinGroups = Self.buildVenuePinGroups(from: mappableMatches)
        venuePinGroupIdsSignature = venuePinGroups.map(\.id).sorted().joined(separator: "|")

        roadTripItineraryMatchesChronological = filteredCompletedMatches
            .filter(\.hasVenueCoordinate)
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

        let home = StadiumMapHomeVenueStorage.coordinate(for: folder.folderID)
        roadTripRoundTripMeters = Self.chainTripTotalMeters(itineraryMatches: roadTripItineraryMatchesChronological)

        if computeRoadTripVisuals {
            roadTripVisualSegments = Self.buildRoadTripVisualSegments(
                home: home,
                itineraryMatches: roadTripItineraryMatchesChronological
            )
        } else {
            roadTripVisualSegments = []
        }

        matchesMissingVenueCoordinates = filteredCompletedMatches.filter { match in
            guard !match.hasVenueCoordinate else { return false }
            return match.mapGeocodeQuery != nil
        }
        geocodeBackfillTaskToken = matchesMissingVenueCoordinates
            .map { String(describing: $0.persistentModelID) }
            .sorted()
            .joined(separator: "|")
    }

    func regionEncasingMappableMatches() -> FanfolioMapRegion? {
        Self.regionEncasingCoordinates(
            mappableMatches.compactMap { m in
                guard let lat = m.venueLatitude, let lon = m.venueLongitude else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            },
            edgePaddingFraction: 0.35
        )
    }

    /// `edgePaddingFraction`: span 대비 여백 비율 — 기본 지도는 0.35, 원정 직선 맞춤은 0.25 등.
    static func regionEncasingCoordinates(
        _ coords: [CLLocationCoordinate2D],
        edgePaddingFraction: Double = 0.35
    ) -> FanfolioMapRegion? {
        guard let first = coords.first else { return nil }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for c in coords.dropFirst() {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let latSpan = max(maxLat - minLat, 0.02)
        let lonSpan = max(maxLon - minLon, 0.02)
        let padLat = max(latSpan * edgePaddingFraction, 0.03)
        let padLon = max(lonSpan * edgePaddingFraction, 0.03)
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        return FanfolioMapRegion(
            center: center,
            latitudeDelta: min(latSpan + padLat * 2, 180),
            longitudeDelta: min(lonSpan + padLon * 2, 360)
        )
    }

    private static func venueCoordinateGroupingKey(latitude: Double, longitude: Double) -> String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }

    private static func buildVenuePinGroups(from mappableMatches: [SportsModel]) -> [StadiumMapVenuePinGroup] {
        let grouped = Dictionary(grouping: mappableMatches) { match -> String in
            guard let la = match.venueLatitude, let lo = match.venueLongitude else { return "" }
            return venueCoordinateGroupingKey(latitude: la, longitude: lo)
        }
        return grouped.compactMap { key, matches -> StadiumMapVenuePinGroup? in
            guard !key.isEmpty,
                  let first = matches.first,
                  let la = first.venueLatitude,
                  let lo = first.venueLongitude else { return nil }
            let sorted = matches.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            return StadiumMapVenuePinGroup(
                id: key,
                coordinate: CLLocationCoordinate2D(latitude: la, longitude: lo),
                matches: sorted
            )
        }
    }

    /// 연쇄 경로 **편도 구간 합**(m) — 경기일 순 웨이포인트(연속 동일 구장은 생략).
    private static func chainTripTotalMeters(itineraryMatches: [SportsModel]) -> Double {
        let waypoints = waypointsFromItinerary(itineraryMatches)
        guard waypoints.count >= 2 else { return 0 }
        var sum = 0.0
        for i in 0..<(waypoints.count - 1) {
            let a = waypoints[i]
            let b = waypoints[i + 1]
            let d = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            if d >= minimumLegMeters { sum += d }
        }
        return sum
    }

    private static let minimumLegMeters: Double = 80

    private static func waypointsFromItinerary(_ matches: [SportsModel]) -> [CLLocationCoordinate2D] {
        var waypoints: [CLLocationCoordinate2D] = []
        for m in matches {
            guard let la = m.venueLatitude, let lo = m.venueLongitude else { continue }
            let c = CLLocationCoordinate2D(latitude: la, longitude: lo)
            if let last = waypoints.last,
               CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) < minimumLegMeters {
                continue
            }
            waypoints.append(c)
        }
        return waypoints
    }

    private static func isNearHome(_ coord: CLLocationCoordinate2D, home: CLLocationCoordinate2D) -> Bool {
        CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            .distance(from: CLLocation(latitude: home.latitude, longitude: home.longitude)) < 180
    }

    private static func matchCoordinate(_ m: SportsModel) -> CLLocationCoordinate2D? {
        guard let la = m.venueLatitude, let lo = m.venueLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: lo)
    }

    private static func matchIsAtWaypoint(_ m: SportsModel, waypoint: CLLocationCoordinate2D, home: CLLocationCoordinate2D?) -> Bool {
        guard let c = matchCoordinate(m) else { return false }
        if let h = home, isNearHome(waypoint, home: h) { return isNearHome(c, home: h) }
        return CLLocation(latitude: c.latitude, longitude: c.longitude)
            .distance(from: CLLocation(latitude: waypoint.latitude, longitude: waypoint.longitude)) < 180
    }

    /// 이 구간 출발지에서 떠날 때까지의 **마지막** 경기(시간순).
    private static func calloutDepartureItineraryIndex(
        itinerary: [SportsModel],
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        home: CLLocationCoordinate2D?
    ) -> Int {
        var lastAtFrom: Int?
        for (idx, m) in itinerary.enumerated() {
            guard matchCoordinate(m) != nil else { continue }
            if matchIsAtWaypoint(m, waypoint: to, home: home) { break }
            if matchIsAtWaypoint(m, waypoint: from, home: home) { lastAtFrom = idx }
        }
        return lastAtFrom ?? 0
    }

    /// 이 구간 도착 구장에서의 **첫** 경기(출발 인덱스 이후 시간순).
    private static func calloutArrivalItineraryIndex(
        itinerary: [SportsModel],
        to: CLLocationCoordinate2D,
        afterDepartureIndex: Int,
        home: CLLocationCoordinate2D?
    ) -> Int {
        let start = min(afterDepartureIndex + 1, itinerary.count)
        for idx in start..<itinerary.count {
            if matchIsAtWaypoint(itinerary[idx], waypoint: to, home: home) { return idx }
        }
        for idx in itinerary.indices {
            if matchIsAtWaypoint(itinerary[idx], waypoint: to, home: home) { return idx }
        }
        return afterDepartureIndex
    }

    /// 출발 구장에서 이 구간을 떠나기 직전까지 **같은 구장 연속 경기** 전부.
    private static func calloutDepartureItineraryIndices(
        itinerary: [SportsModel],
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        home: CLLocationCoordinate2D?
    ) -> [Int] {
        let depIdx = calloutDepartureItineraryIndex(itinerary: itinerary, from: from, to: to, home: home)
        var lo = depIdx
        while lo > 0 && matchIsAtWaypoint(itinerary[lo - 1], waypoint: from, home: home) {
            lo -= 1
        }
        return Array(lo...depIdx)
    }

    /// 도착 구장에서 다음 구장으로 가기 전까지 **같은 구장 연속 경기** 전부.
    private static func calloutArrivalItineraryIndices(
        itinerary: [SportsModel],
        to: CLLocationCoordinate2D,
        afterDepartureIndex: Int,
        home: CLLocationCoordinate2D?
    ) -> [Int] {
        let arrIdx = calloutArrivalItineraryIndex(
            itinerary: itinerary,
            to: to,
            afterDepartureIndex: afterDepartureIndex,
            home: home
        )
        var hi = arrIdx
        while hi + 1 < itinerary.count && matchIsAtWaypoint(itinerary[hi + 1], waypoint: to, home: home) {
            hi += 1
        }
        return Array(arrIdx...hi)
    }

    // MARK: - 시각적 아크(연쇄 구간 + 구간 인덱스별 높이 차)

    private static func buildRoadTripVisualSegments(
        home: CLLocationCoordinate2D?,
        itineraryMatches: [SportsModel]
    ) -> [RoadTripVisualSegment] {
        let waypoints = waypointsFromItinerary(itineraryMatches)
        guard waypoints.count >= 2 else { return [] }

        var segments: [RoadTripVisualSegment] = []
        var visualIndex = 0
        for i in 0..<(waypoints.count - 1) {
            let from = waypoints[i]
            let to = waypoints[i + 1]
            let distM = CLLocation(latitude: from.latitude, longitude: from.longitude)
                .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
            if distM < minimumLegMeters { continue }

            let coords = visualArcCoordinates(
                from: from,
                to: to,
                pointCount: 64,
                segmentIndex: visualIndex
            )
            let departureHome = home.map { isNearHome(from, home: $0) } ?? false
            let depVid = departureHome
                ? ""
                : venueCoordinateGroupingKey(latitude: from.latitude, longitude: from.longitude)
            let arrivalHome = home.map { isNearHome(to, home: $0) } ?? false
            let vid = arrivalHome
                ? ""
                : venueCoordinateGroupingKey(latitude: to.latitude, longitude: to.longitude)
            let depIdx = calloutDepartureItineraryIndex(
                itinerary: itineraryMatches,
                from: from,
                to: to,
                home: home
            )
            let depIndices = calloutDepartureItineraryIndices(
                itinerary: itineraryMatches,
                from: from,
                to: to,
                home: home
            )
            let arrIndices = calloutArrivalItineraryIndices(
                itinerary: itineraryMatches,
                to: to,
                afterDepartureIndex: depIdx,
                home: home
            )
            segments.append(
                RoadTripVisualSegment(
                    id: "roadtrip.chain.\(visualIndex).\(i)",
                    departureIsHome: departureHome,
                    departureVenuePinGroupId: depVid,
                    venuePinGroupId: vid,
                    arrivalIsHome: arrivalHome,
                    oneWayMeters: distM,
                    coordinates: coords,
                    calloutDepartureItineraryIndices: depIndices,
                    calloutArrivalItineraryIndices: arrIndices
                )
            )
            visualIndex += 1
        }
        return segments
    }

    /// 위도에 `sin(πt)` 보간 — 거리·**구간 인덱스**로 피크 가변(같은 지리적 코스도 시각적으로 구분).
    private static func visualArcCoordinates(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        pointCount: Int,
        segmentIndex: Int
    ) -> [CLLocationCoordinate2D] {
        let distM = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
        let distKm = max(0.5, distM / 1000)
        let indexBoost = 1.0 + Double(segmentIndex) * 0.06
        // 완만한 포물선(이전보다 낮은 피크 + 분모 확대).
        let peakDeg = min(4.0, max(0.05, distKm / 320 * 0.75 * indexBoost))

        return (0...pointCount).map { i in
            let t = Double(i) / Double(pointCount)
            let lat = from.latitude + (to.latitude - from.latitude) * t
            let lon = from.longitude + (to.longitude - from.longitude) * t
            let lift = sin(t * .pi) * peakDeg
            return CLLocationCoordinate2D(latitude: lat + lift, longitude: lon)
        }
    }
}
