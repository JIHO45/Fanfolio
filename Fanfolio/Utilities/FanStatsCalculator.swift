//
//  FanStatsCalculator.swift
//  Fanfolio
//
//  유닛 테스트를 작성하면서 깨닫는 첫 번째 원칙:
//  "로직이 View 안에 묻혀 있으면 테스트할 수 없다."
//
//  FanStatsView 안에 private var로 숨어 있던 통계 계산 로직을
//  이 파일로 분리했습니다. 이제 View 없이도 계산 결과를 검증할 수 있습니다.
//

import Foundation

// MARK: - MatchStatDTO (SwiftData 스레드 안전용)

/// 통계 계산에 필요한 최소 데이터만 담은 순수 값 타입.
/// 메인 스레드에서 folder.matches를 한 번만 매핑한 뒤 백그라운드로 전달할 때 사용.
struct MatchStatDTO {
    var matchStatus: MatchStatus
    var matchResult: MatchResult
    var date: Date?
    var isHomeGame: Bool
    var opponentTeam: String
    var myTeamScore: Int
    var opponentScore: Int

    /// 메인 스레드에서만 호출 (SwiftData @Model 접근).
    init(from match: SportsModel) {
        self.matchStatus = match.matchStatus
        self.matchResult = match.matchResult
        self.date = match.date
        self.isHomeGame = match.isHomeGame
        self.opponentTeam = match.opponentTeam
        self.myTeamScore = match.myTeamScore
        self.opponentScore = match.opponentScore
    }
}

// MARK: - FanStatsResult (비동기 계산 결과)

/// FanStatsCalculator.compute() 반환 타입. 뷰는 이 값만 바인딩.
struct FanStatsResult {
    var wins: Int
    var losses: Int
    var draws: Int
    var totalCompleted: Int
    var winRate: Double
    var luckyInfo: (emoji: String, title: String, subtitle: String)
    var maxWinStreak: Int
    var opponentRecords: [OpponentRecord]
    var fanArchetype: FanArchetype
    var fanRankPercentile: Int
    var seasonHighlight: SeasonHighlight?
    var monthlyData: [(month: Int, count: Int)]
    var homeWins: Int
    var homeLosses: Int
    var homeDraws: Int
    var awayWins: Int
    var awayLosses: Int
    var awayDraws: Int
    var milestoneUnlocks: [String: Bool]
    /// 현재 연승/연패 (최근 경기 기준, 2 이상일 때만).
    var currentStreak: (count: Int, type: MatchResult)?
}

// MARK: - FanStatsCalculator

/// 팬 통계 계산을 담당하는 순수(Pure) 계산기 타입.
///
/// **왜 구조체(struct)인가?**
/// 이 타입은 경기 배열을 입력받아 통계를 계산하는 것 외에
/// 아무것도 하지 않습니다. 외부 상태(화면, 네트워크)에
/// 의존하지 않으므로 `struct`로 설계하면 충분합니다.
///
/// **유닛 테스트에 적합한 이유:**
/// - 동일한 입력 → 항상 동일한 출력 (순수 함수 원칙)
/// - SwiftUI View 없이도 인스턴스를 생성할 수 있음
/// - 의존성이 `[SportsModel]` 하나뿐이라 테스트 데이터 주입이 쉬움
///
/// ```swift
/// // 테스트 코드 예시
/// let calc = FanStatsCalculator(matches: testMatches)
/// #expect(calc.winRate == 75.0)
/// ```
struct FanStatsCalculator {

    /// 계산 대상 (DTO만 사용 시 백그라운드 스레드 안전).
    private let data: [MatchStatDTO]

    /// 레거시/테스트용. 메인 스레드에서만 호출.
    init(matches: [SportsModel]) {
        self.data = matches.map { MatchStatDTO(from: $0) }
    }

    /// 백그라운드 전달용. 순수 값 타입만 사용.
    init(data: [MatchStatDTO]) {
        self.data = data
    }

    /// 완료(`.completed`) 상태인 경기만 필터링합니다.
    private var completed: [MatchStatDTO] {
        data.filter { $0.matchStatus == .completed }
    }

    // MARK: - 기본 집계

    var wins:           Int { completed.filter { $0.matchResult == .win  }.count }
    var losses:         Int { completed.filter { $0.matchResult == .loss }.count }
    var draws:          Int { completed.filter { $0.matchResult == .draw }.count }
    var totalCompleted: Int { completed.count }

    // MARK: - 승률

    /// 완료된 경기 중 승리 비율 (0 ~ 100%).
    /// 완료 경기가 없으면 0을 반환합니다 (0으로 나누기 방지).
    var winRate: Double {
        guard totalCompleted > 0 else { return 0 }
        return Double(wins) / Double(totalCompleted) * 100
    }

