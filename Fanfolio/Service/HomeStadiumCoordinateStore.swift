//
//  HomeStadiumCoordinateStore.swift
//  Fanfolio
//
//  팀명 → 홈구장 정확 좌표 정적 사전.
//  geocoding API 오차를 원천 차단합니다 (중립 구장·원정 이벤트는 geocoding 폴백).
//
//  커버 범위:
//  ⚾ Baseball  : MLB 30팀 · KBO 10팀
//  🏀 Basketball: NBA 30팀
//  🏈 AmFootball: NFL 32팀
//  ⚽ Soccer    : EPL · La Liga · Bundesliga · Serie A · Ligue 1 · MLS
//                Eredivisie · Primeira Liga · Süper Lig · Belgian Pro League
//                Super League Greece · Czech First League · Danish Superliga
//                + 컵 대회(FA Cup, Copa del Rey, DFB-Pokal 등)
//

import CoreLocation

enum HomeStadiumCoordinateStore {

    // MARK: - 공개 진입점

    /// 경기의 홈팀 이름으로 정적 좌표를 반환합니다.
    /// - 홈 경기: user 팀(`match.team1Display`)이 홈
    /// - 원정 경기: 상대팀(`match.opponentTeam`)이 홈
    /// - 커버되지 않는 구장(중립 경기 등)은 `nil` → geocoding 폴백
    static func coordinate(for match: SportsModel, folder: SportsFanFolder) -> CLLocationCoordinate2D? {
        let homeTeamName = match.isHomeGame ? match.team1Display : match.opponentTeam
        let norm = normalized(homeTeamName)

        switch folder.sportType {
        case .americanFootball:
            return nflLookup(norm)
        case .basketball:
            return nbaLookup(norm)
        case .baseball:
            return baseballLookup(norm, leagueCode: folder.leagueCode)
        case .soccer:
            return soccerLookup(norm, leagueCode: folder.leagueCode)
        default:
            return nil
        }
    }

    // MARK: - 정규화

