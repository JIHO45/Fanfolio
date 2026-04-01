//
//  RoadTripHighlightReelController.swift
//  Fanfolio
//
//  PRO 원정 하이라이트 릴: 구간마다 카메라 1회(풀샷) 고정 후 비행기만 고빈도 갱신 → 도착 펄스 → 요약.
//  탭: 현재 단계 스킵 · 길게 누르기: 전체 경로 요약으로 점프.
//

import CoreLocation
import MapboxMaps
import Observation
import SwiftUI

/// 원정 릴 카메라·맵 오너먼트용 기기·가로폭별 튜닝값.
struct RoadTripLayoutMetrics: Equatable, Sendable {
    /// 추적 샷 줌에 더함(음수면 더 넓게 보임). iPad·regular width 등에서 사용.
    var chaseZoomOffset: CGFloat
    /// Mapbox 로고·어트리뷰션 하단 마진에 더함(pt).
    var ornamentBottomExtraLift: CGFloat

    static let `default` = RoadTripLayoutMetrics(chaseZoomOffset: 0, ornamentBottomExtraLift: 0)
}

@MainActor
@Observable
final class RoadTripHighlightReelController {
    private(set) var phase: PlaybackPhase = .idle
    private(set) var segmentIndex: Int = 0
    /// 현재 구간 곡선을 따라 0…1.
    private(set) var flyProgress: Double = 0
    /// 누적 왕복 기준 표시용(km).
    private(set) var odometerKm: Double = 0
    private(set) var pulsingVenueGroupId: String?
    /// 연쇄 구간이 홈에서 끝날 때 집 마커 펄스.
    private(set) var pulsingHomeArrival: Bool = false
    private(set) var showAllArcsSummary: Bool = false
    /// `.legPause`일 때 콜아웃: `true`면 해당 구간 **출발** 구장, `false`면 **도착** 구장.
    private(set) var pinCalloutShowsDeparture: Bool = false
    private(set) var pinCalloutSegmentIndex: Int = 0

    private var task: Task<Void, Never>?
    private var skipSegment = false
    private var jumpSummary = false

    enum PlaybackPhase: Equatable {
        case idle
        case flying
        case legPause
        case summary
    }

    func stop() {
        task?.cancel()
        task = nil
        resetIdleVisuals()
    }

    private func resetIdleVisuals() {
        phase = .idle
        segmentIndex = 0
        flyProgress = 0
        odometerKm = 0
        pulsingVenueGroupId = nil
        pulsingHomeArrival = false
        showAllArcsSummary = false
        pinCalloutShowsDeparture = false
        pinCalloutSegmentIndex = 0
        skipSegment = false
        jumpSummary = false
    }

    func userTappedSkip() {
        skipSegment = true
    }

    func userLongPressedSummary() {
        jumpSummary = true
        skipSegment = true
    }

    func start(
        segments: [RoadTripVisualSegment],
        home: CLLocationCoordinate2D?,
        roundTripTotalKm: Double,
        layoutMetrics: RoadTripLayoutMetrics = .default,
        updateCamera: @escaping (Viewport) -> Void
    ) {
        stop()
        guard !segments.isEmpty else { return }

        task = Task { @MainActor in
            // 맵·카메라·ViewAnnotation이 첫 프레임에 안정되도록 짧은 유예(시작 핀 누락 완화).
            try? await Task.sleep(nanoseconds: 320_000_000)
            if Task.isCancelled { return }
            await runPlayback(
                segments: segments,
                home: home,
                roundTripTotalKm: roundTripTotalKm,
                layoutMetrics: layoutMetrics,
                updateCamera: updateCamera
            )
        }
    }

