//
//  FolderStadiumMapView.swift
//  Fanfolio
//
//  폴더(팀) 기준 완료 경기 구장을 지도에 표시. 티켓 이미지 없이도 경기만으로 핀·백필 가능.
//

import Foundation
import SwiftUI
import SwiftData
import CoreLocation
import MapboxMaps
import UIKit

/// 현재 비행 구간 — **구간 ID + 고정 접미사**로 어노테이션 ID를 쓰면 세그먼트가 바뀔 때만 이전 세그먼트 피처가 사라지고, 같은 세그먼트 안에서는 좌표만 갱신된다.
/// 전역 `active.segment.*`는 구간이 바뀌며 이전 세그먼트와 무관한 같은 문자열 ID를 재사용해 레이어 전체가 덜컥 갱신되기 쉽다.
private enum RoadTripPolylineActiveId {
    static let trailSuffix = ".activeTrail"
    static let tipSuffix = ".activeTip"
    static func trail(for segmentId: String) -> String { segmentId + trailSuffix }
    static func tip(for segmentId: String) -> String { segmentId + tipSuffix }
}

private struct RoadTripPolylineDrawSegment: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    var isTrail: Bool = false
}

/// SwiftUI `PolylineAnnotation` 대신 런타임 `GeoJSONSource` + `LineLayer`로 그림 — `flyProgress`마다 맵 콘텐츠 트리를 재동기화하지 않음(공식 “Animate a line” 패턴).
private enum FanfolioRoadTripGeoJSONLine {
    static let baseSourceId = "fanfolio-rt-base-src"
    static let baseLayerId = "fanfolio-rt-base-layer"
    static let trailSourceId = "fanfolio-rt-trail-src"
    static let trailLayerId = "fanfolio-rt-trail-layer"
    static let tipSourceId = "fanfolio-rt-tip-src"
    static let tipLayerId = "fanfolio-rt-tip-layer"
}