    private static func normalized(_ name: String) -> String {
        name.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: "")
    }

    // MARK: - Rule 타입

    private struct StadiumRule {
        let keyword: String
        let coord: CLLocationCoordinate2D
    }

    private static func firstMatch(_ norm: String, in rules: [StadiumRule]) -> CLLocationCoordinate2D? {
        rules.first { norm.contains($0.keyword) }?.coord
    }

    // MARK: - NFL (32팀)

    private static func nflLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: nflRules)
    }

    private static let nflRules: [StadiumRule] = [
        // AFC East
        .init(keyword: "bills",       coord: .init(latitude: 42.7738,  longitude: -78.7869)),  // Highmark Stadium
        .init(keyword: "dolphins",    coord: .init(latitude: 25.9580,  longitude: -80.2389)),  // Hard Rock Stadium
        .init(keyword: "patriots",    coord: .init(latitude: 42.0909,  longitude: -71.2643)),  // Gillette Stadium
        .init(keyword: "jets",        coord: .init(latitude: 40.8135,  longitude: -74.0745)),  // MetLife Stadium
        // AFC North
        .init(keyword: "ravens",      coord: .init(latitude: 39.2780,  longitude: -76.6228)),  // M&T Bank Stadium
        .init(keyword: "bengals",     coord: .init(latitude: 39.0954,  longitude: -84.5160)),  // Paycor Stadium
        .init(keyword: "browns",      coord: .init(latitude: 41.5061,  longitude: -81.6995)),  // Huntington Bank Field
        .init(keyword: "steelers",    coord: .init(latitude: 40.4468,  longitude: -80.0158)),  // Acrisure Stadium
        // AFC South
        .init(keyword: "texans",      coord: .init(latitude: 29.6847,  longitude: -95.4107)),  // NRG Stadium
        .init(keyword: "colts",       coord: .init(latitude: 39.7601,  longitude: -86.1638)),  // Lucas Oil Stadium
        .init(keyword: "jaguars",     coord: .init(latitude: 30.3240,  longitude: -81.6374)),  // EverBank Stadium
        .init(keyword: "titans",      coord: .init(latitude: 36.1665,  longitude: -86.7713)),  // Nissan Stadium
        // AFC West
        .init(keyword: "chiefs",      coord: .init(latitude: 39.0489,  longitude: -94.4839)),  // Arrowhead Stadium
        .init(keyword: "raiders",     coord: .init(latitude: 36.0909,  longitude: -115.1833)), // Allegiant Stadium
        .init(keyword: "chargers",    coord: .init(latitude: 33.9534,  longitude: -118.3387)), // SoFi Stadium
        .init(keyword: "broncos",     coord: .init(latitude: 39.7439,  longitude: -105.0201)), // Empower Field
        // NFC East
        .init(keyword: "cowboys",     coord: .init(latitude: 32.7480,  longitude: -97.0928)),  // AT&T Stadium
        .init(keyword: "giants",      coord: .init(latitude: 40.8135,  longitude: -74.0745)),  // MetLife Stadium
        .init(keyword: "eagles",      coord: .init(latitude: 39.9008,  longitude: -75.1675)),  // Lincoln Financial Field
        .init(keyword: "commanders",  coord: .init(latitude: 38.9076,  longitude: -76.8645)),  // Northwest Stadium
        // NFC North
        .init(keyword: "bears",       coord: .init(latitude: 41.8623,  longitude: -87.6167)),  // Soldier Field
        .init(keyword: "lions",       coord: .init(latitude: 42.3400,  longitude: -83.0456)),  // Ford Field
        .init(keyword: "packers",     coord: .init(latitude: 44.5013,  longitude: -88.0622)),  // Lambeau Field
        .init(keyword: "vikings",     coord: .init(latitude: 44.9735,  longitude: -93.2575)),  // U.S. Bank Stadium
        // NFC South
        .init(keyword: "falcons",     coord: .init(latitude: 33.7554,  longitude: -84.4010)),  // Mercedes-Benz Stadium
        .init(keyword: "panthers",    coord: .init(latitude: 35.2258,  longitude: -80.8528)),  // Bank of America Stadium
        .init(keyword: "saints",      coord: .init(latitude: 29.9511,  longitude: -90.0812)),  // Caesars Superdome
        .init(keyword: "buccaneers",  coord: .init(latitude: 27.9759,  longitude: -82.5033)),  // Raymond James Stadium
        // NFC West
        .init(keyword: "49ers",       coord: .init(latitude: 37.4033,  longitude: -121.9694)), // Levi's Stadium
        .init(keyword: "seahawks",    coord: .init(latitude: 47.5952,  longitude: -122.3316)), // Lumen Field
        .init(keyword: "rams",        coord: .init(latitude: 33.9534,  longitude: -118.3387)), // SoFi Stadium
        .init(keyword: "cardinals",   coord: .init(latitude: 33.5277,  longitude: -112.2626)), // State Farm Stadium
    ]

    // MARK: - NBA (30팀)

    private static func nbaLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: nbaRules)
    }

    private static let nbaRules: [StadiumRule] = [
        // Atlantic
        .init(keyword: "celtics",        coord: .init(latitude: 42.3662,  longitude: -71.0621)),  // TD Garden
        .init(keyword: "nets",           coord: .init(latitude: 40.6826,  longitude: -73.9754)),  // Barclays Center
        .init(keyword: "knicks",         coord: .init(latitude: 40.7505,  longitude: -73.9934)),  // Madison Square Garden
        .init(keyword: "76ers",          coord: .init(latitude: 39.9012,  longitude: -75.1720)),  // Wells Fargo Center
        .init(keyword: "sixers",         coord: .init(latitude: 39.9012,  longitude: -75.1720)),
        .init(keyword: "raptors",        coord: .init(latitude: 43.6435,  longitude: -79.3791)),  // Scotiabank Arena
        // Central
        .init(keyword: "bulls",          coord: .init(latitude: 41.8806,  longitude: -87.6742)),  // United Center
        .init(keyword: "cavaliers",      coord: .init(latitude: 41.4965,  longitude: -81.6882)),  // Rocket Mortgage FieldHouse
        .init(keyword: "cavs",           coord: .init(latitude: 41.4965,  longitude: -81.6882)),
        .init(keyword: "pistons",        coord: .init(latitude: 42.3410,  longitude: -83.0554)),  // Little Caesars Arena
        .init(keyword: "pacers",         coord: .init(latitude: 39.7640,  longitude: -86.1555)),  // Gainbridge Fieldhouse
        .init(keyword: "bucks",          coord: .init(latitude: 43.0450,  longitude: -87.9170)),  // Fiserv Forum
        // Southeast
        .init(keyword: "hawks",          coord: .init(latitude: 33.7573,  longitude: -84.3963)),  // State Farm Arena
        .init(keyword: "hornets",        coord: .init(latitude: 35.2252,  longitude: -80.8393)),  // Spectrum Center
        .init(keyword: "heat",           coord: .init(latitude: 25.7814,  longitude: -80.1870)),  // Kaseya Center
        .init(keyword: "magic",          coord: .init(latitude: 28.5392,  longitude: -81.3837)),  // Kia Center
        .init(keyword: "wizards",        coord: .init(latitude: 38.8981,  longitude: -77.0209)),  // Capital One Arena
        // Northwest
        .init(keyword: "nuggets",        coord: .init(latitude: 39.7487,  longitude: -105.0077)), // Ball Arena
        .init(keyword: "timberwolves",   coord: .init(latitude: 44.9795,  longitude: -93.2760)),  // Target Center
        .init(keyword: "thunder",        coord: .init(latitude: 35.4634,  longitude: -97.5151)),  // Paycom Center
        .init(keyword: "trailblazers",   coord: .init(latitude: 45.5316,  longitude: -122.6668)), // Moda Center
        .init(keyword: "blazers",        coord: .init(latitude: 45.5316,  longitude: -122.6668)),
        .init(keyword: "jazz",           coord: .init(latitude: 40.7683,  longitude: -111.9011)), // Delta Center
        // Pacific
        .init(keyword: "warriors",       coord: .init(latitude: 37.7680,  longitude: -122.3877)), // Chase Center
        .init(keyword: "clippers",       coord: .init(latitude: 33.8617,  longitude: -118.3351)), // Intuit Dome
        .init(keyword: "lakers",         coord: .init(latitude: 34.0430,  longitude: -118.2673)), // Crypto.com Arena
        .init(keyword: "suns",           coord: .init(latitude: 33.4457,  longitude: -112.0712)), // Footprint Center
        .init(keyword: "kings",          coord: .init(latitude: 38.5802,  longitude: -121.4996)), // Golden 1 Center
        // Southwest
        .init(keyword: "mavericks",      coord: .init(latitude: 32.7905,  longitude: -96.8103)),  // American Airlines Center
        .init(keyword: "mavs",           coord: .init(latitude: 32.7905,  longitude: -96.8103)),
        .init(keyword: "rockets",        coord: .init(latitude: 29.7508,  longitude: -95.3621)),  // Toyota Center
        .init(keyword: "grizzlies",      coord: .init(latitude: 35.1383,  longitude: -90.0505)),  // FedExForum
        .init(keyword: "pelicans",       coord: .init(latitude: 29.9490,  longitude: -90.0812)),  // Smoothie King Center
        .init(keyword: "spurs",          coord: .init(latitude: 29.4269,  longitude: -98.4375)),  // Frost Bank Center
    ]

    // MARK: - Baseball

    private static func baseballLookup(_ norm: String, leagueCode: String?) -> CLLocationCoordinate2D? {
        let code = leagueCode?.uppercased() ?? ""
        switch code {
        case "MLB": return mlbLookup(norm)
        case "KBO": return kboLookup(norm)
        default:    return mlbLookup(norm) ?? kboLookup(norm)
        }
    }

    // MLB (30팀)
    private static func mlbLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: mlbRules)
    }

    private static let mlbRules: [StadiumRule] = [
        // AL East
        .init(keyword: "orioles",         coord: .init(latitude: 39.2840,  longitude: -76.6217)),  // Oriole Park at Camden Yards
        .init(keyword: "redsox",          coord: .init(latitude: 42.3467,  longitude: -71.0972)),  // Fenway Park
        .init(keyword: "yankees",         coord: .init(latitude: 40.8296,  longitude: -73.9262)),  // Yankee Stadium
        .init(keyword: "rays",            coord: .init(latitude: 27.7683,  longitude: -82.6534)),  // Tropicana Field
        .init(keyword: "bluejays",        coord: .init(latitude: 43.6414,  longitude: -79.3894)),  // Rogers Centre
        // AL Central
        .init(keyword: "whitesox",        coord: .init(latitude: 41.8299,  longitude: -87.6338)),  // Guaranteed Rate Field
        .init(keyword: "guardians",       coord: .init(latitude: 41.4962,  longitude: -81.6853)),  // Progressive Field
        .init(keyword: "tigers",          coord: .init(latitude: 42.3390,  longitude: -83.0485)),  // Comerica Park
        .init(keyword: "royals",          coord: .init(latitude: 39.0517,  longitude: -94.4803)),  // Kauffman Stadium
        .init(keyword: "twins",           coord: .init(latitude: 44.9817,  longitude: -93.2781)),  // Target Field
        // AL West
        .init(keyword: "astros",          coord: .init(latitude: 29.7572,  longitude: -95.3555)),  // Minute Maid Park
        .init(keyword: "angels",          coord: .init(latitude: 33.8003,  longitude: -117.8827)), // Angel Stadium
        .init(keyword: "athletics",       coord: .init(latitude: 38.5849,  longitude: -121.5011)), // Sutter Health Park (Sacramento)
        .init(keyword: "mariners",        coord: .init(latitude: 47.5914,  longitude: -122.3325)), // T-Mobile Park
        .init(keyword: "rangers",         coord: .init(latitude: 32.7473,  longitude: -97.0845)),  // Globe Life Field
        // NL East
        .init(keyword: "braves",          coord: .init(latitude: 33.8908,  longitude: -84.4678)),  // Truist Park
        .init(keyword: "marlins",         coord: .init(latitude: 25.7781,  longitude: -80.2197)),  // loanDepot park
        .init(keyword: "mets",            coord: .init(latitude: 40.7571,  longitude: -73.8458)),  // Citi Field
        .init(keyword: "phillies",        coord: .init(latitude: 39.9061,  longitude: -75.1665)),  // Citizens Bank Park
        .init(keyword: "nationals",       coord: .init(latitude: 38.8729,  longitude: -77.0074)),  // Nationals Park
        // NL Central
        .init(keyword: "cubs",            coord: .init(latitude: 41.9484,  longitude: -87.6553)),  // Wrigley Field
        .init(keyword: "reds",            coord: .init(latitude: 39.0979,  longitude: -84.5085)),  // Great American Ball Park
        .init(keyword: "brewers",         coord: .init(latitude: 43.0282,  longitude: -87.9712)),  // American Family Field
        .init(keyword: "pirates",         coord: .init(latitude: 40.4468,  longitude: -80.0058)),  // PNC Park
        .init(keyword: "stlcardinals",    coord: .init(latitude: 38.6226,  longitude: -90.1928)),  // Busch Stadium
        .init(keyword: "cardinals",       coord: .init(latitude: 38.6226,  longitude: -90.1928)),  // Busch Stadium (NFL에서는 americanFootball로 분기)
        // NL West
        .init(keyword: "diamondbacks",    coord: .init(latitude: 33.4455,  longitude: -112.0667)), // Chase Field
        .init(keyword: "dbacks",          coord: .init(latitude: 33.4455,  longitude: -112.0667)),
        .init(keyword: "rockies",         coord: .init(latitude: 39.7559,  longitude: -104.9942)), // Coors Field
        .init(keyword: "dodgers",         coord: .init(latitude: 34.0739,  longitude: -118.2400)), // Dodger Stadium
        .init(keyword: "padres",          coord: .init(latitude: 32.7073,  longitude: -117.1566)), // Petco Park
        .init(keyword: "sfgiants",        coord: .init(latitude: 37.7786,  longitude: -122.3893)), // Oracle Park
        .init(keyword: "sanfrancisco",    coord: .init(latitude: 37.7786,  longitude: -122.3893)),
        .init(keyword: "giants",          coord: .init(latitude: 37.7786,  longitude: -122.3893)), // baseball 분기 내에서만 매칭
    ]

    // KBO (10팀)
    private static func kboLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: kboRules)
    }

    private static let kboRules: [StadiumRule] = [
        .init(keyword: "kiwoom",    coord: .init(latitude: 37.4982,  longitude: 126.8672)), // 고척 스카이돔
        .init(keyword: "키움",      coord: .init(latitude: 37.4982,  longitude: 126.8672)),
        .init(keyword: "doosan",    coord: .init(latitude: 37.5120,  longitude: 127.0719)), // 잠실 야구장
        .init(keyword: "두산",      coord: .init(latitude: 37.5120,  longitude: 127.0719)),
        .init(keyword: "lgtwins",   coord: .init(latitude: 37.5120,  longitude: 127.0719)),
        .init(keyword: "엘지",      coord: .init(latitude: 37.5120,  longitude: 127.0719)),
        .init(keyword: "lg",        coord: .init(latitude: 37.5120,  longitude: 127.0719)),
        .init(keyword: "ssg",       coord: .init(latitude: 37.4370,  longitude: 126.6932)), // 인천 SSG 랜더스필드
        .init(keyword: "ktwiz",     coord: .init(latitude: 37.2997,  longitude: 127.0097)), // 수원 KT 위즈파크
        .init(keyword: "케이티",    coord: .init(latitude: 37.2997,  longitude: 127.0097)),
        .init(keyword: "samsung",   coord: .init(latitude: 35.8411,  longitude: 128.6814)), // 대구 삼성 라이온즈파크
        .init(keyword: "삼성",      coord: .init(latitude: 35.8411,  longitude: 128.6814)),
        .init(keyword: "lotte",     coord: .init(latitude: 35.1938,  longitude: 129.0617)), // 사직 야구장
        .init(keyword: "롯데",      coord: .init(latitude: 35.1938,  longitude: 129.0617)),
        .init(keyword: "hanwha",    coord: .init(latitude: 36.3174,  longitude: 127.4289)), // 한화생명이글스파크
        .init(keyword: "한화",      coord: .init(latitude: 36.3174,  longitude: 127.4289)),
        .init(keyword: "ncdino",    coord: .init(latitude: 35.2226,  longitude: 128.5819)), // 창원 NC 파크
        .init(keyword: "nc다이",    coord: .init(latitude: 35.2226,  longitude: 128.5819)),
        .init(keyword: "nc",        coord: .init(latitude: 35.2226,  longitude: 128.5819)),
        .init(keyword: "kiatigers", coord: .init(latitude: 35.1681,  longitude: 126.8892)), // 광주 기아 챔피언스필드
        .init(keyword: "기아",      coord: .init(latitude: 35.1681,  longitude: 126.8892)),
    ]

    // MARK: - Soccer

    private static func soccerLookup(_ norm: String, leagueCode: String?) -> CLLocationCoordinate2D? {
        let code = leagueCode?.uppercased() ?? ""
        switch code {
        case "ENG.1", "EPL", "ENG.FA", "ENG.LEAGUE_CUP":
            return eplLookup(norm)
        case "ESP.1", "LALIGA", "ESP.COPA":
            return laligaLookup(norm)
        case "GER.1", "BUNDESLIGA", "GER.DFB":
            return bundesligaLookup(norm)
        case "ITA.1", "SERIEA", "ITA.COPPA":
            return serieaLookup(norm)
        case "FRA.1", "LIGUE1", "FRA.COUPE_DE_FRANCE":
            return ligue1Lookup(norm)
        case "USA.1", "MLS":
            return mlsLookup(norm)
        case "NED.1", "EREDIVISIE":
            return erediviseLookup(norm)
        case "POR.1", "PRIMEIRALG":
            return primeiraLigaLookup(norm)
        case "TUR.1", "SUPERLIG":
            return superLigLookup(norm)
        case "BEL.1", "PROLEAGUE":
            return belgianProLeagueLookup(norm)
        case "GRE.1", "SUPERLEAGR":
            return greekSuperLeagueLookup(norm)
        case "CZE.1", "FIRSTLIGA":
            return czechFirstLeagueLookup(norm)
        case "DEN.1", "SUPERLIGA":
            return danishSuperligaLookup(norm)
        case "UEFA.CHAMPIONS", "UEFA.EUROPA":
            // 유럽 전 리그 순회
            return eplLookup(norm)
                ?? laligaLookup(norm)
                ?? bundesligaLookup(norm)
                ?? serieaLookup(norm)
                ?? ligue1Lookup(norm)
                ?? erediviseLookup(norm)
                ?? primeiraLigaLookup(norm)
                ?? superLigLookup(norm)
                ?? belgianProLeagueLookup(norm)
        default:
            return nil
        }
    }

    // EPL (20팀)
    private static func eplLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: eplRules)
    }

    private static let eplRules: [StadiumRule] = [
        .init(keyword: "manchestercity",   coord: .init(latitude: 53.4831,  longitude: -2.2004)),  // Etihad Stadium
        .init(keyword: "manchesterunited", coord: .init(latitude: 53.4631,  longitude: -2.2913)),  // Old Trafford
        .init(keyword: "mancity",          coord: .init(latitude: 53.4831,  longitude: -2.2004)),
        .init(keyword: "manutd",           coord: .init(latitude: 53.4631,  longitude: -2.2913)),
        .init(keyword: "manunited",        coord: .init(latitude: 53.4631,  longitude: -2.2913)),
        .init(keyword: "crystalpalace",    coord: .init(latitude: 51.3983,  longitude: -0.0855)),  // Selhurst Park
        .init(keyword: "astonvilla",       coord: .init(latitude: 52.5092,  longitude: -1.8847)),  // Villa Park
        .init(keyword: "westham",          coord: .init(latitude: 51.5386,  longitude: -0.0168)),  // London Stadium
        .init(keyword: "wolverhampton",    coord: .init(latitude: 52.5904,  longitude: -2.1302)),  // Molineux
        .init(keyword: "wolves",           coord: .init(latitude: 52.5904,  longitude: -2.1302)),
        .init(keyword: "nottingham",       coord: .init(latitude: 52.9399,  longitude: -1.1323)),  // City Ground
        .init(keyword: "tottenham",        coord: .init(latitude: 51.6042,  longitude: -0.0665)),  // Tottenham Hotspur Stadium
        .init(keyword: "spurs",            coord: .init(latitude: 51.6042,  longitude: -0.0665)),
        .init(keyword: "newcastle",        coord: .init(latitude: 54.9756,  longitude: -1.6217)),  // St. James' Park
        .init(keyword: "liverpool",        coord: .init(latitude: 53.4308,  longitude: -2.9608)),  // Anfield
        .init(keyword: "arsenal",          coord: .init(latitude: 51.5549,  longitude: -0.1084)),  // Emirates Stadium
        .init(keyword: "chelsea",          coord: .init(latitude: 51.4816,  longitude: -0.1910)),  // Stamford Bridge
        .init(keyword: "brighton",         coord: .init(latitude: 50.8612,  longitude: -0.0836)),  // Amex Stadium
        .init(keyword: "everton",          coord: .init(latitude: 53.4388,  longitude: -2.9662)),  // Goodison Park
        .init(keyword: "fulham",           coord: .init(latitude: 51.4749,  longitude: -0.2217)),  // Craven Cottage
        .init(keyword: "brentford",        coord: .init(latitude: 51.4882,  longitude: -0.2886)),  // Gtech Community Stadium
        .init(keyword: "southampton",      coord: .init(latitude: 50.9058,  longitude: -1.3914)),  // St. Mary's Stadium
        .init(keyword: "ipswich",          coord: .init(latitude: 52.0544,  longitude:  1.1446)),  // Portman Road
        .init(keyword: "leicester",        coord: .init(latitude: 52.6204,  longitude: -1.1422)),  // King Power Stadium
        .init(keyword: "bournemouth",      coord: .init(latitude: 50.7352,  longitude: -1.8382)),  // Vitality Stadium
    ]

    // La Liga (20팀)
    private static func laligaLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: laligaRules)
    }

    private static let laligaRules: [StadiumRule] = [
        .init(keyword: "realmadrid",     coord: .init(latitude: 40.4531,  longitude: -3.6883)),  // Santiago Bernabéu
        .init(keyword: "atleticomadrid", coord: .init(latitude: 40.4361,  longitude: -3.5996)),  // Civitas Metropolitano
        .init(keyword: "atletico",       coord: .init(latitude: 40.4361,  longitude: -3.5996)),
        .init(keyword: "fcbarcelona",    coord: .init(latitude: 41.3809,  longitude:  2.1228)),  // Estadi Olímpic / Camp Nou
        .init(keyword: "barcelona",      coord: .init(latitude: 41.3809,  longitude:  2.1228)),
        .init(keyword: "sevilla",        coord: .init(latitude: 37.3840,  longitude: -5.9708)),  // Estadio Ramón Sánchez-Pizjuán
        .init(keyword: "realsociedad",   coord: .init(latitude: 43.3016,  longitude: -2.0007)),  // Reale Arena
        .init(keyword: "athleticclub",   coord: .init(latitude: 43.2641,  longitude: -2.9499)),  // San Mamés
        .init(keyword: "bilbao",         coord: .init(latitude: 43.2641,  longitude: -2.9499)),
        .init(keyword: "realbetis",      coord: .init(latitude: 37.3567,  longitude: -5.9811)),  // Estadio Benito Villamarín
        .init(keyword: "betis",          coord: .init(latitude: 37.3567,  longitude: -5.9811)),
        .init(keyword: "villarreal",     coord: .init(latitude: 39.9441,  longitude: -0.1030)),  // Estadio de la Cerámica
        .init(keyword: "valencia",       coord: .init(latitude: 39.4745,  longitude: -0.3581)),  // Estadio Mestalla
        .init(keyword: "celtavigo",      coord: .init(latitude: 42.2113,  longitude: -8.7395)),  // Abanca-Balaídos
        .init(keyword: "celta",          coord: .init(latitude: 42.2113,  longitude: -8.7395)),
        .init(keyword: "osasuna",        coord: .init(latitude: 42.7967,  longitude: -1.6369)),  // El Sadar
        .init(keyword: "getafe",         coord: .init(latitude: 40.3238,  longitude: -3.7181)),  // Coliseum Alfonso Pérez
        .init(keyword: "girona",         coord: .init(latitude: 41.9627,  longitude:  2.8273)),  // Estadio Municipal de Montilivi
        .init(keyword: "laspalmas",      coord: .init(latitude: 28.1007,  longitude: -15.4502)), // Estadio de Gran Canaria
        .init(keyword: "rayo",           coord: .init(latitude: 40.3917,  longitude: -3.6597)),  // Estadio de Vallecas
        .init(keyword: "alaves",         coord: .init(latitude: 42.8421,  longitude: -2.6816)),  // Estadio de Mendizorroza
        .init(keyword: "leganes",        coord: .init(latitude: 40.3286,  longitude: -3.7766)),  // Estadio Municipal de Butarque
        .init(keyword: "espanyol",       coord: .init(latitude: 41.3473,  longitude:  2.0752)),  // RCDE Stadium
        .init(keyword: "mallorca",       coord: .init(latitude: 39.5891,  longitude:  2.6327)),  // Visit Mallorca Estadi
        .init(keyword: "valladolid",     coord: .init(latitude: 41.6427,  longitude: -4.7285)),  // Estadio José Zorrilla
    ]

    // Bundesliga (18팀)
    private static func bundesligaLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: bundesligaRules)
    }

    private static let bundesligaRules: [StadiumRule] = [
        .init(keyword: "bayernmunich",          coord: .init(latitude: 48.2188,  longitude: 11.6248)), // Allianz Arena
        .init(keyword: "fcbayern",              coord: .init(latitude: 48.2188,  longitude: 11.6248)),
        .init(keyword: "bayern",                coord: .init(latitude: 48.2188,  longitude: 11.6248)),
        .init(keyword: "borussiadortmund",      coord: .init(latitude: 51.4926,  longitude:  7.4519)), // Signal Iduna Park
        .init(keyword: "dortmund",              coord: .init(latitude: 51.4926,  longitude:  7.4519)),
        .init(keyword: "bayer04",               coord: .init(latitude: 51.0384,  longitude:  7.0024)), // BayArena
        .init(keyword: "leverkusen",            coord: .init(latitude: 51.0384,  longitude:  7.0024)),
        .init(keyword: "rbleipzig",             coord: .init(latitude: 51.3457,  longitude: 12.3483)), // Red Bull Arena Leipzig
        .init(keyword: "leipzig",               coord: .init(latitude: 51.3457,  longitude: 12.3483)),
        .init(keyword: "borussiamonchengladbach", coord: .init(latitude: 51.1744, longitude:  6.3850)), // Borussia-Park
        .init(keyword: "monchengladbach",       coord: .init(latitude: 51.1744,  longitude:  6.3850)),
        .init(keyword: "gladbach",              coord: .init(latitude: 51.1744,  longitude:  6.3850)),
        .init(keyword: "unionberlin",           coord: .init(latitude: 52.4573,  longitude: 13.5680)), // An der Alten Försterei
        .init(keyword: "eintrachtfrankfurt",    coord: .init(latitude: 50.0686,  longitude:  8.6455)), // Deutsche Bank Park
        .init(keyword: "frankfurt",             coord: .init(latitude: 50.0686,  longitude:  8.6455)),
        .init(keyword: "werderbremen",          coord: .init(latitude: 53.0663,  longitude:  8.8377)), // Weserstadion
        .init(keyword: "werder",                coord: .init(latitude: 53.0663,  longitude:  8.8377)),
        .init(keyword: "wolfsburg",             coord: .init(latitude: 52.4322,  longitude: 10.8030)), // Volkswagen Arena
        .init(keyword: "vfbstuttgart",          coord: .init(latitude: 48.7924,  longitude:  9.2323)), // MHP Arena
        .init(keyword: "stuttgart",             coord: .init(latitude: 48.7924,  longitude:  9.2323)),
        .init(keyword: "hoffenheim",            coord: .init(latitude: 49.2388,  longitude:  8.8886)), // PreZero Arena
        .init(keyword: "scfreiburg",            coord: .init(latitude: 47.9961,  longitude:  7.8962)), // Europa-Park Stadion
        .init(keyword: "freiburg",              coord: .init(latitude: 47.9961,  longitude:  7.8962)),
        .init(keyword: "fcaugsburg",            coord: .init(latitude: 48.3237,  longitude: 10.8862)), // WWK Arena
        .init(keyword: "augsburg",              coord: .init(latitude: 48.3237,  longitude: 10.8862)),
        .init(keyword: "1fsmainz",              coord: .init(latitude: 49.9842,  longitude:  8.2246)), // MEWA Arena
        .init(keyword: "mainz",                 coord: .init(latitude: 49.9842,  longitude:  8.2246)),
        .init(keyword: "heidenheim",            coord: .init(latitude: 48.6780,  longitude: 10.1555)), // Voith-Arena
        .init(keyword: "holsteinkiel",          coord: .init(latitude: 54.3389,  longitude: 10.1203)), // Holstein-Stadion
        .init(keyword: "kiel",                  coord: .init(latitude: 54.3389,  longitude: 10.1203)),
        .init(keyword: "stpauli",               coord: .init(latitude: 53.5540,  longitude:  9.9680)), // Millerntor-Stadion
        .init(keyword: "pauli",                 coord: .init(latitude: 53.5540,  longitude:  9.9680)),
        .init(keyword: "vflbochum",             coord: .init(latitude: 51.4900,  longitude:  7.2396)), // Vonovia Ruhrstadion
        .init(keyword: "bochum",                coord: .init(latitude: 51.4900,  longitude:  7.2396)),
    ]

    // Serie A (20팀)
    private static func serieaLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: serieaRules)
    }

    private static let serieaRules: [StadiumRule] = [
        .init(keyword: "juventus",    coord: .init(latitude: 45.1096,  longitude:  7.6413)), // Allianz Stadium
        .init(keyword: "intermilan",  coord: .init(latitude: 45.4781,  longitude:  9.1240)), // Giuseppe Meazza (San Siro)
        .init(keyword: "internazionale", coord: .init(latitude: 45.4781, longitude: 9.1240)),
        .init(keyword: "acmilan",     coord: .init(latitude: 45.4781,  longitude:  9.1240)), // Giuseppe Meazza (San Siro)
        .init(keyword: "napoli",      coord: .init(latitude: 40.8279,  longitude: 14.1931)), // Diego Armando Maradona
        .init(keyword: "asroma",      coord: .init(latitude: 41.9334,  longitude: 12.4546)), // Stadio Olimpico
        .init(keyword: "roma",        coord: .init(latitude: 41.9334,  longitude: 12.4546)),
        .init(keyword: "lazio",       coord: .init(latitude: 41.9334,  longitude: 12.4546)), // Stadio Olimpico (shared)
        .init(keyword: "atalanta",    coord: .init(latitude: 45.7087,  longitude:  9.6800)), // Gewiss Stadium
        .init(keyword: "fiorentina",  coord: .init(latitude: 43.7803,  longitude: 11.2822)), // Stadio Artemio Franchi
        .init(keyword: "torino",      coord: .init(latitude: 45.0426,  longitude:  7.6505)), // Olimpico Grande Torino
        .init(keyword: "bologna",     coord: .init(latitude: 44.4928,  longitude: 11.3092)), // Stadio Renato Dall'Ara
        .init(keyword: "verona",      coord: .init(latitude: 45.4385,  longitude: 10.9793)), // Stadio Bentegodi
        .init(keyword: "hellas",      coord: .init(latitude: 45.4385,  longitude: 10.9793)),
        .init(keyword: "udinese",     coord: .init(latitude: 46.0794,  longitude: 13.1773)), // Bluenergy Stadium
        .init(keyword: "cagliari",    coord: .init(latitude: 39.2089,  longitude:  9.1369)), // Unipol Domus
        .init(keyword: "lecce",       coord: .init(latitude: 40.3530,  longitude: 18.1690)), // Stadio Via del Mare
        .init(keyword: "empoli",      coord: .init(latitude: 43.7183,  longitude: 10.9507)), // Stadio Carlo Castellani
        .init(keyword: "monza",       coord: .init(latitude: 45.6010,  longitude:  9.2897)), // U-Power Stadium
        .init(keyword: "como",        coord: .init(latitude: 45.8158,  longitude:  9.0835)), // Stadio Giuseppe Sinigaglia
        .init(keyword: "venezia",     coord: .init(latitude: 45.4258,  longitude: 12.3660)), // Stadio Pier Luigi Penzo
        .init(keyword: "parma",       coord: .init(latitude: 44.7987,  longitude: 10.3404)), // Stadio Ennio Tardini
        .init(keyword: "genoa",       coord: .init(latitude: 44.4166,  longitude:  8.9517)), // Stadio Luigi Ferraris
        .init(keyword: "inter",       coord: .init(latitude: 45.4781,  longitude:  9.1240)), // fallback for "Inter"
        .init(keyword: "milan",       coord: .init(latitude: 45.4781,  longitude:  9.1240)), // fallback for "Milan"
    ]

    // Ligue 1 (18팀)
    private static func ligue1Lookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: ligue1Rules)
    }

    private static let ligue1Rules: [StadiumRule] = [
        .init(keyword: "parissaintgermain", coord: .init(latitude: 48.8414, longitude:  2.2530)), // Parc des Princes
        .init(keyword: "psg",               coord: .init(latitude: 48.8414, longitude:  2.2530)),
        .init(keyword: "olympiquedemarseille", coord: .init(latitude: 43.2696, longitude: 5.3959)), // Stade Orange Vélodrome
        .init(keyword: "marseille",         coord: .init(latitude: 43.2696, longitude:  5.3959)),
        .init(keyword: "asmonaco",          coord: .init(latitude: 43.7274, longitude:  7.4154)), // Stade Louis II
        .init(keyword: "monaco",            coord: .init(latitude: 43.7274, longitude:  7.4154)),
        .init(keyword: "losc",              coord: .init(latitude: 50.6116, longitude:  3.1302)), // Stade Pierre-Mauroy
        .init(keyword: "lille",             coord: .init(latitude: 50.6116, longitude:  3.1302)),
        .init(keyword: "olympiquelyon",     coord: .init(latitude: 45.7651, longitude:  4.9824)), // Groupama Stadium
        .init(keyword: "lyon",              coord: .init(latitude: 45.7651, longitude:  4.9824)),
        .init(keyword: "ogcnice",           coord: .init(latitude: 43.7052, longitude:  7.1922)), // Allianz Riviera
        .init(keyword: "nice",              coord: .init(latitude: 43.7052, longitude:  7.1922)),
        .init(keyword: "rclens",            coord: .init(latitude: 50.4333, longitude:  2.8147)), // Stade Bollaert-Delelis
        .init(keyword: "lens",              coord: .init(latitude: 50.4333, longitude:  2.8147)),
        .init(keyword: "staderennes",       coord: .init(latitude: 48.1076, longitude: -1.7120)), // Roazhon Park
        .init(keyword: "rennes",            coord: .init(latitude: 48.1076, longitude: -1.7120)),
        .init(keyword: "rcstrasbourg",      coord: .init(latitude: 48.5598, longitude:  7.7505)), // Stade de la Meinau
        .init(keyword: "strasbourg",        coord: .init(latitude: 48.5598, longitude:  7.7505)),
        .init(keyword: "toulouse",          coord: .init(latitude: 43.5827, longitude:  1.4342)), // Stadium de Toulouse
        .init(keyword: "reims",             coord: .init(latitude: 49.2596, longitude:  4.0393)), // Stade Auguste-Delaune
        .init(keyword: "montpellier",       coord: .init(latitude: 43.6200, longitude:  3.8134)), // Stade de la Mosson
        .init(keyword: "brest",             coord: .init(latitude: 48.3914, longitude: -4.4851)), // Stade Francis-Le Blé
        .init(keyword: "nantes",            coord: .init(latitude: 47.2558, longitude: -1.5251)), // Stade de la Beaujoire
        .init(keyword: "saintetienne",      coord: .init(latitude: 45.4605, longitude:  4.3900)), // Stade Geoffroy-Guichard
        .init(keyword: "auxerre",           coord: .init(latitude: 47.7939, longitude:  3.5722)), // Stade de l'Abbé-Deschamps
        .init(keyword: "havre",             coord: .init(latitude: 49.4994, longitude:  0.0876)), // Stade Océane
        .init(keyword: "angers",            coord: .init(latitude: 47.4703, longitude: -0.5604)), // Stade Raymond-Kopa
    ]

    // MLS (30팀)
    private static func mlsLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: mlsRules)
    }

    private static let mlsRules: [StadiumRule] = [
        // Eastern Conference
        .init(keyword: "atlantaunited",  coord: .init(latitude: 33.7554,  longitude: -84.4010)),  // Mercedes-Benz Stadium
        .init(keyword: "charlottefc",    coord: .init(latitude: 35.2258,  longitude: -80.8528)),  // Bank of America Stadium
        .init(keyword: "chicagofire",    coord: .init(latitude: 41.8623,  longitude: -87.6167)),  // Soldier Field
        .init(keyword: "fccincinnati",   coord: .init(latitude: 39.1063,  longitude: -84.5230)),  // TQL Stadium
        .init(keyword: "cincinnati",     coord: .init(latitude: 39.1063,  longitude: -84.5230)),
        .init(keyword: "columbuscrew",   coord: .init(latitude: 39.9694,  longitude: -83.0065)),  // Lower.com Field
        .init(keyword: "columbus",       coord: .init(latitude: 39.9694,  longitude: -83.0065)),
        .init(keyword: "dcunited",       coord: .init(latitude: 38.8682,  longitude: -77.0124)),  // Audi Field
        .init(keyword: "intermiamicf",   coord: .init(latitude: 26.1913,  longitude: -80.1425)),  // Chase Stadium
        .init(keyword: "intermiami",     coord: .init(latitude: 26.1913,  longitude: -80.1425)),
        .init(keyword: "cfmontreal",     coord: .init(latitude: 45.5631,  longitude: -73.5514)),  // Saputo Stadium
        .init(keyword: "montreal",       coord: .init(latitude: 45.5631,  longitude: -73.5514)),
        .init(keyword: "nashvillesc",    coord: .init(latitude: 36.1314,  longitude: -86.7630)),  // GEODIS Park
        .init(keyword: "nashville",      coord: .init(latitude: 36.1314,  longitude: -86.7630)),
        .init(keyword: "newenglandrevolution", coord: .init(latitude: 42.0909, longitude: -71.2643)), // Gillette Stadium
        .init(keyword: "newengland",     coord: .init(latitude: 42.0909,  longitude: -71.2643)),
        .init(keyword: "newyorkcityfc",  coord: .init(latitude: 40.8296,  longitude: -73.9262)),  // Yankee Stadium
        .init(keyword: "nycfc",          coord: .init(latitude: 40.8296,  longitude: -73.9262)),
        .init(keyword: "newyorkredbulls",coord: .init(latitude: 40.7369,  longitude: -74.1507)),  // Red Bull Arena
        .init(keyword: "redbulls",       coord: .init(latitude: 40.7369,  longitude: -74.1507)),
        .init(keyword: "orlandocity",    coord: .init(latitude: 28.5426,  longitude: -81.3898)),  // Inter&Co Stadium
        .init(keyword: "orlando",        coord: .init(latitude: 28.5426,  longitude: -81.3898)),
        .init(keyword: "philadelphiaunion", coord: .init(latitude: 39.8324, longitude: -75.3812)), // Subaru Park
        .init(keyword: "philadelphia",   coord: .init(latitude: 39.8324,  longitude: -75.3812)),
        .init(keyword: "torontofc",      coord: .init(latitude: 43.6334,  longitude: -79.4186)),  // BMO Field
        // Western Conference
        .init(keyword: "coloradorapids", coord: .init(latitude: 39.8060,  longitude: -104.8921)), // Dick's Sporting Goods Park
        .init(keyword: "fcdallas",       coord: .init(latitude: 33.1546,  longitude: -96.8359)),  // Toyota Stadium
        .init(keyword: "houstondynamo",  coord: .init(latitude: 29.7522,  longitude: -95.3516)),  // Shell Energy Stadium
        .init(keyword: "lagalaxy",       coord: .init(latitude: 33.8643,  longitude: -118.2610)), // Dignity Health Sports Park
        .init(keyword: "lafc",           coord: .init(latitude: 34.0122,  longitude: -118.2843)), // BMO Stadium
        .init(keyword: "losangelesfc",   coord: .init(latitude: 34.0122,  longitude: -118.2843)),
        .init(keyword: "minnesotaunited",coord: .init(latitude: 44.9537,  longitude: -93.1646)),  // Allianz Field
        .init(keyword: "portlandtimbers",coord: .init(latitude: 45.5213,  longitude: -122.6919)), // Providence Park
        .init(keyword: "timbers",        coord: .init(latitude: 45.5213,  longitude: -122.6919)),
        .init(keyword: "realsaltlake",   coord: .init(latitude: 40.5829,  longitude: -111.8929)), // America First Field
        .init(keyword: "sanjoseearthquakes", coord: .init(latitude: 37.3518, longitude: -121.9271)), // PayPal Park
        .init(keyword: "earthquakes",    coord: .init(latitude: 37.3518,  longitude: -121.9271)),
        .init(keyword: "seattlesounders",coord: .init(latitude: 47.5952,  longitude: -122.3316)), // Lumen Field
        .init(keyword: "sounders",       coord: .init(latitude: 47.5952,  longitude: -122.3316)),
        .init(keyword: "sportingkc",     coord: .init(latitude: 39.1225,  longitude: -94.8234)),  // Children's Mercy Park
        .init(keyword: "sportingkansascity", coord: .init(latitude: 39.1225, longitude: -94.8234)),
        .init(keyword: "stlouiscity",    coord: .init(latitude: 38.6337,  longitude: -90.2088)),  // CityPark
        .init(keyword: "stlouis",        coord: .init(latitude: 38.6337,  longitude: -90.2088)),
        .init(keyword: "vancouverwhitecaps", coord: .init(latitude: 49.2767, longitude: -123.1121)), // BC Place
        .init(keyword: "whitecaps",      coord: .init(latitude: 49.2767,  longitude: -123.1121)),
        .init(keyword: "austinfc",       coord: .init(latitude: 30.3869,  longitude: -97.7193)),  // Q2 Stadium
        .init(keyword: "sandiegofc",     coord: .init(latitude: 32.7831,  longitude: -117.1189)), // Snapdragon Stadium
    ]

    // Eredivisie (18팀)
    private static func erediviseLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: eredivisieRules)
    }

    private static let eredivisieRules: [StadiumRule] = [
        .init(keyword: "ajax",          coord: .init(latitude: 52.3143, longitude:  4.9412)), // Johan Cruyff Arena
        .init(keyword: "psv",           coord: .init(latitude: 51.4416, longitude:  5.4675)), // Philips Stadion
        .init(keyword: "feyenoord",     coord: .init(latitude: 51.8936, longitude:  4.5237)), // De Kuip
        .init(keyword: "az",            coord: .init(latitude: 52.6065, longitude:  4.7521)), // AFAS Stadion
        .init(keyword: "fcutrecht",     coord: .init(latitude: 52.0790, longitude:  5.1499)), // Stadion Galgenwaard
        .init(keyword: "fctwente",      coord: .init(latitude: 52.2336, longitude:  6.8762)), // De Grolsch Veste
        .init(keyword: "twente",        coord: .init(latitude: 52.2336, longitude:  6.8762)),
        .init(keyword: "necnijmegen",   coord: .init(latitude: 51.8175, longitude:  5.8545)), // Goffertstadion
        .init(keyword: "nijmegen",      coord: .init(latitude: 51.8175, longitude:  5.8545)),
        .init(keyword: "spartarotterdam", coord: .init(latitude: 51.9148, longitude: 4.4621)), // Sparta Stadion Het Kasteel
        .init(keyword: "heerenveen",    coord: .init(latitude: 52.9954, longitude:  5.9189)), // Abe Lenstra Stadion
        .init(keyword: "almerecity",    coord: .init(latitude: 52.3660, longitude:  5.2112)), // Yanmar Stadion
        .init(keyword: "goaheadeagles", coord: .init(latitude: 52.2604, longitude:  6.1522)), // De Adelaarshorst
        .init(keyword: "fortunasittard",coord: .init(latitude: 51.0022, longitude:  5.8708)), // Fortuna Sittard Stadion
        .init(keyword: "peczwolle",     coord: .init(latitude: 52.4932, longitude:  6.0836)), // MAC³PARK stadion
        .init(keyword: "zwolle",        coord: .init(latitude: 52.4932, longitude:  6.0836)),
        .init(keyword: "rkcwaalwijk",   coord: .init(latitude: 51.6878, longitude:  5.0734)), // Mandemakers Stadion
        .init(keyword: "heraclesalmelo",coord: .init(latitude: 52.3498, longitude:  6.6565)), // Polman Stadion
        .init(keyword: "heracles",      coord: .init(latitude: 52.3498, longitude:  6.6565)),
        .init(keyword: "willemii",      coord: .init(latitude: 51.5617, longitude:  5.0714)), // Koning Willem II Stadion
        .init(keyword: "nacbreda",      coord: .init(latitude: 51.5863, longitude:  4.7677)), // Rat Verlegh Stadion
    ]

    // Primeira Liga (18팀)
    private static func primeiraLigaLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: primeiraLigaRules)
    }

    private static let primeiraLigaRules: [StadiumRule] = [
        .init(keyword: "slbenfica",    coord: .init(latitude: 38.7526, longitude: -9.1846)), // Estádio da Luz
        .init(keyword: "benfica",      coord: .init(latitude: 38.7526, longitude: -9.1846)),
        .init(keyword: "fcporto",      coord: .init(latitude: 41.1610, longitude: -8.5839)), // Estádio do Dragão
        .init(keyword: "porto",        coord: .init(latitude: 41.1610, longitude: -8.5839)),
        .init(keyword: "sportingcp",   coord: .init(latitude: 38.7612, longitude: -9.1606)), // Estádio José Alvalade
        .init(keyword: "sporting",     coord: .init(latitude: 38.7612, longitude: -9.1606)),
        .init(keyword: "scbraga",      coord: .init(latitude: 41.5671, longitude: -8.4323)), // Estádio Municipal de Braga
        .init(keyword: "braga",        coord: .init(latitude: 41.5671, longitude: -8.4323)),
        .init(keyword: "vitoriaguimaraes", coord: .init(latitude: 41.4434, longitude: -8.2951)),
        .init(keyword: "vitoriase",    coord: .init(latitude: 38.5173, longitude: -8.8937)), // Estádio de Setúbal
        .init(keyword: "boavista",     coord: .init(latitude: 41.1593, longitude: -8.6462)), // Estádio do Bessa
        .init(keyword: "moreirense",   coord: .init(latitude: 41.4303, longitude: -8.3560)),
        .init(keyword: "estoril",      coord: .init(latitude: 38.7063, longitude: -9.4000)),
        .init(keyword: "famalicao",    coord: .init(latitude: 41.4059, longitude: -8.5113)),
        .init(keyword: "casapia",      coord: .init(latitude: 38.7178, longitude: -9.1822)),
        .init(keyword: "rioave",       coord: .init(latitude: 41.3369, longitude: -8.7338)),
        .init(keyword: "santaclara",   coord: .init(latitude: 37.7303, longitude: -25.6605)),
        .init(keyword: "arouca",       coord: .init(latitude: 40.9339, longitude: -8.2464)),
        .init(keyword: "farense",      coord: .init(latitude: 37.0163, longitude: -7.9352)),
        .init(keyword: "gilvicentefc", coord: .init(latitude: 41.5377, longitude: -8.6137)),
        .init(keyword: "nacional",     coord: .init(latitude: 32.6540,  longitude: -16.9135)), // Estádio da Madeira
    ]

    // Süper Lig (주요 팀)
    private static func superLigLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: superLigRules)
    }

    private static let superLigRules: [StadiumRule] = [
        .init(keyword: "galatasaray",   coord: .init(latitude: 41.0763, longitude: 28.7920)), // Rams Park (RAMS Park)
        .init(keyword: "fenerbahce",    coord: .init(latitude: 40.9792, longitude: 29.0390)), // Şükrü Saracoğlu Stadium
        .init(keyword: "besiktas",      coord: .init(latitude: 41.0392, longitude: 29.0100)), // Tüpraş Stadium (Vodafone Park)
        .init(keyword: "trabzonspor",   coord: .init(latitude: 41.0028, longitude: 39.7253)), // Papara Park
        .init(keyword: "basaksehir",    coord: .init(latitude: 41.0955, longitude: 28.8015)), // Başakşehir Fatih Terim Stadyumu
        .init(keyword: "sivasspor",     coord: .init(latitude: 39.7476, longitude: 37.0196)),
        .init(keyword: "antalyaspor",   coord: .init(latitude: 36.8662, longitude: 30.7049)),
        .init(keyword: "konyaspor",     coord: .init(latitude: 37.8558, longitude: 32.4935)),
        .init(keyword: "adanademirspor",coord: .init(latitude: 37.0177, longitude: 35.3467)),
        .init(keyword: "kayserispor",   coord: .init(latitude: 38.7178, longitude: 35.4858)),
        .init(keyword: "gaziantep",     coord: .init(latitude: 37.0662, longitude: 37.3832)),
        .init(keyword: "kasimpasa",     coord: .init(latitude: 41.0604, longitude: 28.9537)),
        .init(keyword: "alanyaspor",    coord: .init(latitude: 36.5505, longitude: 32.0086)),
        .init(keyword: "goztepe",       coord: .init(latitude: 38.3959, longitude: 27.0986)),
        .init(keyword: "hatayspor",     coord: .init(latitude: 36.2021, longitude: 36.1603)),
        .init(keyword: "rizespor",      coord: .init(latitude: 41.0215, longitude: 40.5109)),
        .init(keyword: "samsunspor",    coord: .init(latitude: 41.3009, longitude: 36.3369)),
        .init(keyword: "eyupspor",      coord: .init(latitude: 41.0534, longitude: 28.9274)),
    ]

    // Belgian Pro League (주요 팀)
    private static func belgianProLeagueLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: belgianProLeagueRules)
    }

    private static let belgianProLeagueRules: [StadiumRule] = [
        .init(keyword: "clubbrugge",    coord: .init(latitude: 51.1897, longitude:  3.1998)), // Jan Breydel Stadion
        .init(keyword: "rsca",          coord: .init(latitude: 50.8350, longitude:  4.2968)), // Lotto Park
        .init(keyword: "anderlecht",    coord: .init(latitude: 50.8350, longitude:  4.2968)),
        .init(keyword: "kaagehnt",      coord: .init(latitude: 51.0437, longitude:  3.7270)), // Ghelamco Arena
        .init(keyword: "gent",          coord: .init(latitude: 51.0437, longitude:  3.7270)),
        .init(keyword: "standardliege", coord: .init(latitude: 50.5997, longitude:  5.5195)), // Stade de Sclessin
        .init(keyword: "standard",      coord: .init(latitude: 50.5997, longitude:  5.5195)),
        .init(keyword: "genk",          coord: .init(latitude: 51.0213, longitude:  5.4993)), // Cegeka Arena
        .init(keyword: "royalantwerp",  coord: .init(latitude: 51.2242, longitude:  4.4504)), // Bosuil
        .init(keyword: "antwerp",       coord: .init(latitude: 51.2242, longitude:  4.4504)),
        .init(keyword: "kfcwesterlo",   coord: .init(latitude: 51.1054, longitude:  4.9131)),
        .init(keyword: "kvmechelen",    coord: .init(latitude: 51.0284, longitude:  4.4791)),
        .init(keyword: "mechelen",      coord: .init(latitude: 51.0284, longitude:  4.4791)),
        .init(keyword: "sinttruidensevc", coord: .init(latitude: 50.8241, longitude:  5.1861)),
        .init(keyword: "kortrijk",      coord: .init(latitude: 50.8340, longitude:  3.2705)),
        .init(keyword: "charleroi",     coord: .init(latitude: 50.3965, longitude:  4.4472)),
        .init(keyword: "beerschot",     coord: .init(latitude: 51.1907, longitude:  4.4175)),
        .init(keyword: "cerclbrugge",   coord: .init(latitude: 51.1897, longitude:  3.1998)), // Jan Breydel (shared)
    ]

    // Super League Greece (주요 팀)
    private static func greekSuperLeagueLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: greekSuperLeagueRules)
    }

    private static let greekSuperLeagueRules: [StadiumRule] = [
        .init(keyword: "olympiacos",    coord: .init(latitude: 37.9434, longitude: 23.6667)), // Georgios Karaiskakis
        .init(keyword: "panathinaikos", coord: .init(latitude: 38.0001, longitude: 23.7745)), // OPAP Arena
        .init(keyword: "aekathens",     coord: .init(latitude: 38.0001, longitude: 23.7745)), // OPAP Arena
        .init(keyword: "paok",          coord: .init(latitude: 40.6118, longitude: 22.9704)), // Toumba Stadium
        .init(keyword: "aris",          coord: .init(latitude: 40.6275, longitude: 22.9506)), // Kleanthis Vikelidis
        .init(keyword: "atromitos",     coord: .init(latitude: 38.0159, longitude: 23.6898)),
        .init(keyword: "panserraikos",  coord: .init(latitude: 41.0706, longitude: 23.5530)),
        .init(keyword: "volos",         coord: .init(latitude: 39.3636, longitude: 22.9413)),
        .init(keyword: "panetolikos",   coord: .init(latitude: 38.6267, longitude: 21.4028)),
        .init(keyword: "ofi",           coord: .init(latitude: 35.3406, longitude: 25.1346)),
        .init(keyword: "ael",           coord: .init(latitude: 39.6318, longitude: 20.8503)),
        .init(keyword: "levadiakos",    coord: .init(latitude: 38.4416, longitude: 22.8769)),
    ]

    // Czech First League (주요 팀)
    private static func czechFirstLeagueLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: czechFirstLeagueRules)
    }

    private static let czechFirstLeagueRules: [StadiumRule] = [
        .init(keyword: "spartapraha",   coord: .init(latitude: 50.1005, longitude: 14.4009)), // Generali Arena
        .init(keyword: "sparta",        coord: .init(latitude: 50.1005, longitude: 14.4009)),
        .init(keyword: "slaviapraha",   coord: .init(latitude: 50.0665, longitude: 14.4757)), // Sinobo Stadium
        .init(keyword: "slavia",        coord: .init(latitude: 50.0665, longitude: 14.4757)),
        .init(keyword: "viktoriaPlzen", coord: .init(latitude: 49.7477, longitude: 13.3878)), // Doosan Arena
        .init(keyword: "plzen",         coord: .init(latitude: 49.7477, longitude: 13.3878)),
        .init(keyword: "fcbanikostrava",coord: .init(latitude: 49.8283, longitude: 18.2529)),
        .init(keyword: "sigmaolouc",    coord: .init(latitude: 49.5836, longitude: 17.2507)),
        .init(keyword: "mlada",         coord: .init(latitude: 50.4136, longitude: 14.9008)),
        .init(keyword: "liberec",       coord: .init(latitude: 50.7632, longitude: 15.0423)),
        .init(keyword: "olomouc",       coord: .init(latitude: 49.5836, longitude: 17.2507)),
        .init(keyword: "jablonec",      coord: .init(latitude: 50.7253, longitude: 15.1694)),
        .init(keyword: "ceske",         coord: .init(latitude: 48.9759, longitude: 14.4748)),
        .init(keyword: "slovacko",      coord: .init(latitude: 49.0010, longitude: 17.4520)),
        .init(keyword: "teplice",       coord: .init(latitude: 50.6449, longitude: 13.8320)),
        .init(keyword: "karvinafc",     coord: .init(latitude: 49.8552, longitude: 18.5440)),
    ]

    // Danish Superliga (주요 팀)
    private static func danishSuperligaLookup(_ norm: String) -> CLLocationCoordinate2D? {
        firstMatch(norm, in: danishSuperligaRules)
    }

    private static let danishSuperligaRules: [StadiumRule] = [
        .init(keyword: "fccopenhagen",  coord: .init(latitude: 55.7027, longitude: 12.5689)), // Parken Stadium
        .init(keyword: "copenhagen",    coord: .init(latitude: 55.7027, longitude: 12.5689)),
        .init(keyword: "fcmidtjylland", coord: .init(latitude: 56.1328, longitude:  8.9994)), // MCH Arena
        .init(keyword: "midtjylland",   coord: .init(latitude: 56.1328, longitude:  8.9994)),
        .init(keyword: "brondby",       coord: .init(latitude: 55.6442, longitude: 12.4333)), // Brøndby Stadium
        .init(keyword: "aabsportsklub", coord: .init(latitude: 57.0188, longitude:  9.9143)), // Aalborg Portland Park
        .init(keyword: "aalborg",       coord: .init(latitude: 57.0188, longitude:  9.9143)),
        .init(keyword: "aarhus",        coord: .init(latitude: 56.1167, longitude: 10.1805)), // Ceres Park
        .init(keyword: "agf",           coord: .init(latitude: 56.1167, longitude: 10.1805)),
        .init(keyword: "odense",        coord: .init(latitude: 55.3778, longitude: 10.3820)), // Nature Energy Park
        .init(keyword: "obfk",          coord: .init(latitude: 55.3778, longitude: 10.3820)),
        .init(keyword: "vejle",         coord: .init(latitude: 55.7119, longitude:  9.5352)),
        .init(keyword: "sonderjyske",   coord: .init(latitude: 55.0572, longitude:  9.3993)),
        .init(keyword: "randers",       coord: .init(latitude: 56.4639, longitude: 10.0497)),
        .init(keyword: "silkeborg",     coord: .init(latitude: 56.1820, longitude:  9.5433)),
        .init(keyword: "nordsjaelland", coord: .init(latitude: 55.8754, longitude: 12.3464)),
        .init(keyword: "viborg",        coord: .init(latitude: 56.4510, longitude:  9.3890)),
    ]
}