    private func runPlayback(
        segments: [RoadTripVisualSegment],
        home: CLLocationCoordinate2D?,
        roundTripTotalKm: Double,
        layoutMetrics: RoadTripLayoutMetrics,
        updateCamera: @escaping (Viewport) -> Void
    ) async {
        jumpSummary = false
        skipSegment = false
        showAllArcsSummary = false
        var cumulativeLegKm = 0.0

        flyProgress = 0
        odometerKm = 0
        if Task.isCancelled { return }
        if jumpSummary {
            await applySummary(segments: segments, home: home, roundTripTotalKm: roundTripTotalKm, updateCamera: updateCamera)
            return
        }

        for i in segments.indices {
            if Task.isCancelled { return }
            if jumpSummary { break }

            segmentIndex = i
            let seg = segments[i]
            let legKm = seg.oneWayMeters / 1000

            /// 첫 구간: 추적 줌인 → 출발 핀 경기 콜아웃 → 비행 시작(궤적은 비행 전까지 숨김).
            if i == 0 {
                flyProgress = 0
                phase = .flying
                var introBearing: Double?
                // `progress: 0.06`이면 카메라 중심이 출발 구장에서 벗어나 핀이 화면 밖으로 밀린다. 출발점(0) + 하단 콜아웃만큼 패딩.
                if let chase = Self.chaseViewport(
                    segmentCoords: seg.coordinates,
                    progress: 0,
                    legKm: legKm,
                    layoutMetrics: layoutMetrics,
                    smoothedBearing: &introBearing
                ) {
                    let framed = chase.padding(.bottom, 270)
                    withViewportAnimation(.easeInOut(duration: 0.78)) {
                        updateCamera(framed)
                    }
                }
                try? await Task.sleep(nanoseconds: 820_000_000)
                if Task.isCancelled { return }
                if jumpSummary {
                    await applySummary(segments: segments, home: home, roundTripTotalKm: roundTripTotalKm, updateCamera: updateCamera)
                    return
                }

                phase = .legPause
                pinCalloutSegmentIndex = 0
                pinCalloutShowsDeparture = true
                pulsingVenueGroupId = seg.departureIsHome ? nil : seg.departureVenuePinGroupId
                pulsingHomeArrival = seg.departureIsHome
                await sleepInterruptible(seconds: Self.legPauseDepartureSeconds)
                pulsingVenueGroupId = nil
                pulsingHomeArrival = false
                pinCalloutShowsDeparture = false

                if Task.isCancelled { return }
                if jumpSummary {
                    await applySummary(segments: segments, home: home, roundTripTotalKm: roundTripTotalKm, updateCamera: updateCamera)
                    return
                }
            }

            phase = .flying
            flyProgress = 0
            pulsingVenueGroupId = nil
            pulsingHomeArrival = false

            // 전체 구간 오버뷰(줌아웃) 없이 바로 추적 샷으로 이어짐.

            // 2) 카메라 고정 — flyProgress·오도미터만 고빈도 갱신.
            /// 거리 비례 + 클램프: 긴 구간에서 타일 로딩·짧은 구간에서 최소 체류 시간 확보.
            let flightSec = Self.flightDuration(forLegKm: max(0.3, legKm))
            let steps = max(56, min(168, Int(flightSec * 72)))
            let stepDuration = flightSec / Double(steps + 1)

            var exitedFlyEarly = false
            /// 구간마다 리셋 — 꺾임에서 베어링이 튀어도 직전 프레임과 최단 호로만 스무딩.
            var chaseSmoothedBearing: Double?
            if let chase = Self.chaseViewport(
                segmentCoords: seg.coordinates,
                progress: 1e-4,
                legKm: legKm,
                layoutMetrics: layoutMetrics,
                smoothedBearing: &chaseSmoothedBearing
            ) {
                updateCamera(chase)
            }
            for s in 0...steps {
                await Task.yield()
                if Task.isCancelled { return }
                if jumpSummary {
                    flyProgress = 1
                    odometerKm = cumulativeLegKm + legKm
                    exitedFlyEarly = true
                    break
                }
                if skipSegment {
                    skipSegment = false
                    flyProgress = 1
                    odometerKm = cumulativeLegKm + legKm
                    exitedFlyEarly = true
                    break
                }
                let p = Double(s + 1) / Double(steps + 1)
                flyProgress = p
                odometerKm = cumulativeLegKm + legKm * p
                // 비행 중: 진행 방향·피치 고정 추적 카메라(애니메이션 없이 매 스텝 갱신).
                if let chase = Self.chaseViewport(
                    segmentCoords: seg.coordinates,
                    progress: p,
                    legKm: legKm,
                    layoutMetrics: layoutMetrics,
                    smoothedBearing: &chaseSmoothedBearing
                ) {
                    updateCamera(chase)
                }
                await Task.yield()
                let tileBreath: TimeInterval = legKm >= 120 ? 0.005 : 0
                try? await Task.sleep(nanoseconds: UInt64(max(stepDuration + tileBreath, 0.002) * 1_000_000_000))
            }

            if !exitedFlyEarly {
                flyProgress = 1
                odometerKm = cumulativeLegKm + legKm
            }
            cumulativeLegKm += legKm

            if jumpSummary { break }

            phase = .legPause
            pinCalloutSegmentIndex = i
            pinCalloutShowsDeparture = false
            pulsingVenueGroupId = seg.arrivalIsHome ? nil : seg.venuePinGroupId
            pulsingHomeArrival = seg.arrivalIsHome
            await sleepInterruptible(seconds: Self.legPauseArrivalSeconds)
            pulsingVenueGroupId = nil
            pulsingHomeArrival = false

            if jumpSummary { break }
        }

        if Task.isCancelled { return }
        await applySummary(segments: segments, home: home, roundTripTotalKm: roundTripTotalKm, updateCamera: updateCamera)
    }

