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

    /// 계산 대상 경기 기록 배열 (미완료 포함 전체).
    let matches: [SportsModel]

    // MARK: - 기본 집계

    /// 완료(`.completed`) 상태인 경기만 필터링합니다.
    /// 예정·진행 중 경기는 통계에 포함하지 않습니다.
    var completedMatches: [SportsModel] {
        matches.filter { $0.matchStatus == .completed }
    }

    var wins:           Int { completedMatches.filter { $0.matchResult == .win  }.count }
    var losses:         Int { completedMatches.filter { $0.matchResult == .loss }.count }
    var draws:          Int { completedMatches.filter { $0.matchResult == .draw }.count }
    var totalCompleted: Int { completedMatches.count }

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
        case 80...:   return ("🍀", "전설의 럭키팬", "내가 가면 무조건 이긴다!")
        case 65..<80: return ("⭐️", "행운의 팬",   "내가 가면 우리 팀이 이긴다!")
        case 50..<65: return ("👍", "복 받은 팬",   "꽤 괜찮은 직관 운이네요!")
        case 40..<50: return ("😅", "분투의 팬",    "승리를 향해 달려가는 중!")
        case 25..<40: return ("😢", "시련의 팬",    "비가 온 뒤에 무지개가 뜬다!")
        default:      return ("💪", "불굴의 팬",    "진정한 팬은 져도 응원한다!")
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
        let sorted = completedMatches.sorted {
            ($0.date ?? .distantPast) < ($1.date ?? .distantPast)
        }
        for match in sorted {
            if match.matchResult == .win {
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
    /// `Dictionary(grouping:by:)`로 O(n) 만에 그룹화하고,
    /// 총 경기 수 내림차순으로 정렬해 반환합니다.
    var opponentRecords: [OpponentRecord] {
        let grouped = Dictionary(grouping: completedMatches, by: { $0.opponentTeam })
        return grouped.map { opponent, matches in
            OpponentRecord(
                name:   opponent,
                wins:   matches.filter { $0.matchResult == .win  }.count,
                losses: matches.filter { $0.matchResult == .loss }.count,
                draws:  matches.filter { $0.matchResult == .draw }.count
            )
        }
        .sorted { $0.total > $1.total }
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
