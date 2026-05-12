//
//  SportsMatchesTab.swift
//  Fanfolio
//

import SwiftUI
import SwiftData

/// SportsView 하단 탭 중 '경기' 탭.
/// 실시간 스코어보드, 예정/완료 경기 목록을 표시합니다.
struct SportsMatchesTab: View {
    let folder: SportsFanFolder
    let viewModel: SportsLiveScoreViewModel

    /// 경기 추가 시트 — 상위 SportsView의 툴바 버튼과 공유
    @Binding var showingAddMatchSheet: Bool
    /// 경기 불러오기 시트 — 상위 SportsView의 툴바 메뉴와 공유
    @Binding var showingMatchSheet: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var matchToDelete: SportsModel?
    @State private var showingDeleteMatchAlert = false

    // MARK: - 경기 목록 계산

    private var activeMatches: [SportsModel] {
        folder.matches
            .filter { $0.matchStatus == .upcoming }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    private var completedMatches: [SportsModel] {
        folder.matches
            .filter { $0.matchStatus == .completed }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // 실시간 스코어보드 섹션 (기타 카테고리 제외)
                if folder.sportType != .other {
                    if !viewModel.scoreboardRelevantFixtures.isEmpty || viewModel.isLoadingLive {
                        liveScoreboardSection
                    }

                    let leagueCode = folder.leagueCode ?? ""
                    if ESPNPlayerService.shared.shouldPromptForMissingAPISportsKey(leagueCode: leagueCode)
                        && viewModel.scoreboardRelevantFixtures.isEmpty && !viewModel.isLoadingLive {
                        liveScoreAPIKeyPrompt
                    }
                }

                // 에러 배너
                if let error = viewModel.liveLoadError {
                    errorBanner(message: error)
                }

                // 예정 경기
                if !activeMatches.isEmpty {
                    sectionHeader(
                        title: String(localized: "sports.section.upcomingMatches", defaultValue: "예정"),
                        iconName: "clock",
                        count: activeMatches.count
                    )
                    ForEach(activeMatches) { match in
                        matchRow(match: match)
                    }
                }

                // 완료된 경기
                if !completedMatches.isEmpty {
                    sectionHeader(
                        title: String(localized: "common.section.completed", defaultValue: "완료"),
                        iconName: "checkmark.circle",
                        count: completedMatches.count
                    )
                    ForEach(completedMatches) { match in
                        matchRow(match: match)
                    }
                }

                // 빈 상태 안내
                if folder.matches.isEmpty && viewModel.scoreboardRelevantFixtures.isEmpty && !viewModel.isLoadingLive {
                    ContentUnavailableView(
                        String(localized: "sports.list.emptyTitle", defaultValue: "경기 기록이 없습니다"),
                        systemImage: folder.sportType.iconName,
                        description: Text(String(localized: "sports.list.emptyDescription", defaultValue: "+ 버튼을 눌러 첫 경기를 기록해보세요!"))
                    )
                    .padding(.top, 16)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.fetchLiveScores(showLoadingUI: false)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $showingAddMatchSheet) {
            AddSportsMatchView(
                folder: folder,
                nextOrderIndex: folder.matches.count
            )
        }
        .sheet(isPresented: $showingMatchSheet) {
            MatchListView(folder: folder)
        }
    }

    // MARK: - 실시간 스코어보드 섹션

    private var liveScoreboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if viewModel.isLoadingLive {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(String(localized: "sports.live.loading", defaultValue: "실시간 스코어 로딩 중…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if viewModel.scoreboardRelevantFixtures.contains(where: \.isLive) {
                        LiveIndicator()
                        Text(String(localized: "sports.live.header.live", defaultValue: "실시간 스코어"))
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "sportscourt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "sports.live.header.games", defaultValue: "경기 스코어"))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    Text(String(localized: "sports.live.pullRefresh", defaultValue: "· 아래로 당겨서 새로고침"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            if !viewModel.scoreboardRelevantFixtures.isEmpty {
                LiveScoreboardSection(fixtures: viewModel.scoreboardRelevantFixtures, sportType: folder.sportType)
            }
        }
        .padding(.top, 4)
    }

    private var liveScoreAPIKeyPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "sports.live.apiKey.title", defaultValue: "실시간 스코어 미설정"))
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text(String(localized: "sports.live.apiKey.message", defaultValue: "APIKeys.xcconfig에 API_SPORTS_KEY를 설정하면 실시간 스코어를 이용할 수 있습니다. example 파일을 복사해 사용하세요."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            let limiter = APIRateLimiter.shared
            if limiter.callCount > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: String(localized: "sports.live.api.callsRemaining", defaultValue: "%lld회 남음"), locale: .autoupdatingCurrent, Int64(limiter.remainingCalls)))
                        .font(.caption2.bold())
                        .foregroundStyle(limiter.remainingCalls < 20 ? .orange : .secondary)
                    Text(String(localized: "sports.live.api.todayRemaining", defaultValue: "오늘 API 잔여"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - 섹션 헤더

    private func sectionHeader(title: String, iconName: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: iconName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text(verbatim: "\(count)")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())

            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - 경기 행

    private func matchRow(match: SportsModel) -> some View {
        NavigationLink(destination: SportsDetailView(match: match)) {
            SportsGameCard(match: match)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                matchToDelete = match
                showingDeleteMatchAlert = true
            } label: {
                Label(String(localized: "common.action.delete", defaultValue: "삭제"), systemImage: "trash")
            }
        }
        .alert(
            Text(String(localized: "sports.deleteMatch.title", defaultValue: "경기 기록 삭제")),
            isPresented: $showingDeleteMatchAlert
        ) {
            Button(String(localized: "common.action.cancel", defaultValue: "취소"), role: .cancel) {
                matchToDelete = nil
            }
            Button(String(localized: "common.action.delete", defaultValue: "삭제"), role: .destructive) {
                if let match = matchToDelete {
                    TicketImageStore.delete(paths: match.savedTicketPaths)
                    ArchivePhotoStore.delete(paths: match.photoPaths ?? [])
                    withAnimation {
                        modelContext.delete(match)
                    }
                    matchToDelete = nil
                }
            }
        } message: {
            if let match = matchToDelete {
                Text(String(format: String(localized: "record.deleteConfirm", defaultValue: "'%@' 기록을 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다."), locale: .autoupdatingCurrent, match.title))
            }
        }
    }
}
