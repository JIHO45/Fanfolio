//
//  LiveActivityManager.swift
//  Fanfolio
//
//  본 앱 타겟 전용. Widget Extension에는 포함하지 마세요.
//
//  역할
//  - 라이브 액티비티(ActivityKit)의 시작/업데이트/종료를 한 곳에서 관리
//  - `activityStateUpdates` AsyncSequence를 구독해 유저가 강제로 닫은 경우(dismissed/ended)를
//    감지하여, 본 앱에서 더 이상 업데이트를 시도하지 않도록 currentActivity를 해제
//
//  주의 (백그라운드 폴링 한계)
//  - 본 앱의 폴링은 Foreground에서만 동작합니다.
//  - 잠금화면 상태에서도 실시간 점수가 바뀌게 하려면 ActivityKit Push(APNs) 서버 연동이 필요합니다.
//  - 현재 구현은 "Foreground 진입 시 최신 스코어를 위젯에 반영"하는 반쪽짜리 구현입니다.
//

import Foundation
import ActivityKit
import os.log

@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()

    private init() {}

    // MARK: - 상태

    /// 현재 띄운 액티비티. dismissed/ended 시 자동으로 nil로 비워집니다.
    private(set) var currentActivity: Activity<LiveScoreAttributes>?

    /// 현재 액티비티가 추적 중인 외부 경기 ID. 중복 start 방지용.
    private(set) var currentEventID: String?

    /// activityStateUpdates 구독 Task. 새 액티비티를 시작하면 기존 Task는 취소됩니다.
    private var stateObservationTask: Task<Void, Never>?

    // MARK: - 가능 여부

    /// 시스템 설정에서 라이브 액티비티가 허용되어 있는지.
    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - 시작

    /// `LiveFixture`를 받아 라이브 액티비티를 시작합니다.
    /// 이미 같은 `externalEventID`로 진행 중이라면 시작하지 않고 업데이트만 수행합니다.
    ///
    /// - Parameters:
    ///   - fixture: 현재 진행/임박 경기 정보
    ///   - externalEventID: 본 앱이 관리하는 경기 고유 키 (예: "espn:401547439", "firestore-kbo:20260512_DOOSAN_LG")
    ///   - leagueCode: 리그 코드 (예: "KBO", "EPL")
    ///   - homeAssetImageName: 번들 에셋 이미지 이름 (KBO 전용, 없으면 nil)
    ///   - awayAssetImageName: 번들 에셋 이미지 이름 (KBO 전용, 없으면 nil)
    func startActivity(
        fixture: LiveFixture,
        externalEventID: String,
        leagueCode: String,
        homeAssetImageName: String?,
        awayAssetImageName: String?
    ) {
        guard isAvailable else {
            Logger.liveActivity.info("시작 불가: 시스템 라이브 액티비티 비활성화")
            return
        }

        // 이미 같은 경기로 띄워져 있으면 update만 시도하고 종료
        if let current = currentActivity,
           currentEventID == externalEventID,
           current.activityState == .active {
            Task { await self.updateActivity(fixture: fixture) }
            return
        }

        // 다른 경기를 추적 중이면 그것부터 즉시 종료
        if currentActivity != nil {
            Task { await self.endActivityImmediately() }
        }

        let attributes = LiveScoreAttributes(
            homeTeamName: fixture.homeTeam.name,
            awayTeamName: fixture.awayTeam.name,
            homeTeamAssetImageName: homeAssetImageName,
            awayTeamAssetImageName: awayAssetImageName,
            homeTeamAbbreviation: fixture.homeTeam.abbreviation,
            awayTeamAbbreviation: fixture.awayTeam.abbreviation,
            leagueCode: leagueCode,
            externalEventID: externalEventID
        )

        let state = makeContentState(from: fixture)
        let content = ActivityContent(state: state, staleDate: Self.staleDate(for: fixture))

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil // Foreground 업데이트 전용. 서버 푸시 도입 시 .token으로 변경.
            )
            self.currentActivity = activity
            self.currentEventID = externalEventID
            observeStateUpdates(for: activity)
            Logger.liveActivity.info("시작: id=\(activity.id, privacy: .public), event=\(externalEventID, privacy: .public)")
        } catch {
            Logger.liveActivity.error("시작 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 업데이트

    /// 현재 추적 중인 액티비티를 최신 fixture로 갱신합니다.
    /// - 유저가 강제 종료한 경우(currentActivity == nil)나 비활성 상태에서는 조용히 무시됩니다.
    /// - 경기가 종료(`isFinished == true`)되면 자동으로 endActivity를 호출합니다.
    func updateActivity(fixture: LiveFixture) async {
        guard let activity = currentActivity else { return }
        guard activity.activityState == .active else {
            Logger.liveActivity.info("업데이트 건너뜀: 액티비티 비활성 상태(\(String(describing: activity.activityState), privacy: .public))")
            return
        }

        let state = makeContentState(from: fixture)
        let content = ActivityContent(state: state, staleDate: Self.staleDate(for: fixture))

        await activity.update(content)

        if fixture.status.isFinished {
            await endActivity(finalFixture: fixture)
        }
    }

    // MARK: - 종료

    /// 경기 종료 시 최종 상태로 마무리. 잠금화면에는 시스템 정책에 따라 잠시 남습니다(.default).
    func endActivity(finalFixture: LiveFixture? = nil) async {
        guard let activity = currentActivity else { return }

        let finalState: LiveScoreAttributes.ContentState = {
            if let fixture = finalFixture {
                return makeContentState(from: fixture)
            } else {
                return activity.content.state
            }
        }()

        let content = ActivityContent(state: finalState, staleDate: nil)
        await activity.end(content, dismissalPolicy: .default)

        Logger.liveActivity.info("종료: id=\(activity.id, privacy: .public)")
        cleanupLocalState()
    }

    /// 사용자가 폴더를 닫거나 다른 경기로 전환할 때, 잠금화면에서 즉시 사라지게 종료.
    func endActivityImmediately() async {
        guard let activity = currentActivity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        Logger.liveActivity.info("즉시 종료: id=\(activity.id, privacy: .public)")
        cleanupLocalState()
    }

    /// 앱 실행 시 호출하여, 시스템에 남아있는 우리 액티비티(앱 강제종료 후 재실행 등)를 다시 추적.
    /// - 여러 개 남아있으면 활성 상태인 가장 최근 것 하나만 유지하고 나머지는 즉시 종료.
    func reattachOnLaunch() {
        let activities = Activity<LiveScoreAttributes>.activities
        guard !activities.isEmpty else { return }

        // 가장 활성도 높은 액티비티 하나 선택
        let pick = activities.first(where: { $0.activityState == .active }) ?? activities.first
        guard let pick else { return }

        self.currentActivity = pick
        self.currentEventID = pick.attributes.externalEventID
        observeStateUpdates(for: pick)
        Logger.liveActivity.info("재연결: id=\(pick.id, privacy: .public), event=\(pick.attributes.externalEventID, privacy: .public)")

        // 그 외 잔여 액티비티는 즉시 종료해서 중복 표시 방지
        Task {
            for stale in activities where stale.id != pick.id {
                await stale.end(nil, dismissalPolicy: .immediate)
                Logger.liveActivity.info("잔여 액티비티 정리: id=\(stale.id, privacy: .public)")
            }
        }
    }

    // MARK: - 내부 유틸

    /// `LiveFixture` → `ContentState` 변환.
    private func makeContentState(from fixture: LiveFixture) -> LiveScoreAttributes.ContentState {
        LiveScoreAttributes.ContentState(
            homeScore: fixture.score.home ?? 0,
            awayScore: fixture.score.away ?? 0,
            matchStatus: fixture.status.displayText,
            rawStatusShort: fixture.status.short,
            isLive: fixture.status.isLive,
            isFinished: fixture.status.isFinished
        )
    }

    /// `activityStateUpdates`를 구독하여 dismissed/ended로 바뀌면 로컬 상태를 정리.
    private func observeStateUpdates(for activity: Activity<LiveScoreAttributes>) {
        stateObservationTask?.cancel()
        let observedID = activity.id

        stateObservationTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                Logger.liveActivity.info("상태 변경: id=\(observedID, privacy: .public) → \(String(describing: state), privacy: .public)")
                switch state {
                case .ended, .dismissed, .stale:
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        // 우리가 추적하던 동일한 활동인 경우에만 정리
                        if self.currentActivity?.id == observedID {
                            self.cleanupLocalState()
                        }
                    }
                    return
                case .active:
                    continue
                default:
                    continue
                }
            }
        }
    }

    /// 로컬 추적 상태만 비웁니다 (시스템 액티비티에는 영향 없음).
    private func cleanupLocalState() {
        currentActivity = nil
        currentEventID = nil
        stateObservationTask?.cancel()
        stateObservationTask = nil
    }

    /// staleDate: 라이브면 5분, 예정/미정이면 30분 후로 두어 위젯이 "오래된 데이터" UI로 전환되도록.
    private static func staleDate(for fixture: LiveFixture) -> Date? {
        if fixture.status.isFinished { return nil }
        let seconds: TimeInterval = fixture.status.isLive ? 5 * 60 : 30 * 60
        return Date().addingTimeInterval(seconds)
    }
}