    // MARK: - 럭키팬 지수

    /// 승률 구간에 따른 럭키팬 등급 (이모지, 제목, 부제목).
    ///
    /// Swift의 범위 패턴(range pattern)을 switch에 사용해
    /// 구간 분류를 깔끔하게 표현합니다.
    var luckyInfo: (emoji: String, title: String, subtitle: String) {
        switch winRate {
        case 80...:   return ("🍀", String(localized: "sports.stats.lucky.legendary.title", defaultValue: "전설의 럭키팬"), String(localized: "sports.stats.lucky.legendary.subtitle", defaultValue: "내가 가면 무조건 이긴다!"))
        case 65..<80: return ("⭐️", String(localized: "sports.stats.lucky.fortunate.title", defaultValue: "행운의 팬"),   String(localized: "sports.stats.lucky.fortunate.subtitle", defaultValue: "내가 가면 우리 팀이 이긴다!"))
        case 50..<65: return ("👍", String(localized: "sports.stats.lucky.blessed.title", defaultValue: "복 받은 팬"),   String(localized: "sports.stats.lucky.blessed.subtitle", defaultValue: "꽤 괜찮은 직관 운이네요!"))
        case 40..<50: return ("😅", String(localized: "sports.stats.lucky.battling.title", defaultValue: "분투의 팬"),    String(localized: "sports.stats.lucky.battling.subtitle", defaultValue: "승리를 향해 달려가는 중!"))
        case 25..<40: return ("😢", String(localized: "sports.stats.lucky.trial.title", defaultValue: "시련의 팬"),    String(localized: "sports.stats.lucky.trial.subtitle", defaultValue: "비가 온 뒤에 무지개가 뜬다!"))
        default:      return ("💪", String(localized: "sports.stats.lucky.indomitable.title", defaultValue: "불굴의 팬"),    String(localized: "sports.stats.lucky.indomitable.subtitle", defaultValue: "진정한 팬은 져도 응원한다!"))
        }
    }

    // MARK: - 최대 연승

    /// 날짜 오름차순으로 정렬한 뒤 연속 승리의 최댓값을 계산합니다.
    ///
    /// **알고리즘 (O(n)):**
    /// 1. 날짜순 정렬
    /// 2. 승리면 `current` 증가 후 `maxStreak` 갱신
    /// 3. 패배·무승부면 `current`를 0으로 초기화 (연승 끊김)
    var maxWinStreak: Int {
        var maxStreak = 0
        var current   = 0
        let sorted = completed.sorted {
            ($0.date ?? .distantPast) < ($1.date ?? .distantPast)
        }
        for m in sorted {
            if m.matchResult == .win {
                current += 1
                maxStreak = max(maxStreak, current)
            } else {
                current = 0
            }
        }
        return maxStreak
    }

    // MARK: - 상대별 전적

    /// 상대팀별로 경기를 그룹화한 뒤 전적을 계산합니다.
    var opponentRecords: [OpponentRecord] {
        let grouped = Dictionary(grouping: completed, by: { $0.opponentTeam })
        return grouped.map { opponent, list in
            OpponentRecord(
                name:   opponent,
                wins:   list.filter { $0.matchResult == .win  }.count,
                losses: list.filter { $0.matchResult == .loss }.count,
                draws:  list.filter { $0.matchResult == .draw }.count
            )
        }
        .sorted { $0.total > $1.total }
    }

