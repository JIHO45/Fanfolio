//
//  StadiumMapViewport.swift
//  Fanfolio
//
//  `FanfolioMapRegion`·경로 기하를 Mapbox Viewport로 변환합니다.
//

import CoreLocation
import MapboxMaps

enum StadiumMapViewport {
    /// 완료 핀이 있을 때 카메라가 영역을 덮도록 합니다.
    static func viewport(from region: FanfolioMapRegion) -> Viewport {
        let ring = boundingRing(for: region)
        let polygon = Polygon([ring])
        return .overview(geometry: polygon, bearing: 0, pitch: 0)
    }

    /// 원정 릴: 구간 곡선 전체가 보이도록(피치 포함).
    static func overviewLineString(_ coordinates: [CLLocationCoordinate2D], pitch: CGFloat) -> Viewport? {
        guard coordinates.count >= 2 else { return nil }
        return .overview(geometry: LineString(coordinates), bearing: 0, pitch: pitch)
    }

    private static func boundingRing(for region: FanfolioMapRegion) -> [CLLocationCoordinate2D] {
        let c = region.center
        let hLat = region.latitudeDelta / 2
        let hLon = region.longitudeDelta / 2
        return [
            CLLocationCoordinate2D(latitude: c.latitude - hLat, longitude: c.longitude - hLon),
            CLLocationCoordinate2D(latitude: c.latitude - hLat, longitude: c.longitude + hLon),
            CLLocationCoordinate2D(latitude: c.latitude + hLat, longitude: c.longitude + hLon),
            CLLocationCoordinate2D(latitude: c.latitude + hLat, longitude: c.longitude - hLon),
            CLLocationCoordinate2D(latitude: c.latitude - hLat, longitude: c.longitude - hLon)
        ]
    }
}