    private func applySummary(
        segments: [RoadTripVisualSegment],
        home: CLLocationCoordinate2D?,
        roundTripTotalKm: Double,
        updateCamera: @escaping (Viewport) -> Void
    ) async {
        phase = .summary
        segmentIndex = segments.count
        flyProgress = 0
        showAllArcsSummary = true
        pulsingVenueGroupId = nil
        pulsingHomeArrival = false
        jumpSummary = false
        skipSegment = false
        odometerKm = roundTripTotalKm

        var coords: [CLLocationCoordinate2D] = []
        if let h = home {
            coords.append(h)
        } else if let first = segments.first?.coordinates.first {
            coords.append(first)
        }
        for s in segments {
            if let last = s.coordinates.last {
                coords.append(last)
            }
        }
        if coords.count >= 2,
           let r = FolderStadiumMapViewModel.regionEncasingCoordinates(coords, edgePaddingFraction: 0.22) {
            withViewportAnimation(.easeInOut(duration: 0.55)) {
                updateCamera(StadiumMapViewport.viewport(from: r))
            }
        }
    }

    private func sleepInterruptible(seconds: Double) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            await Task.yield()
            if Task.isCancelled { return }
            if jumpSummary { return }
            if skipSegment {
                skipSegment = false
                return
            }
            try? await Task.sleep(nanoseconds: 45_000_000)
        }
    }

    /// 출발 핀 콜아웃 표시 시간(경기 정보 읽기).
    private static let legPauseDepartureSeconds: TimeInterval = 2.9
    /// 도착 핀 콜아웃 표시 시간.
    private static let legPauseArrivalSeconds: TimeInterval = 3.4

    // MARK: - 비행 시간 (거리 비례 + 클램프)

    /// 거리에 따라 비행 시간을 둡니다. Mapbox 타일 로딩에 여유를 주되, 지나치게 길어지지 않게 상한을 둡니다.
    private static func flightDuration(forLegKm legKm: Double) -> TimeInterval {
        let minDuration: TimeInterval = 2.45
        let maxDuration: TimeInterval = 10.5
        let calculatedDuration = minDuration + (legKm / 1000.0) * 0.64
        return min(maxDuration, max(minDuration, calculatedDuration))
    }

    /// 추적 샷: 경로 진행 방향으로 베어링·피치. Standard 스타일은 피치 ~45° 넘어가면 안개·대기 셰이더 부담이 커져 이동 중 화면 번쩍임이 생기기 쉽다.
    private static let chasePitchDegrees: CGFloat = 38

    // MARK: - 추적 줌 튜닝 (아이패드·화면비 조정 시 여기만 보면 됨)
    // 값이 클수록 화면에 가까움(줌인). 회색 타일 완화를 위해 전체적으로 한 단계 넓힌 범위를 씀.

    private static let chaseZoomLegKmMin = 0.35
    private static let chaseZoomLegKmMax = 600.0
    private static let chaseZoomClose: CGFloat = 13.75
    private static let chaseZoomWide: CGFloat = 11.65
    private static let chaseZoomOutputMin: CGFloat = 11.25
    private static let chaseZoomOutputMax: CGFloat = 13.85
    /// 진행 중 포물선 줌아웃 시에만 더 넓게 허용(타일 부담 완화).
    private static let chaseZoomParallaxFloor: CGFloat = 9.95

    /// 프레임마다 raw 베어링을 이 각도 비율만큼만 따라가게 해 꺾임·노드에서의 급회전을 완화 (2D heading에는 quaternion slerp 대신 각도 보간이 일반적).
    private static let chaseBearingSmoothingAlpha = 0.32

    /// 구간 길이 → 줌. `legKm`·출력 줌 이중 클램프 + log 정규화 + smoothstep + 레이아웃 오프셋.
    private static func chaseZoom(forLegKm legKm: Double, layoutMetrics: RoadTripLayoutMetrics) -> CGFloat {
        let k = min(chaseZoomLegKmMax, max(chaseZoomLegKmMin, legKm))
        let u = (log(k) - log(chaseZoomLegKmMin)) / (log(chaseZoomLegKmMax) - log(chaseZoomLegKmMin))
        let s = u * u * (3 - 2 * u)
        let blended = chaseZoomClose + CGFloat(s) * (chaseZoomWide - chaseZoomClose)
        let adjusted = blended + layoutMetrics.chaseZoomOffset
        return min(chaseZoomOutputMax, max(chaseZoomOutputMin, adjusted))
    }

    /// 구간 중앙에서만 줌을 낮춰(시야 확대) 고해상도 타일 요구를 줄입니다. `progress` 0·1에서는 0.
    private static func chaseZoomParallaxOffset(progress: Double, legKm: Double) -> CGFloat {
        let p = min(1, max(0, progress))
        let bell = 4 * p * (1 - p)
        let legWeight = min(1, max(0, (legKm - 35) / 550))
        let depth: CGFloat = 1.55
        return -CGFloat(bell * legWeight) * depth
    }

    private static func chaseViewport(
        segmentCoords: [CLLocationCoordinate2D],
        progress: Double,
        legKm: Double,
        layoutMetrics: RoadTripLayoutMetrics,
        smoothedBearing: inout Double?
    ) -> Viewport? {
        guard let center = coordinateOnPolyline(segmentCoords, progress: progress) else { return nil }
        let rawBearing = bearingAlongPolyline(segmentCoords, progress: progress)
        let bearing = smoothBearing(previous: &smoothedBearing, raw: rawBearing, alpha: chaseBearingSmoothingAlpha)
        let base = chaseZoom(forLegKm: legKm, layoutMetrics: layoutMetrics)
        let parallax = chaseZoomParallaxOffset(progress: progress, legKm: legKm)
        /// 전 구간 공통으로 살짝 더 넓힘(고줌 타일 폭주 완화) — 이동 중 시야를 한 단계 더 넓힘.
        let zoomBias: CGFloat = -0.48
        let zoom = min(chaseZoomOutputMax, max(chaseZoomParallaxFloor, base + parallax + zoomBias))
        return .camera(center: center, zoom: zoom, bearing: bearing, pitch: chasePitchDegrees)
    }

    private static func smoothBearing(previous: inout Double?, raw: Double, alpha: Double) -> Double {
        guard let prev = previous else {
            let n = normalizeBearingDegrees(raw)
            previous = n
            return n
        }
        let next = lerpAngleDegrees(from: prev, to: raw, t: alpha)
        previous = next
        return next
    }

    /// 최단 호로 선형 보간한 뒤 0…360°로 정규화.
    private static func lerpAngleDegrees(from: Double, to: Double, t: Double) -> Double {
        let a = normalizeBearingDegrees(from)
        let b = normalizeBearingDegrees(to)
        var delta = b - a
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return normalizeBearingDegrees(a + delta * t)
    }

    private static func normalizeBearingDegrees(_ degrees: Double) -> Double {
        var r = degrees.truncatingRemainder(dividingBy: 360)
        if r < 0 { r += 360 }
        return r
    }

    private static func bearingAlongPolyline(_ coords: [CLLocationCoordinate2D], progress: Double) -> CLLocationDirection {
        guard let c = coordinateOnPolyline(coords, progress: progress) else { return 0 }
        let ahead = min(1, progress + 0.03)
        let c2 = coordinateOnPolyline(coords, progress: ahead) ?? c
        return bearingDegrees(from: c, to: c2)
    }

    private static func coordinateOnPolyline(_ coords: [CLLocationCoordinate2D], progress: Double) -> CLLocationCoordinate2D? {
        guard let first = coords.first else { return nil }
        guard coords.count >= 2 else { return first }
        let t = min(1, max(0, progress))
        let maxIdx = coords.count - 1
        let floatIndex = t * Double(maxIdx)
        let i = min(maxIdx - 1, max(0, Int(floatIndex)))
        let frac = floatIndex - Double(i)
        let a = coords[i]
        let b = coords[i + 1]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * frac,
            longitude: a.longitude + (b.longitude - a.longitude) * frac
        )
    }

    private static func bearingDegrees(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }
}