    /// 백그라운드에서 호출해 한 번에 결과를 반환. 뷰는 이 결과만 바인딩.
    func compute() -> FanStatsResult {
        let calendar = Calendar.current
        let monthly: [(month: Int, count: Int)] = (0..<12).reversed().compactMap { i -> (month: Int, count: Int)? in
            guard let date = calendar.date(byAdding: .month, value: -i, to: Date()) else { return nil }
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)
            let count = completed.filter { m in
                guard let d = m.date else { return false }
                return calendar.component(.month, from: d) == month && calendar.component(.year, from: d) == year
            }.count
            return (month, count)
        }
        let homeWins = completed.filter { $0.isHomeGame && $0.matchResult == .win }.count
        let homeLosses = completed.filter { $0.isHomeGame && $0.matchResult == .loss }.count
        let homeDraws = completed.filter { $0.isHomeGame && $0.matchResult == .draw }.count
        let awayWins = completed.filter { !$0.isHomeGame && $0.matchResult == .win }.count
        let awayLosses = completed.filter { !$0.isHomeGame && $0.matchResult == .loss }.count
        let awayDraws = completed.filter { !$0.isHomeGame && $0.matchResult == .draw }.count
        let hasAway = completed.contains { !$0.isHomeGame }
        let shutoutWin = completed.contains { $0.matchResult == .win && $0.opponentScore == 0 }
        let hasRival = opponentRecords.contains { $0.total >= 5 }
        let sortedByDate = completed.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let currentStreak: (count: Int, type: MatchResult)? = {
            guard let first = sortedByDate.first, first.matchResult != .draw else { return nil }
            let t = first.matchResult
            var count = 0
            for m in sortedByDate {
                if m.matchResult == t { count += 1 } else { break }
            }
            return count >= 2 ? (count, t) : nil
        }()
        let milestones: [String: Bool] = [
            "first": totalCompleted >= 1,
            "ten": totalCompleted >= 10,
            "twentyfive": totalCompleted >= 25,
            "fifty": totalCompleted >= 50,
            "hundred": totalCompleted >= 100,
            "away": hasAway,
            "streak3": maxWinStreak >= 3,
            "streak5": maxWinStreak >= 5,
            "shutout": shutoutWin,
            "rival": hasRival,
            "home10": homeWins >= 10,
            "road5": (awayWins + awayLosses + awayDraws) >= 5,
        ]
        return FanStatsResult(
            wins: wins,
            losses: losses,
            draws: draws,
            totalCompleted: totalCompleted,
            winRate: winRate,
            luckyInfo: luckyInfo,
            maxWinStreak: maxWinStreak,
            opponentRecords: opponentRecords,
            fanArchetype: fanArchetype,
            fanRankPercentile: fanRankPercentile,
            seasonHighlight: seasonHighlight,
            monthlyData: monthly,
            homeWins: homeWins,
            homeLosses: homeLosses,
            homeDraws: homeDraws,
            awayWins: awayWins,
            awayLosses: awayLosses,
            awayDraws: awayDraws,
            milestoneUnlocks: milestones,
            currentStreak: currentStreak
        )
    }
}

// MARK: - OpponentRecord

/// 특정 상대팀에 대한 누적 전적 모델.
///
/// 이전에는 `FanStatsView`의 `private struct`로 선언되어
/// 테스트에서 접근할 수 없었습니다.
/// 이 파일로 이동시켜 `internal` 수준으로 공개하면
/// 테스트 코드에서도 직접 생성·검증할 수 있습니다.
struct OpponentRecord: Identifiable {
    let id     = UUID()
    let name:   String
    let wins:   Int
    let losses: Int
    let draws:  Int

    /// 총 경기 수 (승 + 패 + 무).
    var total: Int { wins + losses + draws }

    /// 해당 상대에 대한 승률 (0 ~ 100%).
    /// 경기가 없으면 0을 반환합니다.
    var winRate: Double {
        guard total > 0 else { return 0 }
        return Double(wins) / Double(total) * 100
    }
}

// MARK: - 팬 유형 모델

/// 직관 패턴 분석을 통해 부여되는 팬 유형.
struct FanArchetype {
    let emoji:    String
    let title:    String
    let subtitle: String
}

// MARK: - 시즌 하이라이트 모델

/// 시즌 중 가장 인상적인 경기 1개를 요약한 모델.
struct SeasonHighlight {
    let emoji:    String
    let title:    String
    let subtitle: String
}

// MARK: - FanStatsCalculator 확장 (팬 유형 · 퍼센타일 · 하이라이트)

extension FanStatsCalculator {

    // MARK: 팬 유형

    /// 직관 패턴(총 경기 수, 원정 비율, 홈 승률, 승률)을 분석해 팬 유형을 반환합니다.
    /// 조건 우선순위: 열혈팬 > 원정전사 > 홈 수호신 > 행운의 팬 > 불굴의 팬 > 라이징팬
    var fanArchetype: FanArchetype {
        let awayCount   = completed.filter { !$0.isHomeGame }.count
        let homeCount   = completed.filter {  $0.isHomeGame }.count
        let awayRatio   = totalCompleted > 0 ? Double(awayCount) / Double(totalCompleted) : 0
        let homeRatio   = totalCompleted > 0 ? Double(homeCount) / Double(totalCompleted) : 0
        let homeWins    = completed.filter { $0.isHomeGame && $0.matchResult == .win }.count
        let homeWinRate = homeCount > 0 ? Double(homeWins) / Double(homeCount) : 0

        if totalCompleted >= 30 {
            return FanArchetype(emoji: "🔥", title: String(localized: "sports.stats.archetype.passionate.title", defaultValue: "열혈팬"),    subtitle: String(localized: "sports.stats.archetype.passionate.subtitle", defaultValue: "경기장이 곧 내 집"))
        } else if awayRatio >= 0.4 && awayCount >= 3 {
            return FanArchetype(emoji: "⚔️", title: String(localized: "sports.stats.archetype.roadWarrior.title", defaultValue: "원정전사"),  subtitle: String(localized: "sports.stats.archetype.roadWarrior.subtitle", defaultValue: "어디든 달려가는 진짜 팬"))
        } else if homeRatio >= 0.7 && homeWinRate >= 0.6 && homeCount >= 5 {
            return FanArchetype(emoji: "🏠", title: String(localized: "sports.stats.archetype.homeGuardian.title", defaultValue: "홈 수호신"), subtitle: String(localized: "sports.stats.archetype.homeGuardian.subtitle", defaultValue: "홈에서 반드시 이긴다"))
        } else if winRate >= 65 {
            return FanArchetype(emoji: "🍀", title: String(localized: "sports.stats.archetype.luckyFan.title", defaultValue: "행운의 팬"), subtitle: String(localized: "sports.stats.archetype.luckyFan.subtitle", defaultValue: "내가 가면 이긴다"))
        } else if winRate < 40 && totalCompleted >= 10 {
            return FanArchetype(emoji: "💪", title: String(localized: "sports.stats.archetype.neverGiveUp.title", defaultValue: "불굴의 팬"), subtitle: String(localized: "sports.stats.archetype.neverGiveUp.subtitle", defaultValue: "져도 포기하지 않는다"))
        } else {
            return FanArchetype(emoji: "🌱", title: String(localized: "sports.stats.archetype.rising.title", defaultValue: "라이징팬"),  subtitle: String(localized: "sports.stats.archetype.rising.subtitle", defaultValue: "성장 중인 직관 실력"))
        }
    }

