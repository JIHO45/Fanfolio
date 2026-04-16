//
//  LeagueStandingsView.swift
//  Fanfolio
//
//  팀 폴더의 리그 순위표 (ESPN 지원 리그 + KBO)
//

import SwiftUI
import SwiftData

struct LeagueStandingsView: View {
    let folder: SportsFanFolder

    @State private var payload: LeagueStandingsPayload?
    @State private var loadError: String?
    @State private var isLoading = false

    private var leagueCode: String { folder.leagueCode ?? "" }
    private var isKBO: Bool { leagueCode == "KBO" }

    /// ESPN 리그: ESPN 팀 ID로 하이라이트
    private var highlightEspnTeamId: String? {
        guard !isKBO,
              let t = ESPNTeamsLoader.team(name: folder.name, leagueCode: folder.leagueCode),
              !t.id.isESPNFakeID else { return nil }
        return t.id
    }

    /// KBO: API-Sports 팀 ID로 하이라이트
    private var highlightKboTeamId: String? {
        guard isKBO, let tid = folder.apiSportsTeamID else { return nil }
        return "\(tid)"
    }

    private var highlightId: String? { isKBO ? highlightKboTeamId : highlightEspnTeamId }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                Text(err)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if let payload {
                standingsContent(payload)
            } else {
                Text(String(localized: "standings.empty", defaultValue: "순위 데이터가 없습니다."))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(String(localized: "standings.title", defaultValue: "리그 순위"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(folder.persistentModelID)\u{1f}\(leagueCode)") {
            await load(forceRefresh: false)
        }
        .refreshable {
            await load(forceRefresh: true)
        }
    }

    @ViewBuilder
    private func standingsContent(_ payload: LeagueStandingsPayload) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch payload {
                case .winPct(let config, let sections):
                    WinPctStandingsView(
                        config: config,
                        sections: sections,
                        highlightTeamId: highlightId
                    )
                case .soccer(_, let sections):
                    SoccerStandingsView(
                        sections: sections,
                        highlightTeamId: highlightId
                    )
                }
            }
            .padding()
        }
    }

    private func load(forceRefresh: Bool) async {
        guard !leagueCode.isEmpty else {
            loadError = String(localized: "standings.error.noLeague", defaultValue: "리그 정보가 없어 순위를 불러올 수 없습니다.")
            return
        }

        // KBO: Firestore games 캐시에서 직접 순위 계산 (API 추가 호출 없음)
        if isKBO {
            guard !APIConfig.firebaseProjectID.isEmpty else {
                loadError = String(
                    localized: "standings.kbo.error.notConfigured",
                    defaultValue: "Firebase 설정이 필요합니다. APIKeys.xcconfig에 FIREBASE_PROJECT_ID를 추가하세요."
                )
                return
            }
            let showSpinner = !forceRefresh && payload == nil
            if showSpinner { isLoading = true }
            loadError = nil
            defer { if showSpinner { isLoading = false } }
            do {
                payload = try await KBOFirestoreService.shared.computeKBOStandings(forceRefresh: forceRefresh)
            } catch {
                loadError = error.localizedDescription
            }
            return
        }

        // ESPN 지원 리그
        guard ESPNPlayerService.shared.supportsLiveScoreboard(leagueCode) else {
            loadError = String(
                localized: "standings.error.unsupportedLeague",
                defaultValue: "이 리그는 순위를 지원하지 않습니다."
            )
            return
        }
        let showBlockingSpinner = !forceRefresh && payload == nil
        if showBlockingSpinner { isLoading = true }
        if !forceRefresh { loadError = nil }
        defer { if showBlockingSpinner { isLoading = false } }
        do {
            payload = try await StandingsCache.shared.payload(leagueCode: leagueCode, forceRefresh: forceRefresh)
            loadError = nil
        } catch let e as ESPNServiceError {
            loadError = e.localizedDescription
        } catch {
            loadError = error.localizedDescription
        }
    }
}