struct FolderStadiumMapView: View {
    let folder: SportsFanFolder

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.presentPaywall) private var presentPaywall
    @Environment(StoreSubscriptionManager.self) private var storeSubscription

    @State private var mapModel = FolderStadiumMapViewModel()
    @State private var viewport: Viewport = .styleDefault
    @State private var selectedVenueGroupId: String?
    @State private var viewerTicket: SavedTicket?
    @State private var isBackfillGeocoding = false

    // 필터 (팬 통계 지도)
    @State private var selectedSeasonYear: Int?
    @State private var filterWinsOnly = false
    @State private var filterAwayOnly = false

    // PRO 원정 하이라이트 릴 (시각적 아크 + 카메라 시퀀서)
    @State private var roadTripActive = false
    @State private var roadTripReelPreparing = false
    @State private var highlightReel = RoadTripHighlightReelController()

    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    /// 저전력 모드에서는 `.sync` 대신 `.automatic`으로 두어 CPU·GPU 부담을 줄임(뷰 어노테이션은 약간 덜 붙을 수 있음).
    @State private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// `flyProgress`마다 뷰가 갱신될 때 완료 궤적 배열을 다시 만들지 않도록 캐시(맵 전체 깜빡임 완화).
    @State private var roadTripCachedCompletedPolylines: [RoadTripPolylineDrawSegment] = []

    /// 스타일 로드 완료 후 지연 렌더링되는 핀 그룹 — 초기 로딩 부하 분리용.
    @State private var visiblePinGroups: [StadiumMapVenuePinGroup] = []

    /// Summary 단계에서 지도 스냅샷 캡처 — `MapReader` proxy가 살아 있는 동안만 유효.
    @State private var captureMapSnapshot: (() -> UIImage?)?

    private var isPro: Bool { storeSubscription.hasProFeatureAccess }

    /// iPad·가로 regular에서 추적 샷을 약간 넓게, 로고 여백 확보.
    private var roadTripLayoutMetrics: RoadTripLayoutMetrics {
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let regular = horizontalSizeClass == .regular
        guard pad && regular else { return .default }
        return RoadTripLayoutMetrics(chaseZoomOffset: -0.35, ornamentBottomExtraLift: 36)
    }

    private var mapPresentationTransactionMode: PresentationTransactionMode {
        if isLowPowerModeEnabled { return .automatic }
        // 비행 중 매 프레임 동기 커밋은 긴 궤적·카메라와 겹치며 화면 전체가 깜빡이는 느낌을 줄 수 있음.
        if isPro, roadTripActive, highlightReel.phase == .flying { return .automatic }
        return .sync
    }

    /// 완료 궤적 캐시만 무효화할 때(`flyProgress` 제외). `pinCalloutShowsDeparture`는 같은 `segmentIndex`·`.legPause`에서 출발 콜아웃 vs 도착 콜아웃을 가름 — 없으면 캐시가 잘못 재사용됨.
    private var roadTripPolylineCompletedCacheKey: String {
        "\(roadTripActive)|\(highlightReel.segmentIndex)|\(String(describing: highlightReel.phase))|\(highlightReel.pinCalloutShowsDeparture)|\(highlightReel.showAllArcsSummary)|\(mapModel.roadTripVisualSegments.count)"
    }

    /// 런타임 GeoJSON 라인 소스만 맞추기 위한 시그니처(`flyProgress` 포함 → 비행 중 매 스텝 동기화, 단 **폴리라인 어노테이션 트리는 재생성하지 않음**).
    private var roadTripGeoJSONSyncSignature: String {
        "\(isPro)|\(roadTripActive)|\(roadTripPolylineCompletedCacheKey)|\(highlightReel.segmentIndex)|\(String(describing: highlightReel.phase))|\(highlightReel.flyProgress)"
    }

    private var homeCoordinate: CLLocationCoordinate2D? {
        guard isPro else { return nil }
        return StadiumMapHomeVenueStorage.coordinate(for: folder.folderID)
    }

    /// 저장된 홈 좌표와 같은 구장 핀(`FolderStadiumMapViewModel.isNearHome`과 동일: 약 180m 이내).
    private func coordinateIsNearSavedHome(_ coord: CLLocationCoordinate2D) -> Bool {
        guard let h = homeCoordinate else { return false }
        return CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            .distance(from: CLLocation(latitude: h.latitude, longitude: h.longitude)) < 180
    }

    private var roadTripLineColor: Color {
        Color.from(hex: folder.teamColor) ?? .blue
    }

    /// 다크 베이스맵에서 글로우가 죽지 않도록 팀 컬러보다 채도·명도를 살린 색.
    private var roadTripGlowLineColor: Color {
        Self.boostedGlowColor(from: roadTripLineColor)
    }

    /// 실크 트레일: 고정 슬림 두께(지도 가독성 우선).
    private var roadTripLineWidths: (glow: Double, core: Double, glowBlur: Double, coreBlur: Double) {
        Self.roadTripLineWidthsSilkTrail
    }

    /// PRO 원정 릴: 저녁 톤은 유지하되 3D 건물·오브젝트는 끔(베이스맵 타일·GPU 부담 완화로 회색 화면 완화).
    private var stadiumMapStyle: MapStyle {
        if isPro, roadTripActive {
            return .standard(lightPreset: .dusk, show3dObjects: false, show3dBuildings: false)
        }
        return .standard()
    }

    /// 하단 콜아웃 시 Mapbox 로고·어트리뷰션이 카드에 가리지 않도록 여백 상향.
    private var mapOrnamentOptions: OrnamentOptions {
        let baseLift: CGFloat = mapCalloutGroup != nil ? 220 : 10
        let bottomLift = baseLift + roadTripLayoutMetrics.ornamentBottomExtraLift
        return OrnamentOptions(
            scaleBar: ScaleBarViewOptions(visibility: .hidden),
            logo: LogoViewOptions(position: .bottomLeading, margins: CGPoint(x: 10, y: bottomLift)),
            attributionButton: AttributionButtonOptions(position: .bottomTrailing, margins: CGPoint(x: 10, y: bottomLift))
        )
    }

    /// `airplane.circle.fill` 글리프는 기본으로 **동쪽(3시)** 을 향하는 경우가 많음. 진행 방위(북 기준 시계방향)와 맞추려면 −90°.
    private static let roadTripPlaneSymbolHeadingOffsetDegrees: Double = -90

    private static let processInfoPowerStateDidChangeNotification = Notification.Name("NSProcessInfoPowerStateDidChange")

    private var filterSignature: String {
        "\(selectedSeasonYear.map(String.init) ?? "all")|\(filterWinsOnly)|\(filterAwayOnly)"
    }

    private var roadTripWinRateUnderFilters: String {
        let m = mapModel.filteredCompletedMatches
        let wins = m.filter { $0.matchResult == .win }.count
        let losses = m.filter { $0.matchResult == .loss }.count
        let d = wins + losses
        guard d > 0 else {
            return String(localized: "fanstats.map.roadTrip.summary.winRateEmpty", defaultValue: "—")
        }
        let pct = Int(round(Double(wins) / Double(d) * 100))
        return "\(pct)%"
    }

    private var roadTripReelAccessibilitySummary: String {
        let km = Int(highlightReel.odometerKm.rounded())
        let prefix = String(localized: "fanstats.map.roadTrip.totalKm.prefix", defaultValue: "필터 기준 이동 경로 합계 약")
        let unit = String(localized: "fanstats.map.roadTrip.kmUnit", defaultValue: "km")
        let hint = String(localized: "fanstats.map.roadTrip.reelHint", defaultValue: "탭: 다음 단계 · 길게 누르기: 전체 경로")
        return "\(prefix) \(km) \(unit). \(hint)"
    }

    private var selectedVenueGroup: StadiumMapVenuePinGroup? {
        guard let id = selectedVenueGroupId else { return nil }
        return mapModel.venuePinGroups.first { $0.id == id }
    }

    /// 원정 릴 `.legPause` — 같은 구장 **연속 경기**를 시간순으로 모두 포함.
    private var roadTripLegPauseCalloutGroup: StadiumMapVenuePinGroup? {
        guard isPro, roadTripActive, highlightReel.phase == .legPause else { return nil }
        let segs = mapModel.roadTripVisualSegments
        guard highlightReel.pinCalloutSegmentIndex < segs.count else { return nil }
        let seg = segs[highlightReel.pinCalloutSegmentIndex]
        let chron = mapModel.roadTripItineraryMatchesChronological
        let indices = highlightReel.pinCalloutShowsDeparture
            ? seg.calloutDepartureItineraryIndices
            : seg.calloutArrivalItineraryIndices
        guard !indices.isEmpty else { return nil }
        let matches = indices.compactMap { chron.indices.contains($0) ? chron[$0] : nil }
        let sorted = matches.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        guard let first = sorted.first,
              let la = first.venueLatitude,
              let lo = first.venueLongitude else { return nil }
        let coord = CLLocationCoordinate2D(latitude: la, longitude: lo)
        let idSuffix = "\(indices.first ?? 0)-\(indices.last ?? 0)"
        return StadiumMapVenuePinGroup(
            id: "roadtrip.callout.\(seg.id).\(idSuffix)",
            coordinate: coord,
            matches: sorted
        )
    }

    private var roadTripCalloutPhaseLabel: String? {
        guard isPro, roadTripActive, highlightReel.phase == .legPause else { return nil }
        if highlightReel.pinCalloutShowsDeparture {
            return String(localized: "fanstats.map.roadTrip.callout.departure", defaultValue: "이번 구간 출발")
        }
        return String(localized: "fanstats.map.roadTrip.callout.arrival", defaultValue: "도착")
    }

    /// 수동 선택 vs 릴 핀 콜아웃(릴 `.legPause`일 때는 릴만).
    private var mapCalloutGroup: StadiumMapVenuePinGroup? {
        if isPro, roadTripActive, highlightReel.phase == .legPause {
            return roadTripLegPauseCalloutGroup
        }
        return selectedVenueGroup
    }

    private func syncMapModelFromState() {
        mapModel.rebuild(
            folder: folder,
            selectedSeasonYear: selectedSeasonYear,
            filterWinsOnly: filterWinsOnly,
            filterAwayOnly: filterAwayOnly,
            computeRoadTripVisuals: isPro
        )
    }

    var body: some View {
        folderStadiumMapMainContent
    }

    @ViewBuilder
    private var folderStadiumMapMainContent: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    MapboxMaps.Map(viewport: $viewport) {
                        stadiumMapMapboxContent()
                        if isPro, roadTripActive {
                            Atmosphere()
                                .spaceColor(UIColor(red: 0.03, green: 0.05, blue: 0.14, alpha: 1))
                                .highColor(UIColor(red: 0.06, green: 0.1, blue: 0.22, alpha: 1))
                                .starIntensity(0.4)
                        }
                    }
                    .mapStyle(stadiumMapStyle)
                    .presentationTransactionMode(mapPresentationTransactionMode)
                    .ornamentOptions(mapOrnamentOptions)
                    .onStyleLoaded { _ in
                        guard let map = proxy.map else { return }
                        installFanfolioRoadTripGeoJSONLineLayers(map: map)
                        syncFanfolioRoadTripGeoJSONLineData(map: map)
                        captureMapSnapshot = { proxy.captureSnapshot(includeOverlays: true) }
                        applyStaticStadiumCoordinates()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                                visiblePinGroups = mapModel.venuePinGroups
                            }
                        }
                    }
                    .onChange(of: roadTripGeoJSONSyncSignature) { _, _ in
                        syncFanfolioRoadTripGeoJSONLineData(map: proxy.map)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: Self.processInfoPowerStateDidChangeNotification)) { _ in
                    isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
                }
                .onChange(of: mapModel.mappableMatches.count) { _, _ in
                    applyInitialCameraIfNeeded()
                }
                .onChange(of: mapModel.venuePinGroups.count) { _, _ in
                    applyInitialCameraIfNeeded()
                }
                .onChange(of: mapModel.venuePinGroupIdsSignature) { _, _ in
                    if let id = selectedVenueGroupId, !mapModel.venuePinGroups.contains(where: { $0.id == id }) {
                        selectedVenueGroupId = nil
                    }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                        visiblePinGroups = mapModel.venuePinGroups
                    }
                }
                .onChange(of: filterSignature) { _, _ in
                    if isPro, roadTripActive {
                        highlightReel.stop()
                        roadTripActive = false
                        roadTripReelPreparing = false
                    }
                    syncMapModelFromState()
                    if let id = selectedVenueGroupId, !mapModel.venuePinGroups.contains(where: { $0.id == id }) {
                        selectedVenueGroupId = nil
                    }
                }
                .onChange(of: roadTripPolylineCompletedCacheKey) { _, _ in
                    rebuildRoadTripCompletedPolylinesCache()
                }
                .onChange(of: roadTripActive) { _, active in
                    if active {
                        rebuildRoadTripCompletedPolylinesCache()
                    } else {
                        roadTripCachedCompletedPolylines = []
                    }
                }

                if isPro, roadTripActive, highlightReel.phase != .summary {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { highlightReel.userTappedSkip() }
                        .onLongPressGesture(minimumDuration: 0.55) {
                            highlightReel.userLongPressedSummary()
                        }
                }

                if let group = mapCalloutGroup {
                    VenueMatchesCalloutCard(
                        group: group,
                        roadTripPhaseLabel: roadTripCalloutPhaseLabel,
                        showsCloseButton: !(isPro && roadTripActive && highlightReel.phase == .legPause),
                        listMaxHeight: (isPro && roadTripActive && highlightReel.phase == .legPause) ? 480 : nil,
                        onClose: {
                            if roadTripLegPauseCalloutGroup != nil { return }
                            selectedVenueGroupId = nil
                        },
                        onOpenTicketViewer: { ticket in
                            viewerTicket = ticket
                            selectedVenueGroupId = nil
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    /// 릴 재생 중에는 카드를 관람용만 두고 터치는 뒤쪽 스킵 제스처로 넘김(티켓·상세와 충돌 방지).
                    .allowsHitTesting(!(isPro && roadTripActive))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: mapCalloutGroup?.id)

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.28),
                            Color.black.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 76)
                    .allowsHitTesting(false)

                    mapFilterChipsRow
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                }

                if isPro, roadTripActive, mapModel.roadTripRoundTripMeters > 0, highlightReel.phase != .summary {
                    VStack(spacing: 6) {
                        roadTripBadge
                        Text(
                            String(
                                localized: "fanstats.map.roadTrip.reelHint",
                                defaultValue: "탭: 다음 단계 · 길게 누르기: 전체 경로"
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(roadTripReelAccessibilitySummary)
                }

                Spacer(minLength: 0)
            }

            if let msg = toastMessage {
                Text(msg)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 120)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isPro, roadTripReelPreparing {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(
                        String(
                            localized: "fanstats.map.roadTrip.preparingPath",
                            defaultValue: "경로를 준비하는 중…"
                        )
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 160)
            }

            if isPro, roadTripActive, highlightReel.phase == .summary {
                VStack {
                    Spacer()
                    RoadTripSummaryCard(
                        totalKm: Int(highlightReel.odometerKm.rounded()),
                        venueCount: mapModel.venuePinGroups.count,
                        winRateText: roadTripWinRateUnderFilters,
                        accentColor: roadTripLineColor,
                        onDismiss: {
                            highlightReel.stop()
                            roadTripActive = false
                            applyInitialCameraIfNeeded()
                        },
                        onCaptureMapSnapshot: captureMapSnapshot
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toastMessage)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: highlightReel.phase)
        .overlay {
            if mapModel.mappableMatches.isEmpty {
                mapEmptyOverlay
            }
        }
        .onAppear {
            isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            if !isPro {
                roadTripActive = false
                highlightReel.stop()
            }
            syncMapModelFromState()
            applyInitialCameraIfNeeded()
        }
        .onDisappear {
            if isPro, roadTripActive {
                highlightReel.stop()
                roadTripActive = false
                roadTripReelPreparing = false
            }
        }
        .task(id: folder.fanfolioFolderTaskToken) {
            syncMapModelFromState()
            applyInitialCameraIfNeeded()
        }
        .task(id: mapModel.geocodeBackfillTaskToken) {
            await backfillMissingVenueCoordinates()
        }
        .fullScreenCover(item: $viewerTicket) { ticket in
            TicketImageViewerView(ticket: ticket)
        }
        .navigationTitle(String(localized: "fanstats.map.navigationTitle", defaultValue: "직관 지도"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if isPro {
                        toggleRoadTrip()
                    } else {
                        presentPaywall()
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(roadTripActive ? Color.accentColor : .primary, roadTripActive ? Color.accentColor.opacity(0.35) : .secondary)
                        if !isPro {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .offset(x: 5, y: -5)
                        }
                    }
                }
                .accessibilityLabel(
                    isPro
                        ? String(localized: "fanstats.map.roadTrip.a11y", defaultValue: "원정 구장 연결 궤적 하이라이트")
                        : String(
                            localized: "fanstats.map.roadTrip.a11y.locked",
                            defaultValue: "원정 궤적 하이라이트, PRO 구독 필요"
                        )
                )
            }
        }
    }

    private func rebuildRoadTripCompletedPolylinesCache() {
        roadTripCachedCompletedPolylines = computeRoadTripPolylineCompletedStorage()
    }

    /// 전체 경로(세그먼트 연결) — 공유 빌더와 동일한 평탄화.
    private var roadTripPolylineFlattenedFullPath: [CLLocationCoordinate2D] {
        RoadTripRouteShareBuilder.flattenedCoordinates(segments: mapModel.roadTripVisualSegments)
    }

    /// 완료 구간(캐시) + 비행 중 현재 구간 프리픽스. 도착 `legPause`는 캐시가 이미 `segmentIndex` 구간까지 포함하므로 별도 `legPauseTrail` 불필요(중복·GeoJSON 오류 방지).
    private var roadTripPolylineTrailSegments: [RoadTripPolylineDrawSegment] {
        var out = roadTripCachedCompletedPolylines
        guard isPro, roadTripActive else { return out }
        let segs = mapModel.roadTripVisualSegments
        if segs.isEmpty { return out }
        // Summary 단계에서는 캐시 타이밍과 무관하게 직접 전체 경로를 반환해 선이 사라지는 문제를 막음.
        if highlightReel.showAllArcsSummary {
            return segs.map { RoadTripPolylineDrawSegment(id: $0.id, coordinates: $0.coordinates, isTrail: false) }
        }
        // legPause: onChange 캐시 딜레이 없이 직접 계산.
        // 탭 fast-forward 후 phase 전환 시 onChange가 캐시를 업데이트하기 전 1프레임 사이에
        // 선이 깜빡이는 Race Condition을 제거한다.
        if highlightReel.phase == .legPause {
            if highlightReel.pinCalloutShowsDeparture { return [] }
            let n = highlightReel.segmentIndex + 1
            guard n > 0 else { return [] }
            return Array(segs.prefix(n).map {
                RoadTripPolylineDrawSegment(id: $0.id, coordinates: $0.coordinates, isTrail: true)
            })
        }

        if highlightReel.phase == .flying,
           highlightReel.segmentIndex < segs.count {
            let cur = segs[highlightReel.segmentIndex]
            let prog = highlightReel.flyProgress
            if prog > 1e-5 {
                let prefix = roadTripPolylinePrefix(cur.coordinates, progress: prog)
                if prefix.count >= 2 {
                    out.append(RoadTripPolylineDrawSegment(id: "\(cur.id).flyingLegTrail", coordinates: prefix, isTrail: true))
                }
            }
        }
        return out
    }

    /// 비행 중 — 꼬리(dim) 없이 **팁(혜성 광원)**만 갱신해 레이어 부담·Z-fighting을 줄임.
    private var roadTripPolylineActiveTipSegments: [RoadTripPolylineDrawSegment] {
        guard isPro, roadTripActive else { return [] }
        let segs = mapModel.roadTripVisualSegments
        if segs.isEmpty || highlightReel.showAllArcsSummary { return [] }
        guard highlightReel.phase == .flying,
              highlightReel.segmentIndex < segs.count else { return [] }

        let cur = segs[highlightReel.segmentIndex]
        let prog = highlightReel.flyProgress
        /// 비행기는 `coordinateOnPolyline(..., progress: prog)`에 정확히 놓임 — 팁 선 끝을 **prog보다 앞**(예: +0.005)으로 두면 궤적이 비행기보다 빨리 가는 것처럼 보임.
        let tipEnd = prog
        let tid = RoadTripPolylineActiveId.tip(for: cur.id)

        if prog > 0.06 {
            let tipStart = max(0, prog - 0.08)
            let brightTip = roadTripPolylineSlice(cur.coordinates, from: tipStart, to: tipEnd)
            if brightTip.count >= 2 {
                return [RoadTripPolylineDrawSegment(id: tid, coordinates: brightTip, isTrail: false)]
            }
        } else if prog > 1e-5 {
            let pref = roadTripPolylinePrefix(cur.coordinates, progress: prog)
            if pref.count >= 2 {
                return [RoadTripPolylineDrawSegment(id: tid, coordinates: pref, isTrail: false)]
            }
        }
        return []
    }

    /// 이미 끝난 구간만 — `flyProgress`와 무관(`onChange`로만 캐시 갱신).
    /// - 비행 중: `segmentIndex == i`이면 구간 `0..<i`만 완료(현재 구간은 `flyingLegTrail`이 칠함).
    /// - 도착 legPause: 방금 구간 `i` 비행이 끝난 뒤이면 `0...i`까지 완료. 예전 `prefix(segmentIndex)`는 **마지막 구간을 빼서** 끝이 줄곧 회색으로 남았음.
    private func computeRoadTripPolylineCompletedStorage() -> [RoadTripPolylineDrawSegment] {
        guard isPro, roadTripActive else { return [] }
        let segs = mapModel.roadTripVisualSegments
        if segs.isEmpty { return [] }
        if highlightReel.showAllArcsSummary {
            return segs.map { RoadTripPolylineDrawSegment(id: $0.id, coordinates: $0.coordinates, isTrail: false) }
        }
        switch highlightReel.phase {
        case .flying:
            let i = highlightReel.segmentIndex
            guard i > 0 else { return [] }
            return segs.prefix(i).map {
                RoadTripPolylineDrawSegment(id: $0.id, coordinates: $0.coordinates, isTrail: true)
            }
        case .legPause:
            if highlightReel.pinCalloutShowsDeparture {
                return []
            }
            let n = highlightReel.segmentIndex + 1
            guard n > 0 else { return [] }
            return segs.prefix(n).map {
                RoadTripPolylineDrawSegment(id: $0.id, coordinates: $0.coordinates, isTrail: true)
            }
        default:
            return []
        }
    }

    /// 스타일 로드 시 1회: `PolylineAnnotation`이 아닌 **GeoJSON + LineLayer**(Mapbox “Animate a line”과 동일하게 소스 데이터만 갱신).
    private func installFanfolioRoadTripGeoJSONLineLayers(map: MapboxMap) {
        guard !map.sourceExists(withId: FanfolioRoadTripGeoJSONLine.baseSourceId) else { return }

        let lw = roadTripLineWidths
        let baseW = Self.roadTripBaseGuideLineWidth
        /// 베이스(점선)보다 확실히 두껍게 — blur 후 가장자리까지 점선이 가려지도록 1.55× 이상 유지.
        let trailW = max(baseW * 1.55, max(3.2, lw.core * 2.5))
        let tipW = max(baseW * 1.12, max(3.0, lw.glow * 0.72))

        do {
            var baseSrc = GeoJSONSource(id: FanfolioRoadTripGeoJSONLine.baseSourceId)
            baseSrc.data = .featureCollection(FeatureCollection(features: []))
            try map.addSource(baseSrc)

            var trailSrc = GeoJSONSource(id: FanfolioRoadTripGeoJSONLine.trailSourceId)
            trailSrc.data = .featureCollection(FeatureCollection(features: []))
            try map.addSource(trailSrc)

            var tipSrc = GeoJSONSource(id: FanfolioRoadTripGeoJSONLine.tipSourceId)
            tipSrc.data = .featureCollection(FeatureCollection(features: []))
            try map.addSource(tipSrc)

            var baseLayer = LineLayer(id: FanfolioRoadTripGeoJSONLine.baseLayerId, source: FanfolioRoadTripGeoJSONLine.baseSourceId)
            baseLayer.slot = .top
            baseLayer.lineCap = .constant(.round)
            baseLayer.lineJoin = .constant(.round)
            baseLayer.lineRoundLimit = .constant(1.08)
            baseLayer.lineColor = .constant(StyleColor(Color(white: 0.72).opacity(0.55)))
            baseLayer.lineWidth = .expression(
                Exp(.interpolate) {
                    Exp(.linear); Exp(.zoom)
                    4.0; 0.4
                    9.0; baseW * 0.62
                    13.0; baseW
                }
            )
            baseLayer.lineBlur = .constant(0)
            baseLayer.lineDasharray = .constant([2.2, 2.8])
            baseLayer.lineSortKey = .constant(-20)
            try map.addLayer(baseLayer)

            var trailLayer = LineLayer(id: FanfolioRoadTripGeoJSONLine.trailLayerId, source: FanfolioRoadTripGeoJSONLine.trailSourceId)
            trailLayer.slot = .top
            trailLayer.lineCap = .constant(.round)
            trailLayer.lineJoin = .constant(.round)
            trailLayer.lineRoundLimit = .constant(1.08)
            trailLayer.lineColor = .constant(StyleColor(roadTripLineColor.opacity(0.90)))
            trailLayer.lineWidth = .expression(
                Exp(.interpolate) {
                    Exp(.linear); Exp(.zoom)
                    4.0; 0.7
                    9.0; trailW * 0.58
                    13.0; trailW
                }
            )
            trailLayer.lineBlur = .constant(0.18)
            trailLayer.lineEmissiveStrength = .constant(0.18)
            trailLayer.lineSortKey = .constant(2)
            try map.addLayer(trailLayer, layerPosition: .above(FanfolioRoadTripGeoJSONLine.baseLayerId))

            var tipLayer = LineLayer(id: FanfolioRoadTripGeoJSONLine.tipLayerId, source: FanfolioRoadTripGeoJSONLine.tipSourceId)
            tipLayer.slot = .top
            tipLayer.lineCap = .constant(.round)
            tipLayer.lineJoin = .constant(.round)
            tipLayer.lineRoundLimit = .constant(1.08)
            tipLayer.lineColor = .constant(StyleColor(roadTripGlowLineColor.opacity(0.95)))
            tipLayer.lineWidth = .expression(
                Exp(.interpolate) {
                    Exp(.linear); Exp(.zoom)
                    4.0; 0.9
                    9.0; tipW * 0.60
                    13.0; tipW
                }
            )
            tipLayer.lineBlur = .constant(min(2.0, lw.glowBlur * 0.85))
            tipLayer.lineEmissiveStrength = .constant(0.62)
            tipLayer.lineBorderWidth = .constant(0.18)
            tipLayer.lineSortKey = .constant(12)
            try map.addLayer(tipLayer, layerPosition: .above(FanfolioRoadTripGeoJSONLine.trailLayerId))
        } catch {
            // 스타일 경쟁·릴 중 스타일 재로드 시 실패할 수 있음 — 다음 `onStyleLoaded`에서 재시도.
        }
    }

    private func syncFanfolioRoadTripGeoJSONLineData(map: MapboxMap?) {
        guard let map else { return }
        guard map.sourceExists(withId: FanfolioRoadTripGeoJSONLine.baseSourceId) else { return }

        let empty = GeoJSONObject.featureCollection(FeatureCollection(features: []))

        guard isPro, roadTripActive else {
            map.updateGeoJSONSource(withId: FanfolioRoadTripGeoJSONLine.baseSourceId, geoJSON: empty)
            map.updateGeoJSONSource(withId: FanfolioRoadTripGeoJSONLine.trailSourceId, geoJSON: empty)
            map.updateGeoJSONSource(withId: FanfolioRoadTripGeoJSONLine.tipSourceId, geoJSON: empty)
            return
        }

        let flat = roadTripPolylineFlattenedFullPath
        if flat.count >= 2 {
            let f = Feature(geometry: .lineString(LineString(flat)))
            map.updateGeoJSONSource(withId: FanfolioRoadTripGeoJSONLine.baseSourceId, geoJSON: .feature(f))
        } else {
            map.updateGeoJSONSource(withId: FanfolioRoadTripGeoJSONLine.baseSourceId, geoJSON: empty)
        }

        let trails = roadTripPolylineTrailSegments
        if trails.isEmpty {
            map.updateGeoJSONSource(withId: FanfolioRoadTripGeoJSONLine.trailSourceId, geoJSON: empty)
        } else {
            let features: [Feature] = trails.compactMap { seg in
                guard seg.coordinates.count >= 2 else { return nil }
                return Feature(geometry: .lineString(LineString(seg.coordinates)))
            }
            map.updateGeoJSONSource(withId: FanfolioRoadTripGeoJSONLine.trailSourceId, geoJSON: .featureCollection(FeatureCollection(features: features)))
        }

        let tips = roadTripPolylineActiveTipSegments
        if let tip = tips.first, tip.coordinates.count >= 2 {
            let f = Feature(geometry: .lineString(LineString(tip.coordinates)))
            map.updateGeoJSONSource(withId: FanfolioRoadTripGeoJSONLine.tipSourceId, geoJSON: .feature(f))
        } else {
            map.updateGeoJSONSource(withId: FanfolioRoadTripGeoJSONLine.tipSourceId, geoJSON: empty)
        }
    }

    @MapContentBuilder
    private func stadiumMapMapboxContent() -> some MapContent {
        if isPro,
           roadTripActive,
           highlightReel.phase == .flying,
           highlightReel.segmentIndex < mapModel.roadTripVisualSegments.count,
           let plane = planeCoordinateAndHeading(
               coords: mapModel.roadTripVisualSegments[highlightReel.segmentIndex].coordinates,
               progress: highlightReel.flyProgress
           ) {
            MapViewAnnotation(coordinate: plane.coord) {
                RoadTripFlyingPlaneMarker(
                    flyProgress: highlightReel.flyProgress,
                    heading: plane.heading,
                    headingOffsetDegrees: Self.roadTripPlaneSymbolHeadingOffsetDegrees,
                    spotlightColor: roadTripLineColor
                )
            }
        }

        // `id`는 `StadiumMapVenuePinGroup`의 좌표 키와 동일 — 갱신 시 어노테이션 정체성 유지.
        ForEvery(visiblePinGroups, id: \.id) { group in
            let rep = group.matches[0]
            let atSavedHome = isPro && coordinateIsNearSavedHome(group.coordinate)
            MapViewAnnotation(coordinate: group.coordinate) {
                MatchStadiumMarker(
                    pinColor: pinColorForVenue(matches: group.matches),
                    representativeMatch: rep,
                    matchCount: group.matches.count,
                    isPulsing: isPro
                        && roadTripActive
                        && (highlightReel.pulsingVenueGroupId == group.id
                            || (atSavedHome && highlightReel.pulsingHomeArrival)),
                    isHomeVenue: atSavedHome
                ) {
                    selectedVenueGroupId = group.id
                }
                .scaleEffect(isPro && roadTripActive && highlightReel.showAllArcsSummary ? 0.52 : 1.0, anchor: .bottom)
                .animation(.spring(response: 0.38, dampingFraction: 0.8), value: highlightReel.showAllArcsSummary)
            }
            .allowOverlap(true)
            .variableAnchors([ViewAnnotationAnchorConfig(anchor: .bottom)])
        }

        if isPro,
           let homeCoord = homeCoordinate,
           !mapModel.venuePinGroups.contains(where: { coordinateIsNearSavedHome($0.coordinate) }),
           let orphanRep = folder.matches.first(where: { $0.matchStatus == .completed }) ?? folder.matches.first {
            MapViewAnnotation(coordinate: homeCoord) {
                MatchStadiumMarker(
                    pinColor: Color.from(hex: folder.teamColor) ?? .blue,
                    representativeMatch: orphanRep,
                    matchCount: 0,
                    isPulsing: roadTripActive && highlightReel.pulsingHomeArrival,
                    isHomeVenue: true
                ) {}
            }
            .allowOverlap(true)
            .variableAnchors([ViewAnnotationAnchorConfig(anchor: .bottom)])
        }
    }

    // MARK: - 필터 칩

    private var mapFilterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                StadiumMapFilterChip(
                    title: String(localized: "fanstats.map.filter.all", defaultValue: "전체"),
                    isSelected: selectedSeasonYear == nil && !filterWinsOnly && !filterAwayOnly
                ) {
                    selectedSeasonYear = nil
                    filterWinsOnly = false
                    filterAwayOnly = false
                }
                ForEach(mapModel.seasonYearsInFolder, id: \.self) { year in
                    StadiumMapFilterChip(
                        title: "\(year)",
                        isSelected: selectedSeasonYear == year
                    ) {
                        selectedSeasonYear = selectedSeasonYear == year ? nil : year
                    }
                }
                StadiumMapFilterChip(
                    title: String(localized: "fanstats.map.filter.wins", defaultValue: "승만"),
                    isSelected: filterWinsOnly
                ) {
                    filterWinsOnly.toggle()
                }
                StadiumMapFilterChip(
                    title: String(localized: "fanstats.map.filter.away", defaultValue: "원정만"),
                    isSelected: filterAwayOnly
                ) {
                    filterAwayOnly.toggle()
                }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "fanstats.map.filter.a11y.label", defaultValue: "지도 경기 필터"))
    }

    private var roadTripBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "road.lanes.curved.right")
                .foregroundStyle(roadTripLineColor)
            HStack(spacing: 4) {
                Text(String(localized: "fanstats.map.roadTrip.totalKm.prefix", defaultValue: "필터 기준 이동 경로 합계 약"))
                Text(verbatim: "\(Int(highlightReel.odometerKm.rounded()))")
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: highlightReel.odometerKm))
                Text(String(localized: "fanstats.map.roadTrip.kmUnit", defaultValue: "km"))
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .animation(.default, value: highlightReel.odometerKm)
    }

    // MARK: - 원정 직선

    private func toggleRoadTrip() {
        guard isPro else { return }
        if roadTripActive {
            highlightReel.stop()
            roadTripActive = false
            roadTripReelPreparing = false
            applyInitialCameraIfNeeded()
            return
        }
        syncMapModelFromState()
        let visuals = mapModel.roadTripVisualSegments
        guard !visuals.isEmpty else {
            showToast(
                String(
                    localized: "fanstats.map.roadTrip.noPath",
                    defaultValue: "표시할 원정 경기가 없거나, 이어지는 구간이 한 개뿐입니다. 원정 경기를 2곳 이상 기록해 보세요."
                )
            )
            return
        }
        selectedVenueGroupId = nil
        roadTripActive = true
        roadTripReelPreparing = true
        let totalKm = mapModel.roadTripRoundTripMeters / 1000
        highlightReel.start(
            segments: visuals,
            home: homeCoordinate,
            roundTripTotalKm: totalKm,
            layoutMetrics: roadTripLayoutMetrics,
            updateCamera: { viewport = $0 }
        )
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            if roadTripActive { roadTripReelPreparing = false }
        }
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run {
                toastMessage = nil
            }
        }
    }

    @ViewBuilder
    private var mapEmptyOverlay: some View {
        VStack(spacing: 10) {
            if isBackfillGeocoding {
                ProgressView()
                Text(String(localized: "fanstats.map.empty.geocoding", defaultValue: "구장 위치를 찾는 중…"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if mapModel.totalCompletedInFolder == 0 {
                ContentUnavailableView(
                    String(localized: "fanstats.map.empty.noCompleted.title", defaultValue: "완료된 경기가 없습니다"),
                    systemImage: "map",
                    description: Text(String(localized: "fanstats.map.empty.noCompleted.detail", defaultValue: "경기를 완료로 기록하면 지도에 표시할 수 있습니다."))
                )
            } else if mapModel.filteredCompletedMatches.isEmpty {
                ContentUnavailableView(
                    String(localized: "fanstats.map.empty.filtered.title", defaultValue: "필터에 맞는 경기가 없습니다"),
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(String(localized: "fanstats.map.empty.filtered.detail", defaultValue: "연도·승·원정 필터를 바꿔 보세요."))
                )
            } else {
                ContentUnavailableView(
                    String(localized: "fanstats.map.empty.noPins.title", defaultValue: "아직 핀이 없습니다"),
                    systemImage: "mappin.slash",
                    description: Text(String(localized: "fanstats.map.empty.noPins.detail", defaultValue: "장소를 입력하거나, 잠시 후 자동으로 위치를 찾습니다. 결과가 어긋나면 경기 상세에서 장소를 수정해 보세요."))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(mapModel.mappableMatches.isEmpty && mapModel.totalCompletedInFolder > 0 ? 0.65 : 0.35))
        .allowsHitTesting(false)
    }

    private func applyInitialCameraIfNeeded() {
        guard let region = mapModel.regionEncasingMappableMatches() else {
            if mapModel.mappableMatches.isEmpty {
                viewport = .styleDefault
            }
            return
        }
        viewport = StadiumMapViewport.viewport(from: region)
    }

    private func backfillMissingVenueCoordinates() async {
        let batch = mapModel.matchesMissingVenueCoordinates
        guard !batch.isEmpty else { return }
        await MainActor.run { isBackfillGeocoding = true }

        for match in batch {
            // 1순위: 정적 홈구장 좌표 사전 (NFL·EPL·KBO 홈구장 → 100% 정확)
            if let staticCoord = HomeStadiumCoordinateStore.coordinate(for: match, folder: folder) {
                await MainActor.run { applyVenueCoordinate(staticCoord, to: match) }
                continue
            }
            // 2순위: geocoding (중립 구장·커버 범위 외 리그 폴백)
            guard let raw = match.mapGeocodeQuery else { continue }
            let applyLeagueBias = StadiumGeocodingService.shouldApplyLeagueGeocodeBias(forQuery: raw)
            let bias = applyLeagueBias ? StadiumGeocodingService.preferredSearchRegion(folder: folder) : nil
            let country = applyLeagueBias ? StadiumGeocodingService.preferredISOCountryCode(folder: folder) : nil
            guard let coord = try? await StadiumGeocodingService.coordinate(
                for: raw,
                biasRegion: bias,
                preferredISOCountryCode: country
            ) else { continue }
            await MainActor.run {
                applyVenueCoordinate(coord, to: match)
            }
        }

        await MainActor.run {
            isBackfillGeocoding = false
            syncMapModelFromState()
            applyInitialCameraIfNeeded()
        }
    }

    /// 이 구장(핀 그룹) 직관 기준 승률 = 승 ÷ (승+패). 무승부만이면 팔레트 중립 구간(fair) 색.
    private func pinColorForVenue(matches: [SportsModel]) -> Color {
        guard !matches.isEmpty else { return WinRateTierPalette.pinNoMatches }
        let wins = matches.filter { $0.matchResult == .win }.count
        let losses = matches.filter { $0.matchResult == .loss }.count
        let decisive = wins + losses
        guard decisive > 0 else {
            return WinRateTier.tier(forPercent: 45).accent
        }
        let pct = Double(wins) / Double(decisive) * 100
        return WinRateTierPalette.accentColor(forPercent: pct, hasCompletedGames: true)
    }

    @MainActor
    private func applyVenueCoordinate(_ coord: CLLocationCoordinate2D, to match: SportsModel) {
        guard !match.hasVenueCoordinate else { return }
        applyVenueCoordinateForced(coord, to: match)
    }

    /// 정적 사전 좌표는 기존 좌표가 있어도 덮어씁니다 (geocoding 오염 데이터 정정용).
    /// 좌표가 이미 동일하면 저장하지 않습니다 (불필요한 SwiftData write 방지).
    @MainActor
    private func applyVenueCoordinateForced(_ coord: CLLocationCoordinate2D, to match: SportsModel) {
        let isSame = match.venueLatitude.map { abs($0 - coord.latitude) < 1e-5 } == true
                  && match.venueLongitude.map { abs($0 - coord.longitude) < 1e-5 } == true
        guard !isSame else { return }
        match.venueLatitude = coord.latitude
        match.venueLongitude = coord.longitude
        for ticket in match.savedTickets {
            ticket.latitude = coord.latitude
            ticket.longitude = coord.longitude
        }
        try? modelContext.save()
    }

    /// 정적 홈구장 사전을 전체 완료 경기에 적용합니다.
    /// geocoding으로 잘못 저장된 기존 좌표도 덮어씁니다.
    private func applyStaticStadiumCoordinates() {
        let allCompleted = mapModel.filteredCompletedMatches
        guard !allCompleted.isEmpty else { return }
        Task { @MainActor in
            var didChange = false
            for match in allCompleted {
                guard let staticCoord = HomeStadiumCoordinateStore.coordinate(for: match, folder: folder) else { continue }
                let isSame = match.venueLatitude.map { abs($0 - staticCoord.latitude) < 1e-5 } == true
                          && match.venueLongitude.map { abs($0 - staticCoord.longitude) < 1e-5 } == true
                guard !isSame else { continue }
                applyVenueCoordinateForced(staticCoord, to: match)
                didChange = true
            }
            if didChange {
                syncMapModelFromState()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    visiblePinGroups = mapModel.venuePinGroups
                }
            }
        }
    }

    /// `t0`…`t1` 구간(파라미터는 `coordinateOnPolyline`과 동일한 정규화된 진행도)을 잇는 점열.
    private func roadTripPolylineSlice(_ coords: [CLLocationCoordinate2D], from t0: Double, to t1: Double) -> [CLLocationCoordinate2D] {
        guard coords.count >= 2, t1 > t0 + 1e-5 else { return [] }
        guard let p0 = coordinateOnPolyline(coords, progress: t0),
              let p1 = coordinateOnPolyline(coords, progress: t1) else { return [] }
        let maxIdx = coords.count - 1
        let fi0 = t0 * Double(maxIdx)
        let fi1 = t1 * Double(maxIdx)
        let i0 = min(maxIdx - 1, max(0, Int(floor(fi0))))
        let i1 = min(maxIdx - 1, max(0, Int(floor(fi1))))
        var out: [CLLocationCoordinate2D] = [p0]
        if i1 > i0 {
            for idx in (i0 + 1)...min(i1, maxIdx) {
                out.append(coords[idx])
            }
        }
        if let last = out.last,
           abs(last.latitude - p1.latitude) > 1e-8 || abs(last.longitude - p1.longitude) > 1e-8 {
            out.append(p1)
        }
        return out.count >= 2 ? out : []
    }

    /// 곡선을 따라 `progress`(0…1)까지의 점열 — `MapPolyline`용(미리 계산된 좌표만 슬라이스).
    /// `progress`가 거의 0이면 퇴화 선분을 만들지 않고 빈 배열(릴은 `.flying`/`.legPause`에서만 그림).
    private func roadTripPolylinePrefix(_ coords: [CLLocationCoordinate2D], progress: Double) -> [CLLocationCoordinate2D] {
        guard coords.count >= 2 else { return [] }
        let maxIdx = coords.count - 1
        let t = min(1, max(0, progress))
        if t <= 1e-5 {
            return []
        }

        let floatIndex = t * Double(maxIdx)
        let i = min(maxIdx - 1, max(0, Int(floatIndex)))
        let frac = floatIndex - Double(i)
        if abs(frac) <= 1e-9 {
            if i == 0 {
                return Array(coords[0 ... min(1, maxIdx)])
            }
            return Array(coords[0 ... i])
        }
        let a = coords[i]
        let b = coords[i + 1]
        let mid = CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * frac,
            longitude: a.longitude + (b.longitude - a.longitude) * frac
        )
        var out = Array(coords[0 ... i])
        out.append(mid)
        return out
    }

    private func coordinateOnPolyline(_ coords: [CLLocationCoordinate2D], progress: Double) -> CLLocationCoordinate2D? {
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

    private func bearingDegrees(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }

    private func planeCoordinateAndHeading(
        coords: [CLLocationCoordinate2D],
        progress: Double
    ) -> (coord: CLLocationCoordinate2D, heading: Angle)? {
        guard let c = coordinateOnPolyline(coords, progress: progress) else { return nil }
        let ahead = min(1, progress + 0.035)
        let c2 = coordinateOnPolyline(coords, progress: ahead) ?? c
        let brng = bearingDegrees(from: c, to: c2)
        return (c, .degrees(brng))
    }
}

private extension FolderStadiumMapView {
    /// 네이비 톤 맵 위에서 팀 컬러 글로우가 죽지 않도록 HSB 기준으로 채도·명도 보강.
    static func boostedGlowColor(from base: Color) -> Color {
        let ui = UIColor(base)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return base }
        let ns = min(1, s + 0.17)
        let nb = min(1, b + 0.1)
        return Color(UIColor(hue: h, saturation: ns, brightness: nb, alpha: a))
    }

    /// 실크 트레일: 극슬림 코어 + 얇은 팀 글로우(줌 고정).
    static let roadTripLineWidthsSilkTrail: (glow: Double, core: Double, glowBlur: Double, coreBlur: Double) = (
        glow: 6,
        core: 1.2,
        glowBlur: 2.5,
        coreBlur: 0.2
    )

    /// 전체 여정 가이드(회색 점선) — 실크 코어와 무관하게 **읽기 쉬운 두께**로 둠. dash 단위는 선 굵기 배수.
    static let roadTripBaseGuideLineWidth: Double = 3.4
}

// MARK: - 원정 릴 요약 카드

private struct RoadTripSummaryCard: View {
    let totalKm: Int
    let venueCount: Int
    let winRateText: String
    let accentColor: Color
    let onDismiss: () -> Void
    /// 지도 스냅샷 캡처 클로저 — `nil`이면 공유 버튼을 비활성화.
    var onCaptureMapSnapshot: (() -> UIImage?)?

    @State private var isPreparingShare = false
    @State private var showShareSheet = false
    @State private var shareActivityItems: [Any] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "fanstats.map.roadTrip.summary.title", defaultValue: "원정 하이라이트 요약"))
                    .font(.headline)
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "fanstats.map.roadTrip.summary.close.a11y", defaultValue: "요약 닫기"))
            }

            HStack(spacing: 0) {
                summaryColumn(
                    title: String(localized: "fanstats.map.roadTrip.summary.stat.km", defaultValue: "총 거리"),
                    value: "\(totalKm) km"
                )
                .padding(.leading, 2)
                .padding(.trailing, 6)

                summaryStatDivider

                summaryColumn(
                    title: String(localized: "fanstats.map.roadTrip.summary.stat.venues", defaultValue: "구장 수"),
                    value: "\(venueCount)"
                )
                .padding(.horizontal, 6)

                summaryStatDivider

                summaryColumn(
                    title: String(localized: "fanstats.map.roadTrip.summary.stat.winRate", defaultValue: "필터 승률"),
                    value: winRateText
                )
                .padding(.leading, 6)
                .padding(.trailing, 2)
            }

            HStack(spacing: 12) {
                Button {
                    Task { @MainActor in
                        isPreparingShare = true
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        if let raw = onCaptureMapSnapshot?(),
                           let composed = RoadTripMapSnapshotComposer.compose(
                               mapSnapshot: raw,
                               totalKm: totalKm,
                               venueCount: venueCount,
                               winRateText: winRateText,
                               accentColor: accentColor
                           ) {
                            shareActivityItems = [composed]
                            showShareSheet = true
                        }
                        isPreparingShare = false
                    }
                } label: {
                    Group {
                        if isPreparingShare {
                            Label(
                                String(localized: "fanstats.map.roadTrip.summary.share.preparing", defaultValue: "이미지 생성 중…"),
                                systemImage: "camera.viewfinder"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        } else {
                            Label(
                                String(localized: "fanstats.map.roadTrip.summary.share", defaultValue: "공유"),
                                systemImage: "square.and.arrow.up"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isPreparingShare || onCaptureMapSnapshot == nil)
                .accessibilityHint(
                    String(
                        localized: "fanstats.map.roadTrip.summary.share.a11y.hint",
                        defaultValue: "지도 경로와 하이라이트 요약이 담긴 이미지를 공유합니다."
                    )
                )

                Button {
                    onDismiss()
                } label: {
                    Text(String(localized: "fanstats.map.roadTrip.summary.done", defaultValue: "완료"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(isPreparingShare)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 18, y: 8)
        }
        .groupedCardOutline(cornerRadius: 22)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(cardAccessibilitySummary)
        .sheet(isPresented: $showShareSheet) {
            FanfolioShareSheet(items: shareActivityItems)
        }
    }

    private var cardAccessibilitySummary: String {
        let template = String(
            localized: "fanstats.map.roadTrip.summary.card.a11y",
            defaultValue: "원정 하이라이트 요약 카드. 총 거리 %d km, 방문 구장 %d곳, 승률 %@"
        )
        return String.localizedStringWithFormat(template, totalKm, venueCount, winRateText)
    }

    private var summaryStatDivider: some View {
        Divider()
            .frame(height: 38)
    }

    private func summaryColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 공유 시트에 첨부할 원정 궤적(GPX / GeoJSON LineString).
private enum RoadTripRouteShareBuilder {
    private static let coordTolerance = 1e-7

    static func flattenedCoordinates(segments: [RoadTripVisualSegment]) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        let cap = segments.reduce(0) { $0 + $1.coordinates.count }
        result.reserveCapacity(max(0, cap))
        for segment in segments {
            let coords = segment.coordinates
            guard !coords.isEmpty else { continue }
            if result.isEmpty {
                result.append(contentsOf: coords)
                continue
            }
            let first = coords[0]
            if let last = result.last, coordinatesEqual(last, first) {
                result.append(contentsOf: coords.dropFirst())
            } else {
                result.append(contentsOf: coords)
            }
        }
        return result
    }

    private static func coordinatesEqual(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < coordTolerance && abs(a.longitude - b.longitude) < coordTolerance
    }

    static func writeGPXFile(coordinates: [CLLocationCoordinate2D], trackName: String) -> URL? {
        guard !coordinates.isEmpty else { return nil }
        let safeName = escapeXmlForGPX(trackName)
        var body =
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="Fanfolio" xmlns="http://www.topografix.com/GPX/1/1">
            <trk><name>\(safeName)</name><trkseg>
            """
        for c in coordinates where c.latitude.isFinite && c.longitude.isFinite {
            body += "<trkpt lat=\"\(c.latitude)\" lon=\"\(c.longitude)\"></trkpt>\n"
        }
        body += "</trkseg></trk></gpx>"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fanfolio-roadtrip-\(UUID().uuidString).gpx")
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func writeGeoJSONLineStringFile(coordinates: [CLLocationCoordinate2D]) -> URL? {
        let arr: [[Double]] = coordinates.compactMap { c in
            guard c.latitude.isFinite, c.longitude.isFinite else { return nil }
            return [c.longitude, c.latitude]
        }
        guard arr.count >= 2 else { return nil }
        let feature: [String: Any] = [
            "type": "Feature",
            "properties": ["name": "Fanfolio road trip"] as [String: Any],
            "geometry": [
                "type": "LineString",
                "coordinates": arr
            ] as [String: Any]
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: feature, options: [.prettyPrinted])
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fanfolio-roadtrip-\(UUID().uuidString).geojson")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func escapeXmlForGPX(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

/// 공유 시트에 넘길 요약 카드 PNG (`사진에 저장` 등 이미지 활동 표시용).
private enum RoadTripSummaryShareImageBuilder {
    @MainActor
    static func makeImage(
        totalKm: Int,
        venueCount: Int,
        winRateText: String,
        accentColor: Color
    ) -> UIImage? {
        let content = RoadTripShareExportView(
            totalKm: totalKm,
            venueCount: venueCount,
            winRateText: winRateText,
            accentColor: accentColor
        )
        .frame(width: 400, height: 232)
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(UITraitCollection.current.displayScale, 1)
        return renderer.uiImage
    }
}

private struct RoadTripShareExportView: View {
    let totalKm: Int
    let venueCount: Int
    let winRateText: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "fanstats.map.roadTrip.summary.title", defaultValue: "원정 하이라이트 요약"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 0) {
                exportColumn(
                    title: String(localized: "fanstats.map.roadTrip.summary.stat.km", defaultValue: "총 거리"),
                    value: "\(totalKm) km"
                )
                exportDivider
                exportColumn(
                    title: String(localized: "fanstats.map.roadTrip.summary.stat.venues", defaultValue: "구장 수"),
                    value: "\(venueCount)"
                )
                exportDivider
                exportColumn(
                    title: String(localized: "fanstats.map.roadTrip.summary.stat.winRate", defaultValue: "필터 승률"),
                    value: winRateText
                )
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(accentColor.opacity(0.65), lineWidth: 2)
        }
    }

    private var exportDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.22))
            .frame(width: 1, height: 42)
            .padding(.horizontal, 8)
    }

    private func exportColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.65))
            Text(verbatim: value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 궤적은 지면 폴리라인에 두고, 비행기만 `offset`·`sin`으로 공중 궤적 느낌을 냅니다.
private struct RoadTripFlyingPlaneMarker: View {
    var flyProgress: Double
    var heading: Angle
    var headingOffsetDegrees: Double
    /// 지면에 깔리는 팀 컬러 포인트 광원(손전등).
    var spotlightColor: Color

    var body: some View {
        let flightSine = sin(flyProgress * .pi)
        let altitudeOffset = CGFloat(flightSine) * 65
        let planeScale = 1.0 + CGFloat(flightSine) * 0.4
        let spotlightIntensity = 0.28 + CGFloat(flightSine) * 0.22

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            spotlightColor.opacity(0.5 * Double(spotlightIntensity)),
                            spotlightColor.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: 58
                    )
                )
                .frame(width: 118, height: 118)
                .blur(radius: 11)

            Ellipse()
                .fill(Color.black.opacity(0.32))
                .frame(width: 16, height: 8)
                .scaleEffect(1.0 - CGFloat(flightSine) * 0.5)
                .blur(radius: CGFloat(flightSine) * 3)

            Image(systemName: "airplane.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.white.opacity(0.85))
                .rotationEffect(heading + .degrees(headingOffsetDegrees))
                .scaleEffect(planeScale)
                .offset(y: -altitudeOffset)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(localized: "fanstats.map.roadTrip.plane.a11y", defaultValue: "원정 경로상 비행기 위치")
        )
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - 지도 스냅샷 합성기

/// 캡처된 지도 UIImage 아래에 팀 컬러 stats 바를 합성해 공유용 고화질 이미지를 반환합니다.
private enum RoadTripMapSnapshotComposer {
    @MainActor
    static func compose(
        mapSnapshot: UIImage,
        totalKm: Int,
        venueCount: Int,
        winRateText: String,
        accentColor: Color
    ) -> UIImage? {
        let scale = mapSnapshot.scale  // 캡처 원본 scale(@3x 등) 그대로 유지
        let mapW = mapSnapshot.size.width   // pt 단위
        let mapH = mapSnapshot.size.height  // pt 단위
        let barH: CGFloat = 80

        let statsBar = RoadTripMapSnapshotStatsBar(
            totalKm: totalKm,
            venueCount: venueCount,
            winRateText: winRateText,
            accentColor: accentColor,
            width: mapW
        )
        .frame(width: mapW, height: barH)

        let barRenderer = ImageRenderer(content: statsBar)
        barRenderer.scale = scale
        barRenderer.proposedSize = ProposedViewSize(width: mapW, height: barH)
        guard let barImage = barRenderer.uiImage else { return mapSnapshot }

        // 출력 크기 = 지도 원본 그대로(9:16 유지) — stats 바는 하단에 오버레이
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: CGSize(width: mapW, height: mapH), format: format).image { _ in
            mapSnapshot.draw(at: .zero)
            barImage.draw(at: CGPoint(x: 0, y: mapH - barH))
        }
    }
}

/// 합성 이미지 하단 stats 바 뷰 (지도 폭에 맞게 늘어남).
private struct RoadTripMapSnapshotStatsBar: View {
    let totalKm: Int
    let venueCount: Int
    let winRateText: String
    let accentColor: Color
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        String(
                            localized: "fanstats.map.roadTrip.snapshot.totalKm",
                            defaultValue: "총 \(totalKm) km"
                        )
                    )
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                    HStack(spacing: 6) {
                        Text(
                            String(
                                format: String(
                                    localized: "fanstats.map.roadTrip.snapshot.venues",
                                    defaultValue: "구장 %d곳"
                                ),
                                venueCount
                            )
                        )
                        Text(verbatim: "·")
                            .foregroundStyle(Color.white.opacity(0.45))
                        Text(
                            String(
                                localized: "fanstats.map.roadTrip.snapshot.winRate",
                                defaultValue: "승률 \(winRateText)"
                            )
                        )
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                }
                .padding(.leading, 12)

                Spacer(minLength: 8)

                Text("Fanfolio")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.trailing, 14)
            }
        }
        .frame(width: width, height: 80)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
    }
}

// MARK: - 필터 칩

private struct StadiumMapFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.22) : Color(uiColor: .tertiarySystemFill))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : .primary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 마커

private struct MatchStadiumMarker: View {
    /// 구장 단위 승률에 따라 부모에서 계산한 색.
    let pinColor: Color
    /// 접근성·단일 경기 설명용(가장 최근 경기).
    let representativeMatch: SportsModel
    var matchCount: Int
    /// 원정 릴 도착 순간 강조.
    var isPulsing: Bool = false
    /// 저장된 홈 구장이면 맵핀 대신 별 마커(`star.circle.fill`)만 사용.
    var isHomeVenue: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if isHomeVenue {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 38))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .yellow)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    } else {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 38))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, pinColor)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    }
                }

                if matchCount > 1 {
                    Text(verbatim: "\(matchCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red.opacity(0.92)))
                        .offset(x: 8, y: -6)
                }
            }
            .scaleEffect(isPulsing ? 1.1 : 1)
            .animation(
                isPulsing ? .easeInOut(duration: 0.42).repeatForever(autoreverses: true) : .default,
                value: isPulsing
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(markerAccessibilityLabel)
    }

    private var markerAccessibilityLabel: String {
        let base = matchCount > 1
            ? String(
                format: String(localized: "fanstats.map.marker.a11y.venueCount", defaultValue: "이 구장 경기 %1$d건"),
                locale: .autoupdatingCurrent,
                matchCount
            )
            : String(
                format: String(localized: "fanstats.map.marker.a11y", defaultValue: "%1$@ 대 %2$@, %3$@"),
                locale: .autoupdatingCurrent,
                KBOTeamLogoAsset.uiDisplayName(forTeamName: representativeMatch.team1Display, leagueCode: representativeMatch.folder?.leagueCode),
                KBOTeamLogoAsset.uiDisplayName(forTeamName: representativeMatch.opponentTeam, leagueCode: representativeMatch.folder?.leagueCode),
                representativeMatch.matchResult.displayName
            )
        if isHomeVenue {
            return base + ", " + String(localized: "fanstats.map.marker.a11y.homeVenue", defaultValue: "홈 구장")
        }
        return base
    }
}

// MARK: - 콜아웃 (같은 구장 여러 경기)

private struct VenueMatchesCalloutCard: View {
    let group: StadiumMapVenuePinGroup
    var roadTripPhaseLabel: String?
    var showsCloseButton: Bool = true
    /// 릴 콜아웃 등 경기가 많을 때 스크롤 상한(pt). `nil`이면 280.
    var listMaxHeight: CGFloat?
    let onClose: () -> Void
    let onOpenTicketViewer: (SavedTicket) -> Void

    private var scrollListMaxHeight: CGFloat {
        min(CGFloat(group.matches.count) * 88 + 16, listMaxHeight ?? 280)
    }

    /// 사용자 입력 장소 우선, 없으면 첫 경기의 지오코딩용 문자열.
    private var venueSummaryLine: String? {
        for m in group.matches {
            let t = m.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty { return t }
        }
        return group.matches.first?.mapGeocodeQuery
    }

    private static let rowDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("yyyyMMMd")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 0)
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 40, height: 5)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let roadTripPhaseLabel {
                        Text(roadTripPhaseLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(String(localized: "fanstats.map.callout.venueTitle", defaultValue: "이 구장에서"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        String(
                            format: String(localized: "fanstats.map.callout.matchCount", defaultValue: "경기 %lld건"),
                            locale: .autoupdatingCurrent,
                            Int64(group.matches.count)
                        )
                    )
                    .font(.headline)
                    if let venue = venueSummaryLine {
                        Label(venue, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)

                if showsCloseButton {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "fanstats.map.callout.close.a11y", defaultValue: "콜아웃 닫기"))
                }
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(group.matches) { match in
                        VenueMatchCalloutRow(
                            match: match,
                            dateString: match.date.map { Self.rowDateFormatter.string(from: $0) },
                            onOpenTicket: { ticket in onOpenTicketViewer(ticket) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: scrollListMaxHeight)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        )
    }
}

private struct VenueMatchCalloutRow: View {
    let match: SportsModel
    var dateString: String?
    let onOpenTicket: (SavedTicket) -> Void

    private var team1UI: String {
        KBOTeamLogoAsset.uiDisplayName(forTeamName: match.team1Display, leagueCode: match.folder?.leagueCode)
    }
    private var team2UI: String {
        KBOTeamLogoAsset.uiDisplayName(forTeamName: match.opponentTeam, leagueCode: match.folder?.leagueCode)
    }

    private var preferredTicket: SavedTicket? {
        match.savedTickets.sorted { $0.createdAt > $1.createdAt }.first
    }

    var body: some View {
        HStack(spacing: 12) {
            rowThumbnail
                .frame(width: 52, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "\(team1UI) vs \(team2UI)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(verbatim: "\(match.myTeamScore)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                    Text(":")
                        .foregroundStyle(.secondary)
                    Text(verbatim: "\(match.opponentScore)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                    Text(verbatim: "·")
                        .foregroundStyle(.tertiary)
                    Text(match.matchResult.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(match.matchResult.color)
                }
                if let dateString {
                    Text(dateString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                NavigationLink {
                    SportsDetailView(match: match)
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                if let ticket = preferredTicket {
                    Button {
                        onOpenTicket(ticket)
                    } label: {
                        Image(systemName: "ticket.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var rowThumbnail: some View {
        if let ticket = preferredTicket,
           let image = TicketImageStore.loadImageCached(path: ticket.thumbnailPath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
                .overlay {
                    Image(systemName: "sportscourt")
                        .foregroundStyle(.tertiary)
                }
        }
    }
}