    // MARK: 팬 랭킹 퍼센타일

    /// 서버 없이 로컬 점수만으로 산출하는 가상 퍼센타일 (1~99).
    ///
    /// **점수 구성 (합계 0~100점):**
    /// - 총 경기 수: 최대 40점 (50경기 기준 포화)
    /// - 승률:      최대 30점
    /// - 최다 연승: 최대 15점 (10연승 기준 포화)
    /// - 원정 경험: 최대 10점 (10경기 기준 포화)
    /// - 상대 다양성: 최대 5점 (5팀 기준 포화)
    ///
    /// 점수를 시그모이드 함수로 변환해 1~99% 범위로 정규화합니다.
    var fanRankPercentile: Int {
        guard totalCompleted > 0 else { return 1 }

        var score = 0.0
        score += min(Double(totalCompleted) / 50.0, 1.0) * 40
        score += (winRate / 100.0) * 30
        score += min(Double(maxWinStreak) / 10.0, 1.0) * 15

        let awayCount = completed.filter { !$0.isHomeGame }.count
        score += min(Double(awayCount) / 10.0, 1.0) * 10

        let uniqueOpponents = Set(completed.map { $0.opponentTeam }).count
        score += min(Double(uniqueOpponents) / 5.0, 1.0) * 5

        let normalized = (score - 50.0) / 15.0
        let sigmoid    = 1.0 / (1.0 + exp(-normalized))
        return max(1, min(99, Int(sigmoid * 98) + 1))
    }

    // MARK: 시즌 하이라이트

    /// 시즌에서 가장 인상적인 경기를 1개 선별합니다.
    ///
    /// **선별 우선순위:**
    /// 1. 점수 차 3점 이상의 압도적 승리
    /// 2. 완봉승 (상대 무득점)
    /// 3. 내 팀 최다 득점 경기
    var seasonHighlight: SeasonHighlight? {
        guard !completed.isEmpty else { return nil }

        let wins = completed.filter { $0.matchResult == .win }

        if let bigWin = wins.max(by: {
            ($0.myTeamScore - $0.opponentScore) < ($1.myTeamScore - $1.opponentScore)
        }), (bigWin.myTeamScore - bigWin.opponentScore) >= 3 {
            return SeasonHighlight(
                emoji:    "⚡️",
                title:    String(localized: "sports.stats.highlight.bestWin", defaultValue: "최고의 승리"),
                subtitle: "vs \(bigWin.opponentTeam) · \(bigWin.myTeamScore)-\(bigWin.opponentScore)"
            )
        }

        if let shutout = wins.first(where: { $0.opponentScore == 0 }) {
            return SeasonHighlight(
                emoji:    "🛡️",
                title:    String(localized: "sports.stats.highlight.shutout", defaultValue: "완봉승"),
                subtitle: "vs \(shutout.opponentTeam) · \(shutout.myTeamScore)-0"
            )
        }

        if let highScore = completed.max(by: { $0.myTeamScore < $1.myTeamScore }),
           highScore.myTeamScore > 0 {
            return SeasonHighlight(
                emoji:    "🎯",
                title:    String(localized: "sports.stats.highlight.mostGoals", defaultValue: "최다 득점"),
                subtitle: "vs \(highScore.opponentTeam) · \(highScore.myTeamScore)-\(highScore.opponentScore)"
            )
        }

        return nil
    }
}
