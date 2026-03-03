//
//  SportsView.swift
//  Fanfolio
//
//  Created by 박지호 on 12/15/25.
//

import SwiftUI
import SwiftData

struct SportsView: View {
    let folder: SportsFanFolder
    
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddMatchSheet = false
    @State private var showingFolderEditSheet = false
    @State private var showingPastEventsSheet = false
    @State private var matchToDelete: SportsModel?
    @State private var showingDeleteMatchAlert = false
    
    // MARK: - 실시간 스코어 상태
    @State private var liveFixtures: [LiveFixture] = []
    @State private var liveLoadError: String? = nil
    @State private var isLoadingLive = false
    
    // MARK: - F1 레이스 상태
    @State private var showingAddRaceSheet = false
    @State private var raceToDelete: F1RaceModel?
    @State private var showingDeleteRaceAlert = false

    // MARK: - 골프 라운드 상태
    @State private var showingAddRoundSheet = false
    @State private var roundToDelete: GolfRoundModel?
    @State private var showingDeleteRoundAlert = false

    // MARK: - 즐겨찾기 상태 (배너 뱃지용)
    @State private var favorites = FavoritePlayersManager.shared
    
    /// 예정 + 진행중 경기 (가까운 날짜가 위에)
    private var activeMatches: [SportsModel] {
        folder.matches
            .filter { $0.matchStatus != .completed }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    
    /// 완료된 경기 (최근 경기가 위에)
    private var completedMatches: [SportsModel] {
        folder.matches
            .filter { $0.matchStatus == .completed }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    
    // MARK: - 골프 라운드 목록
    private var activeRounds: [GolfRoundModel] {
        folder.golfRounds
            .filter { $0.roundStatus != .completed }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    private var completedRounds: [GolfRoundModel] {
        folder.golfRounds
            .filter { $0.roundStatus == .completed }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    private var golfBestScore: Int? {
        completedRounds.compactMap { $0.totalScore }.min()
    }
    private var golfAverageScore: Double? {
        let scores = completedRounds.compactMap { $0.totalScore }
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }
    private var golfUnderParCount: Int {
        completedRounds.filter { $0.isUnderPar }.count
    }

    // MARK: - F1 레이스 목록
    private var activeRaces: [F1RaceModel] {
        folder.f1Races
            .filter { $0.raceStatus != .completed }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    private var completedRaces: [F1RaceModel] {
        folder.f1Races
            .filter { $0.raceStatus == .completed }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    private var f1PodiumCount: Int {
        completedRaces.filter { F1Data.isPodium($0.myFinishPosition) }.count
    }
    private var f1AveragePosition: Double? {
        let valid = completedRaces.compactMap { $0.myFinishPosition }.filter { $0 > 0 }
        guard !valid.isEmpty else { return nil }
        return Double(valid.reduce(0, +)) / Double(valid.count)
    }

    // MARK: - 통계 계산
    private var wins: Int { completedMatches.filter { $0.matchResult == .win }.count }
    private var losses: Int { completedMatches.filter { $0.matchResult == .loss }.count }
    private var draws: Int { completedMatches.filter { $0.matchResult == .draw }.count }
    private var totalCompleted: Int { completedMatches.count }
    
    private var winRate: Double {
        guard totalCompleted > 0 else { return 0 }
        return Double(wins) / Double(totalCompleted) * 100
    }
    
    /// 현재 연승/연패 계산 (최근 경기부터)
    private var currentStreak: (count: Int, type: MatchResult)? {
        let sorted = completedMatches.sorted {
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
        guard let first = sorted.first,
              first.matchResult != .draw else { return nil }
        
        let streakType = first.matchResult
        var count = 0
        for match in sorted {
            if match.matchResult == streakType {
                count += 1
            } else {
                break
            }
        }
        return count >= 2 ? (count, streakType) : nil
    }
    
    var body: some View {
        Group {
            if folder.sportType == .racing {
                f1ContentView
            } else if folder.sportType == .golf {
                golfContentView
            } else if folder.matches.isEmpty && liveFixtures.isEmpty {
                ContentUnavailableView(
                    "경기 기록이 없습니다",
                    systemImage: folder.sportType.iconName,
                    description: Text("+ 버튼을 눌러 첫 경기를 기록해보세요!")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // 팀 정보 배너 (탭하면 팀 스탯 + 선수단 상세)
                        NavigationLink(destination: TeamInfoDetailView(folder: folder)) {
                            teamInfoBanner
                        }
                        .buttonStyle(.plain)

                        // 전적 통계 배너 (탭하면 상세 통계)
                        if totalCompleted > 0 {
                            NavigationLink(destination: FanStatsView(folder: folder)) {
                                statsHeader
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // 실시간 스코어보드 섹션
                        if !liveFixtures.isEmpty || isLoadingLive {
                            liveScoreboardSection
                        }
                        
                        // API 키 미설정 안내
                        if APIConfig.apiSportsKey.isEmpty && liveFixtures.isEmpty && !isLoadingLive {
                            liveScoreAPIKeyPrompt
                        }
                        
                        // 에러 배너
                        if let error = liveLoadError {
                            errorBanner(message: error)
                        }
                        
                        // 예정/진행중 경기 (상단 고정)
                        if !activeMatches.isEmpty {
                            sectionHeader(
                                title: "예정 · 진행 중",
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
                                title: "완료",
                                iconName: "checkmark.circle",
                                count: completedMatches.count
                            )
                            
                            ForEach(completedMatches) { match in
                                matchRow(match: match)
                            }
                        }
                        
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await fetchLiveScores()
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingFolderEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }

                if folder.sportType == .racing {
                    Button {
                        showingAddRaceSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                } else if folder.sportType == .golf {
                    Button {
                        showingAddRoundSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                } else {
                    Menu {
                        Button {
                            showingAddMatchSheet = true
                        } label: {
                            Label("직접 입력", systemImage: "square.and.pencil")
                        }

                        Button {
                            showingPastEventsSheet = true
                        } label: {
                            Label("지난 경기 불러오기", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddRaceSheet) {
            AddF1RaceView(
                folder: folder,
                nextOrderIndex: folder.f1Races.count
            )
        }
        .sheet(isPresented: $showingAddRoundSheet) {
            AddGolfRoundView(
                folder: folder,
                nextOrderIndex: folder.golfRounds.count
            )
        }
        .sheet(isPresented: $showingAddMatchSheet) {
            AddSportsMatchView(
                folder: folder,
                nextOrderIndex: folder.matches.count
            )
        }
        .sheet(isPresented: $showingFolderEditSheet) {
            AddFolderView(folder: folder)
        }
        .sheet(isPresented: $showingPastEventsSheet) {
            PastEventsListView(folder: folder)
        }
    }
    
    // MARK: - 실시간 스코어 로드 (refreshable에서만 호출)

    private func fetchLiveScores() async {
        guard !APIConfig.apiSportsKey.isEmpty else { return }
        guard NetworkMonitor.shared.isConnected else {
            liveLoadError = "인터넷 연결이 없습니다. 연결 후 다시 시도해주세요."
            return
        }
        isLoadingLive = true
        liveLoadError = nil
        
        defer { isLoadingLive = false }
        
        do {
            let sport = folder.sportType
            let leagueCode = folder.leagueCode ?? ""
            let leagueID = sport.apiSportsLeagueIDs[leagueCode] ?? 0
            
            // 팀 이름으로 API-Sports 팀 ID를 추정 (간단 매핑)
            // 실제 운영 시: espn_teams_master.json에 api_sports_id 필드 추가 권장
            let teamID = folder.name.hashValue % 1000 + 1  // 임시 플레이스홀더
            
            switch sport {
            case .americanFootball:
                liveFixtures = try await APISportsService.shared.fetchNFLLiveOrTodayGames(teamID: teamID)
            case .soccer:
                liveFixtures = try await APISportsService.shared.fetchSoccerGames(leagueID: leagueID, teamID: teamID)
            default:
                liveFixtures = []
            }
        } catch let error as APISportsError {
            liveLoadError = error.errorDescription
            liveFixtures = []
        } catch {
            liveLoadError = "데이터를 불러오는 중 오류가 발생했습니다."
            liveFixtures = []
        }
    }
    
    // MARK: - 실시간 스코어보드 UI 섹션
    
    private var liveScoreboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isLoadingLive {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("실시간 스코어 로딩 중...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LiveIndicator()
                    Text("실시간 스코어")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    Text("· 아래로 당겨서 새로고침")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            
            if !liveFixtures.isEmpty {
                LiveScoreboardSection(fixtures: liveFixtures, sportType: folder.sportType)
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
                Text("실시간 스코어 미설정")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text("Info.plist에 API_SPORTS_KEY를 추가하면 실시간 스코어를 볼 수 있습니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            // API 사용량 표시 (키 설정 시)
            let limiter = APIRateLimiter.shared
            if limiter.callCount > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(limiter.remainingCalls)회 남음")
                        .font(.caption2.bold())
                        .foregroundStyle(limiter.remainingCalls < 20 ? .orange : .secondary)
                    Text("오늘 API 잔여")
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
    
    // MARK: - 럭키팬 칭호
    private var luckyTitle: (emoji: String, title: String) {
        switch winRate {
        case 80...: return ("🍀", "전설의 럭키팬")
        case 65..<80: return ("⭐️", "행운의 팬")
        case 50..<65: return ("👍", "복 받은 팬")
        case 40..<50: return ("😅", "분투의 팬")
        case 25..<40: return ("😢", "시련의 팬")
        default: return ("💪", "불굴의 팬")
        }
    }
    
    // MARK: - 전적 통계 배너
    private var statsHeader: some View {
        VStack(spacing: 14) {
            // 상단: 팀 로고(선택) + 럭키 칭호 + 자세히 보기
            HStack {
                HStack(spacing: 10) {
                    // 우리 팀 로고 (폴더에 팀 선택 시)
                    HStack(spacing: 6) {
                        Text(luckyTitle.emoji)
                        Text(luckyTitle.title)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("자세히 보기")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            // 승률 + 경기 수
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(winRate))%")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(winRate >= 50 ? .green : (winRate > 0 ? .orange : .secondary))
                
                Text("승률")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(totalCompleted)경기")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            
            // 승/패/무 비율 바
            GeometryReader { geometry in
                let total = CGFloat(max(totalCompleted, 1))
                let winWidth = geometry.size.width * CGFloat(wins) / total
                let lossWidth = geometry.size.width * CGFloat(losses) / total
                
                HStack(spacing: 2) {
                    if wins > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(MatchResult.win.color)
                            .frame(width: max(winWidth, 8))
                    }
                    if losses > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(MatchResult.loss.color)
                            .frame(width: max(lossWidth, 8))
                    }
                    if draws > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(MatchResult.draw.color)
                    }
                }
            }
            .frame(height: 8)
            
            // 하단: 승/패/무 수 + 연승/연패
            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    statLabel(count: wins, text: "승", color: .green)
                    statLabel(count: losses, text: "패", color: .red)
                    statLabel(count: draws, text: "무", color: .orange)
                }
                
                Spacer()
                
                if let streak = currentStreak {
                    HStack(spacing: 4) {
                        Text(streak.type == .win ? "🔥" : "💧")
                        Text("\(streak.count)\(streak.type == .win ? "연승" : "연패")")
                            .font(.caption.bold())
                            .foregroundStyle(streak.type.color)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(streak.type.color.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
    
    private func statLabel(count: Int, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count)\(text)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - 팀 정보 배너 카드 (탭하면 TeamInfoDetailView로 이동)

    private var teamInfoBanner: some View {
        let favCount = favorites.favoriteIDs.count
        let gradients = folder.gradientColors

        return HStack(spacing: 14) {
            // 팀 로고
            if let url = folder.teamLogoUrl, !url.isEmpty {
                ZStack {
                    LinearGradient(colors: gradients, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit().padding(6)
                        case .failure:
                            Image(systemName: "person.3.fill")
                                .font(.caption2).foregroundStyle(.white.opacity(0.8))
                        case .empty:
                            ProgressView().tint(.white)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                .frame(width: 44, height: 44)
            } else {
                ZStack {
                    LinearGradient(colors: gradients, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Image(systemName: "person.3.fill")
                        .font(.subheadline).foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
            }

            // 텍스트
            VStack(alignment: .leading, spacing: 4) {
                Text("팀 정보")
                    .font(.subheadline.bold())
                HStack(spacing: 8) {
                    Label("팀 선수단", systemImage: "person.3.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if favCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.red)
                            Text("최애 \(favCount)명")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Text("자세히 보기")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: - 섹션 헤더
    private func sectionHeader(title: String, iconName: String, count: Int, hideCount: Bool = false) -> some View {
        HStack {
            Label(title, systemImage: iconName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            if !hideCount {
                Text("\(count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            
            Spacer()
        }
        .padding(.top, 8)
    }
    
    // MARK: - F1 전용 콘텐츠 뷰

    private var f1ContentView: some View {
        Group {
            if folder.f1Races.isEmpty {
                ContentUnavailableView(
                    "레이스 기록이 없습니다",
                    systemImage: "flag.checkered",
                    description: Text("+ 버튼을 눌러 첫 그랑프리 직관을 기록해보세요!")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // 팀 정보 배너
                        NavigationLink(destination: TeamInfoDetailView(folder: folder)) {
                            teamInfoBanner
                        }
                        .buttonStyle(.plain)

                        // F1 통계 배너
                        if !completedRaces.isEmpty {
                            f1StatsHeader
                        }

                        // 예정 레이스
                        if !activeRaces.isEmpty {
                            sectionHeader(title: "예정", iconName: "clock", count: activeRaces.count)
                            ForEach(activeRaces) { race in
                                f1RaceRow(race: race)
                            }
                        }

                        // 완료된 레이스
                        if !completedRaces.isEmpty {
                            sectionHeader(title: "완료", iconName: "checkmark.circle", count: completedRaces.count)
                            ForEach(completedRaces) { race in
                                f1RaceRow(race: race)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var f1StatsHeader: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered.2.crossed")
                        .foregroundStyle(Color.from(hex: folder.teamColor) ?? .red)
                    Text("시즌 기록")
                        .font(.caption.bold())
                }
                Spacer()
            }

            HStack(spacing: 0) {
                f1StatCell(value: "\(completedRaces.count)", label: "총 레이스")
                Divider().frame(height: 36)
                f1StatCell(
                    value: "\(f1PodiumCount)",
                    label: "포디움",
                    accent: f1PodiumCount > 0 ? Color(red: 1.0, green: 0.84, blue: 0.0) : nil
                )
                Divider().frame(height: 36)
                if let avg = f1AveragePosition {
                    f1StatCell(value: String(format: "%.1f위", avg), label: "평균 순위")
                } else {
                    f1StatCell(value: "-", label: "평균 순위")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func f1StatCell(value: String, label: String, accent: Color? = nil) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(accent ?? .primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func f1RaceRow(race: F1RaceModel) -> some View {
        NavigationLink(destination: F1RaceDetailView(race: race)) {
            F1RaceCard(race: race, folderColor: Color.from(hex: race.folder?.teamColor) ?? .red)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                raceToDelete = race
                showingDeleteRaceAlert = true
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .alert("레이스 기록 삭제", isPresented: $showingDeleteRaceAlert) {
            Button("취소", role: .cancel) { raceToDelete = nil }
            Button("삭제", role: .destructive) {
                if let race = raceToDelete {
                    withAnimation { modelContext.delete(race) }
                    raceToDelete = nil
                }
            }
        } message: {
            if let race = raceToDelete {
                Text("'\(race.title)' 기록을 삭제하시겠습니까?")
            }
        }
    }

    // MARK: - 골프 전용 콘텐츠 뷰

    private var golfContentView: some View {
        Group {
            if folder.golfRounds.isEmpty {
                ContentUnavailableView(
                    "라운드 기록이 없습니다",
                    systemImage: "figure.golf",
                    description: Text("+ 버튼을 눌러 첫 라운드를 기록해보세요!")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // 팀 정보 배너
                        NavigationLink(destination: TeamInfoDetailView(folder: folder)) {
                            teamInfoBanner
                        }
                        .buttonStyle(.plain)

                        // 골프 통계 배너
                        if !completedRounds.isEmpty {
                            golfStatsHeader
                        }

                        // 예정 라운드
                        if !activeRounds.isEmpty {
                            sectionHeader(title: "예정", iconName: "clock", count: activeRounds.count)
                            ForEach(activeRounds) { round in
                                golfRoundRow(round: round)
                            }
                        }

                        // 완료된 라운드
                        if !completedRounds.isEmpty {
                            sectionHeader(title: "완료", iconName: "checkmark.circle", count: completedRounds.count)
                            ForEach(completedRounds) { round in
                                golfRoundRow(round: round)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var golfStatsHeader: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "figure.golf")
                        .foregroundStyle(Color.from(hex: folder.teamColor) ?? .green)
                    Text("시즌 기록")
                        .font(.caption.bold())
                }
                Spacer()
            }

            HStack(spacing: 0) {
                golfStatCell(value: "\(completedRounds.count)", label: "총 라운드")
                Divider().frame(height: 36)
                if let best = golfBestScore {
                    golfStatCell(
                        value: "\(best)타",
                        label: "베스트",
                        accent: Color.from(hex: folder.teamColor) ?? .green
                    )
                } else {
                    golfStatCell(value: "-", label: "베스트")
                }
                Divider().frame(height: 36)
                if let avg = golfAverageScore {
                    golfStatCell(value: String(format: "%.1f", avg), label: "평균 타수")
                } else {
                    golfStatCell(value: "-", label: "평균 타수")
                }
                Divider().frame(height: 36)
                golfStatCell(
                    value: "\(golfUnderParCount)",
                    label: "언더파",
                    accent: golfUnderParCount > 0 ? .green : nil
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func golfStatCell(value: String, label: String, accent: Color? = nil) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(accent ?? .primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func golfRoundRow(round: GolfRoundModel) -> some View {
        NavigationLink(destination: GolfRoundDetailView(round: round)) {
            GolfRoundCard(round: round, folderColor: Color.from(hex: round.folder?.teamColor) ?? .green)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                roundToDelete = round
                showingDeleteRoundAlert = true
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .alert("라운드 기록 삭제", isPresented: $showingDeleteRoundAlert) {
            Button("취소", role: .cancel) { roundToDelete = nil }
            Button("삭제", role: .destructive) {
                if let round = roundToDelete {
                    withAnimation { modelContext.delete(round) }
                    roundToDelete = nil
                }
            }
        } message: {
            if let round = roundToDelete {
                Text("'\(round.title)' 기록을 삭제하시겠습니까?")
            }
        }
    }

    // MARK: - 경기 행 (네비게이션 + 삭제)
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
                Label("삭제", systemImage: "trash")
            }
        }
        .alert("경기 기록 삭제", isPresented: $showingDeleteMatchAlert) {
            Button("취소", role: .cancel) {
                matchToDelete = nil
            }
            Button("삭제", role: .destructive) {
                if let match = matchToDelete {
                    withAnimation {
                        modelContext.delete(match)
                    }
                    matchToDelete = nil
                }
            }
        } message: {
            if let match = matchToDelete {
                Text("'\(match.title)' 기록을 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.")
            }
        }
    }
}

// MARK: - 팀 로고 + 이름 셀
private struct TeamLogoLabel: View {
    let name: String
    let logoUrl: String?
    let gradientColors: [Color]
    
    var body: some View {
        VStack(spacing: 6) {
            if let url = logoUrl, !url.isEmpty {
                ZStack {
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit().padding(8)
                        case .failure:
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        case .empty:
                            ProgressView().tint(.white)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                .frame(width: 36, height: 36)
            }
            Text(name)
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 경기 카드
private struct SportsGameCard: View {
    let match: SportsModel
    
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "M월 d일 (E)"
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt
    }()
    
    private var sportType: SportType {
        match.folder?.sportType ?? .other
    }
    
    private var team1Name: String { match.team1Display }
    private var team2Name: String { match.team2Display }
    
    private var team1Gradient: [Color] {
        match.folder?.gradientColors ?? [.gray, .gray.opacity(0.7)]
    }
    
    private var team1Data: ESPNTeam? {
        ESPNTeamsLoader.team(name: match.team1Display, leagueCode: match.folder?.leagueCode)
    }
    private var team2Data: ESPNTeam? {
        ESPNTeamsLoader.team(name: match.opponentTeam, leagueCode: match.folder?.leagueCode)
    }
    
    private var isActive: Bool {
        match.matchStatus != .completed
    }
    
    /// D-day 계산 (경기 예정일 때)
    private var dDayText: String? {
        guard match.matchStatus == .upcoming,
              let date = match.date else { return nil }
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        if days > 0 { return "D-\(days)" }
        if days == 0 { return "D-Day" }
        return nil
    }
    
    var body: some View {
        if isActive {
            activeCard
        } else {
            completedCard
        }
    }
    
    // MARK: - 예정/진행중 카드
    private var activeCard: some View {
        VStack(spacing: 0) {
            // 진행중: 상단 LIVE 바
            if match.matchStatus == .live {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .symbolEffect(.pulse)
                    Text("LIVE")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(MatchStatus.live.color)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 16, topTrailingRadius: 16
                ))
            }
            
            VStack(spacing: 12) {
                // 상단: D-day / 종목 + 상태 배지
                HStack {
                    if let dDay = dDayText {
                        Text(dDay)
                            .font(.caption.bold())
                            .foregroundStyle(match.matchStatus.color)
                    }
                    
                    Label(sportType.rawValue, systemImage: sportType.iconName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if match.matchStatus == .upcoming {
                        Text(match.matchStatus.rawValue)
                            .font(.caption.bold())
                            .foregroundStyle(match.matchStatus.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(match.matchStatus.color.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                
                // 팀 VS 팀 (로고 + 이름)
                HStack {
                    TeamLogoLabel(
                        name: team1Name,
                        logoUrl: match.hasFavoriteTeam ? match.folder?.teamLogoUrl : team1Data?.logo_url,
                        gradientColors: match.hasFavoriteTeam ? team1Gradient : (team1Data?.gradientColors ?? [.gray, .gray.opacity(0.7)])
                    )
                    
                    Text("VS")
                        .font(.title3.bold())
                        .foregroundStyle(match.matchStatus.color.opacity(0.6))
                    
                    TeamLogoLabel(
                        name: team2Name,
                        logoUrl: team2Data?.logo_url,
                        gradientColors: team2Data?.gradientColors ?? [.gray, .gray.opacity(0.7)]
                    )
                }
                
                // 날짜 + 장소
                HStack {
                    if let date = match.date {
                        Label(Self.dateFormatter.string(from: date), systemImage: "calendar")
                    }
                    Spacer()
                    if let location = match.location {
                        Label(location, systemImage: "mappin")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            match.matchStatus.color.opacity(0.08),
                            Color(uiColor: .secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    match.matchStatus.color.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 5])
                )
        )
    }
    
    // MARK: - 완료 카드
    private var completedCard: some View {
        VStack(spacing: 0) {
            // 상단: 종목 + 결과 배지
            HStack {
                Label(sportType.rawValue, systemImage: sportType.iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(match.matchResult.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(match.matchResult.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(match.matchResult.color.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.bottom, 14)
            
            // 중앙: 내 팀 — 점수 — 상대 팀 (로고 + 이름)
            HStack {
                VStack(spacing: 4) {
                    if let url = match.hasFavoriteTeam ? match.folder?.teamLogoUrl : team1Data?.logo_url, !url.isEmpty {
                        ZStack {
                            LinearGradient(
                                colors: match.hasFavoriteTeam ? team1Gradient : (team1Data?.gradientColors ?? [.gray, .gray.opacity(0.7)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            AsyncImage(url: URL(string: url)) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFit().padding(6)
                                default:
                                    EmptyView()
                                }
                            }
                        }
                        .frame(width: 32, height: 32)
                    }
                    Text(team1Name)
                        .font(.subheadline.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(match.isHomeGame ? "홈" : "원정")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                HStack(spacing: 8) {
                    Text("\(match.myTeamScore)")
                        .font(.title.bold())
                        .foregroundStyle(
                            match.matchResult == .win ? match.matchResult.color : .primary
                        )
                    Text(":")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("\(match.opponentScore)")
                        .font(.title.bold())
                        .foregroundStyle(
                            match.matchResult == .loss ? match.matchResult.color : .primary
                        )
                }
                
                VStack(spacing: 4) {
                    if let opp = team2Data {
                        ZStack {
                            LinearGradient(
                                colors: opp.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            AsyncImage(url: URL(string: opp.logo_url)) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFit().padding(6)
                                default:
                                    EmptyView()
                                }
                            }
                        }
                        .frame(width: 32, height: 32)
                    }
                    Text(team2Name)
                        .font(.subheadline.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(match.isHomeGame ? "원정" : "홈")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 14)
            
            // 하단: 날짜 + 장소
            Divider()
                .padding(.bottom, 10)
            
            HStack {
                if let date = match.date {
                    Label(Self.dateFormatter.string(from: date), systemImage: "calendar")
                }
                Spacer()
                if let location = match.location {
                    Label(location, systemImage: "mappin")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                bottomLeadingRadius: 16
            )
            .fill(match.matchResult.color)
            .frame(width: 4)
        }
    }
}

// MARK: - F1 레이스 카드

private struct F1RaceCard: View {
    let race: F1RaceModel
    let folderColor: Color

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "M월 d일 (E)"
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt
    }()

    var body: some View {
        HStack(spacing: 14) {
            // 왼쪽: 순위 뱃지 or 상태 아이콘
            positionBadge

            // 가운데: 레이스 정보
            VStack(alignment: .leading, spacing: 5) {
                Text(race.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)

                if let circuit = race.circuitName, !circuit.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(circuit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let driver = race.myDriverName, !driver.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(folderColor)
                        Text(driver)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(folderColor)
                    }
                }
            }

            Spacer()

            // 오른쪽: 날짜 + 화살표
            VStack(alignment: .trailing, spacing: 4) {
                if let date = race.date {
                    Text(Self.dateFormatter.string(from: date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if race.raceStatus != .completed {
                    Text(race.raceStatus.rawValue)
                        .font(.caption2.bold())
                        .foregroundStyle(race.raceStatus.color)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(race.raceStatus.color.opacity(0.12))
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                .fill(positionAccentColor)
                .frame(width: 4)
        }
    }

    private var positionAccentColor: Color {
        guard race.raceStatus == .completed else { return folderColor.opacity(0.5) }
        return race.positionBadgeColor
    }

    @ViewBuilder
    private var positionBadge: some View {
        ZStack {
            Circle()
                .fill(positionAccentColor.opacity(0.15))
                .frame(width: 46, height: 46)

            if race.raceStatus == .completed {
                if race.isDNF {
                    VStack(spacing: 1) {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                        Text("DNF")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.red)
                    }
                } else if let pos = race.myFinishPosition {
                    VStack(spacing: 1) {
                        Text("\(pos)")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(positionAccentColor)
                        Text("위")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(positionAccentColor)
                    }
                } else {
                    Image(systemName: "flag.checkered")
                        .font(.subheadline)
                        .foregroundStyle(folderColor)
                }
            } else {
                Image(systemName: race.raceStatus.iconName)
                    .font(.subheadline)
                    .foregroundStyle(race.raceStatus.color)
            }
        }
    }
}

// MARK: - 골프 라운드 카드

private struct GolfRoundCard: View {
    let round: GolfRoundModel
    let folderColor: Color

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "M월 d일 (E)"
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt
    }()

    var body: some View {
        HStack(spacing: 14) {
            // 왼쪽: 스코어 배지 or 상태 아이콘
            scoreBadge

            // 가운데: 라운드 정보
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(round.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if round.isTournament {
                        Image(systemName: "trophy.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }

                if let course = round.courseName, !course.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(course)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "figure.golf")
                        .font(.caption2)
                        .foregroundStyle(folderColor)
                    Text(round.holesText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(folderColor)
                }
            }

            Spacer()

            // 오른쪽: 날짜 + 화살표
            VStack(alignment: .trailing, spacing: 4) {
                if let date = round.date {
                    Text(Self.dateFormatter.string(from: date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if round.roundStatus != .completed {
                    Text(round.roundStatus.rawValue)
                        .font(.caption2.bold())
                        .foregroundStyle(round.roundStatus.color)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(round.roundStatus.color.opacity(0.12))
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                .fill(accentColor)
                .frame(width: 4)
        }
    }

    private var accentColor: Color {
        guard round.roundStatus == .completed else { return folderColor.opacity(0.5) }
        if round.isUnderPar { return .green }
        if round.isEvenPar { return .blue }
        return .orange
    }

    @ViewBuilder
    private var scoreBadge: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.15))
                .frame(width: 46, height: 46)

            if round.roundStatus == .completed {
                if round.totalScore != nil {
                    VStack(spacing: 1) {
                        Text(round.scoreToParText)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(round.scoreColor)
                        Text("par")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(round.scoreColor)
                    }
                } else {
                    Image(systemName: "figure.golf")
                        .font(.subheadline)
                        .foregroundStyle(folderColor)
                }
            } else {
                Image(systemName: round.roundStatus.iconName)
                    .font(.subheadline)
                    .foregroundStyle(round.roundStatus.color)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SportsView(folder: {
            let folder = SportsFanFolder(name: "LG 트윈스", sportType: .baseball)
            
            let live = SportsModel(
                title: "LG vs KT",
                opponentTeam: "KT 위즈",
                matchStatus: .live,
                date: Date(),
                location: "잠실 야구장",
                orderIndex: 0
            )
            live.folder = folder
            
            let upcoming = SportsModel(
                title: "LG vs SSG",
                opponentTeam: "SSG 랜더스",
                matchStatus: .upcoming,
                date: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
                location: "잠실 야구장",
                orderIndex: 1
            )
            upcoming.folder = folder
            
            // 완료된 경기들 — 통계 확인용
            let matches: [(String, Int, Int, MatchResult, Int)] = [
                ("두산 베어스", 5, 2, .win, 2),
                ("SSG 랜더스", 3, 1, .win, 3),
                ("한화 이글스", 7, 4, .win, 4),
                ("NC 다이노스", 2, 5, .loss, 5),
                ("키움 히어로즈", 4, 4, .draw, 6),
                ("KT 위즈", 6, 3, .win, 7),
                ("삼성 라이온즈", 1, 3, .loss, 8),
                ("KIA 타이거즈", 8, 2, .win, 9),
                ("롯데 자이언츠", 3, 6, .loss, 10),
                ("두산 베어스", 4, 1, .win, 11),
            ]
            
            for (opponent, my, opp, result, idx) in matches {
                let m = SportsModel(
                    title: "LG vs \(opponent)",
                    opponentTeam: opponent,
                    myTeamScore: my,
                    opponentScore: opp,
                    matchResult: result,
                    matchStatus: .completed,
                    date: Calendar.current.date(byAdding: .day, value: -idx, to: Date()),
                    location: "잠실 야구장",
                    orderIndex: idx
                )
                m.folder = folder
                folder.matches.append(m)
            }
            
            folder.matches.append(contentsOf: [live, upcoming])
            return folder
        }())
    }
    .modelContainer(SportsPreviewSampleData.container)
}
