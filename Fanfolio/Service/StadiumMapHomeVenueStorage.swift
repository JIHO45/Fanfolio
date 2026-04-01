//
//  StadiumMapHomeVenueStorage.swift
//  Fanfolio
//
//  직관 지도「홈 구장」좌표 — 폴더별 UserDefaults 저장 (원정 직선 거리용).
//  위도·경도는 Double 키로 분리해 Locale·문자열 파싱에 의존하지 않습니다.
//

import CoreLocation
import Foundation

enum StadiumMapHomeVenueStorage {
    private static func latitudeKey(for folderID: UUID) -> String {
        "fanfolio.stadiumMap.homeLat.\(folderID.uuidString)"
    }

    private static func longitudeKey(for folderID: UUID) -> String {
        "fanfolio.stadiumMap.homeLon.\(folderID.uuidString)"
    }

    /// 예전 단일 문자열 키(마이그레이션 전용).
    private static func legacyCombinedKey(for folderID: UUID) -> String {
        "fanfolio.stadiumMap.homeCoord.\(folderID.uuidString)"
    }

    static func coordinate(for folderID: UUID) -> CLLocationCoordinate2D? {
        let defaults = UserDefaults.standard
        let latKey = latitudeKey(for: folderID)
        let lonKey = longitudeKey(for: folderID)

        if let lat = defaults.object(forKey: latKey) as? Double,
           let lon = defaults.object(forKey: lonKey) as? Double {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        // 레거시 "lat,lon" 문자열 → 한 번 읽어 Double 키로 이전 후 제거
        let legacy = legacyCombinedKey(for: folderID)
        guard let s = defaults.string(forKey: legacy) else { return nil }
        let parts = s.split(separator: Character(","), omittingEmptySubsequences: true)
        guard parts.count == 2,
              let lat = Double(String(parts[0]).trimmingCharacters(in: CharacterSet.whitespaces)),
              let lon = Double(String(parts[1]).trimmingCharacters(in: CharacterSet.whitespaces)) else {
            defaults.removeObject(forKey: legacy)
            return nil
        }
        let migrated = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        setCoordinate(migrated, for: folderID)
        defaults.removeObject(forKey: legacy)
        return migrated
    }

    static func setCoordinate(_ coordinate: CLLocationCoordinate2D?, for folderID: UUID) {
        let defaults = UserDefaults.standard
        let latKey = latitudeKey(for: folderID)
        let lonKey = longitudeKey(for: folderID)
        let legacy = legacyCombinedKey(for: folderID)
        if let coordinate {
            defaults.set(coordinate.latitude, forKey: latKey)
            defaults.set(coordinate.longitude, forKey: lonKey)
            defaults.removeObject(forKey: legacy)
        } else {
            defaults.removeObject(forKey: latKey)
            defaults.removeObject(forKey: lonKey)
            defaults.removeObject(forKey: legacy)
        }
    }
}
