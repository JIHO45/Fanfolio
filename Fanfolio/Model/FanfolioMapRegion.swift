//
//  FanfolioMapRegion.swift
//  Fanfolio
//
//  MapKit `MKCoordinateRegion` 없이 지도 카메라용 영역(중심 + 위도/경도 span)을 표현합니다.
//

import CoreLocation

struct FanfolioMapRegion: Equatable, Sendable {
    var center: CLLocationCoordinate2D
    var latitudeDelta: Double
    var longitudeDelta: Double
}
