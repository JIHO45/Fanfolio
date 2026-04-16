//
//  KBOTeamLogoAsset.swift
//  Fanfolio
//
//  KBO 팀 로고를 Assets.xcassets 이미지셋 이름과 연결합니다.
//  에셋 이름: DOOSAN, HANWHA, KIA, KIWOOM, KT, LG, LOTTE, NC, SAMSUNG, SSG
//
//  API-Sports 숫자 팀 ID 매핑은 버전마다 달라질 수 있어 여기서는 넣지 않습니다.
//  ID로 고정하려면 Firestore `teams.*.name`과 함께 로그로 확인한 뒤
//  아래에 `[Int: KBOTeamLogoAsset]`를 추가하면 됩니다.
//

import Foundation

/// Asset catalog `Image("…")`에 넣을 이름과 KBO 팀을 연결합니다.
enum KBOTeamLogoAsset: String, CaseIterable {
    case doosan = "DOOSAN"
    case hanwha = "HANWHA"
    case kia = "KIA"
    case kiwoom = "KIWOOM"
    case kt = "KT"
    case lg = "LG"
    case lotte = "LOTTE"
    case nc = "NC"
    case samsung = "SAMSUNG"
    case ssg = "SSG"

    var imageName: String { rawValue }

    /// 카드·순위 등 UI용 짧은 팀명 (한국어: 삼성·한화·LG 등, 영어: Samsung·Hanwha·LG).
    var shortDisplayNameKorean: String {
        switch self {
        case .doosan:  return "두산"
        case .hanwha:  return "한화"
        case .kia:     return "기아"
        case .kiwoom:  return "키움"
        case .kt:      return "KT"
        case .lg:      return "LG"
        case .lotte:   return "롯데"
        case .nc:      return "NC"
        case .samsung: return "삼성"
        case .ssg:     return "SSG"
        }
    }

    /// 영어 UI용 짧은 팀명.
    var shortDisplayNameEnglish: String {
        switch self {
        case .doosan:  return "Doosan"
        case .hanwha:  return "Hanwha"
        case .kia:     return "Kia"
        case .kiwoom:  return "Kiwoom"
        case .kt:      return "KT"
        case .lg:      return "LG"
        case .lotte:   return "Lotte"
        case .nc:      return "NC"
        case .samsung: return "Samsung"
        case .ssg:     return "SSG"
        }
    }

    /// 현재 앱 언어에 맞는 UI용 짧은 팀명.
    var shortDisplayNameLocalized: String {
        Locale.autoupdatingCurrent.language.languageCode?.identifier == "ko"
            ? shortDisplayNameKorean
            : shortDisplayNameEnglish
    }

    /// `leagueCode == "KBO"`일 때만 짧은 표기, 그 외에는 `name` 그대로.
    static func uiDisplayName(forTeamName name: String, leagueCode: String?) -> String {
        guard leagueCode == "KBO" else { return name }
        return uiDisplayName(forKBOCandidate: name)
    }

    /// KBO 팀으로 식별되면 로케일별 짧은 이름, 아니면 원문.
    static func uiDisplayName(forKBOCandidate name: String) -> String {
        guard let asset = asset(forTeamName: name) else { return name }
        return asset.shortDisplayNameLocalized
    }

    /// 홈 구장 한국어 이름. MKLocalSearch 지오코딩 검색어로 사용합니다.
    var homeStadiumKorean: String {
        switch self {
        case .doosan:  return "잠실 야구장"
        case .lg:      return "잠실 야구장"
        case .ssg:     return "인천 SSG 랜더스필드"
        case .kt:      return "수원 케이티위즈파크"
        case .kiwoom:  return "고척 스카이돔"
        case .samsung: return "대구 삼성 라이온즈파크"
        case .lotte:   return "사직 야구장"
        case .hanwha:  return "한화생명이글스파크"
        case .nc:      return "창원 NC 파크"
        case .kia:     return "광주 기아 챔피언스필드"
        }
    }

    /// 홈 구장 영어 이름.
    var homeStadiumEnglish: String {
        switch self {
        case .doosan:  return "Jamsil Baseball Stadium"
        case .lg:      return "Jamsil Baseball Stadium"
        case .ssg:     return "Incheon SSG Landers Field"
        case .kt:      return "Suwon KT Wiz Park"
        case .kiwoom:  return "Gocheok Sky Dome"
        case .samsung: return "Daegu Samsung Lions Park"
        case .lotte:   return "Sajik Baseball Stadium"
        case .hanwha:  return "Hanwha Life Eagles Park"
        case .nc:      return "Changwon NC Park"
        case .kia:     return "Gwangju Kia Champions Field"
        }
    }

    /// 현재 로케일에 맞는 구장 이름. 카드 표시용.
    var homeStadiumLocalized: String {
        Locale.autoupdatingCurrent.language.languageCode?.identifier == "ko"
            ? homeStadiumKorean
            : homeStadiumEnglish
    }

    /// Firestore `KBOTeamInfo` 등 API-Sports 영문 팀명이 올 때.
    static func imageName(forKBO team: KBOTeamInfo) -> String? {
        imageName(forTeamName: team.name)
    }

    /// 홈팀 이름으로 홈 구장 이름 조회 (현재 로케일).
    static func homeStadium(forTeamName name: String) -> String? {
        asset(forTeamName: name)?.homeStadiumLocalized
    }

    /// 영문·한글 혼용 팀명(폴더 이름, Firestore `teams.home.name`, 상대팀 표기 등).
    static func imageName(forTeamName name: String) -> String? {
        asset(forTeamName: name)?.imageName
    }

    private static func asset(forTeamName name: String) -> KBOTeamLogoAsset? {
        let folded = name.folding(options: .diacriticInsensitive, locale: .current)
        let norm = folded.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: "")

        for rule in Self.nameRules {
            if norm.contains(rule.normalizedNeedle) {
                return rule.asset
            }
        }
        return nil
    }

    // MARK: - 이름 매칭 (길이·구체성 큰 키워드 우선)

    private struct NameRule {
        let normalizedNeedle: String
        let asset: KBOTeamLogoAsset
    }

    // API-Sports KBO 팀명은 항상 영문으로 내려옵니다 (Firestore teams.*.name).
    // 한글 폴더명을 직접 입력하는 경우를 대비해 한글 키워드도 유지합니다.
    private static let nameRules: [NameRule] = {
        let pairs: [(String, KBOTeamLogoAsset)] = [
            // ── API-Sports 영문 이름 (실제 매칭 경로) ──
            ("kiwoomheroes", .kiwoom),
            ("doosanbears",  .doosan),
            ("lgtwins",      .lg),
            ("ssglanders",   .ssg),
            ("ktwiz",        .kt),
            ("samsunglions", .samsung),
            ("lottegiants",  .lotte),
            ("hanwhaeagles", .hanwha),
            ("ncdinos",      .nc),
            ("kiatigers",    .kia),
            // ── 한글 폴더명 수동 입력 대비 ──
            ("키움",   .kiwoom),
            ("두산",   .doosan),
            ("lg트윈", .lg),
            ("엘지",   .lg),
            ("ssg",    .ssg),
            ("kt위즈", .kt),
            ("케이티", .kt),
            ("삼성",   .samsung),
            ("롯데",   .lotte),
            ("한화",   .hanwha),
            ("nc다이", .nc),
            ("기아",   .kia),
        ]
        return pairs.map { NameRule(normalizedNeedle: $0.0, asset: $0.1) }
    }()
}
