//
//  SportsPreviewSampleData.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import SwiftData

@MainActor
class SportsPreviewSampleData {
    
    static let container: ModelContainer = {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: SportsFanFolder.self, SportsModel.self,
                F1RaceModel.self, GolfRoundModel.self,
                CultureFanFolder.self, CultureModel.self,
                configurations: config
            )
            
            // 폴더 생성
            let lgFolder = SportsFanFolder(name: "LG 트윈스", sportType: .baseball, orderIndex: 0)
            let fcSeoulFolder = SportsFanFolder(name: "FC서울", sportType: .soccer, orderIndex: 1)
            let skFolder = SportsFanFolder(name: "서울 SK", sportType: .basketball, orderIndex: 2)
            
            container.mainContext.insert(lgFolder)
            container.mainContext.insert(fcSeoulFolder)
            container.mainContext.insert(skFolder)
            
            // LG 트윈스 — 예정 경기
            let lgUpcoming = SportsModel(
                title: "LG vs SSG",
                opponentTeam: "SSG 랜더스",
                matchStatus: .upcoming,
                date: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
                location: "잠실 야구장",
                orderIndex: 0
            )
            lgUpcoming.folder = lgFolder
            
            // LG 트윈스 — 완료 경기 1 (승리)
            let lgWin = SportsModel(
                title: "LG vs 두산 잠실 직관",
                opponentTeam: "두산 베어스",
                myTeamScore: 5,
                opponentScore: 2,
                matchResult: .win,
                matchStatus: .completed,
                isHomeGame: true,
                date: Date(),
                location: "잠실 야구장",
                memo: "오지환 끝내기 홈런!",
                orderIndex: 1
            )
            lgWin.folder = lgFolder
            
            // LG 트윈스 — 완료 경기 2 (패배)
            let lgLoss = SportsModel(
                title: "LG vs KIA 원정",
                opponentTeam: "KIA 타이거즈",
                myTeamScore: 3,
                opponentScore: 4,
                matchResult: .loss,
                matchStatus: .completed,
                isHomeGame: false,
                date: Calendar.current.date(byAdding: .day, value: -5, to: Date()),
                location: "광주 기아 챔피언스 필드",
                orderIndex: 2
            )
            lgLoss.folder = lgFolder
            
            // FC서울 — 완료 (무승부)
            let fcDraw = SportsModel(
                title: "FC서울 홈경기",
                opponentTeam: "수원 삼성",
                myTeamScore: 1,
                opponentScore: 1,
                matchResult: .draw,
                matchStatus: .completed,
                isHomeGame: true,
                date: Calendar.current.date(byAdding: .day, value: -3, to: Date()),
                location: "상암 월드컵 경기장",
                orderIndex: 0
            )
            fcDraw.folder = fcSeoulFolder
            
            // 서울 SK — 완료 (패배)
            let skLoss = SportsModel(
                title: "원정 농구",
                opponentTeam: "부산 KT",
                myTeamScore: 78,
                opponentScore: 92,
                matchResult: .loss,
                matchStatus: .completed,
                isHomeGame: false,
                date: Calendar.current.date(byAdding: .day, value: -7, to: Date()),
                location: "부산 사직실내체육관",
                memo: "아쉬운 경기... 4쿼터 역전당함",
                orderIndex: 0
            )
            skLoss.folder = skFolder
            
            container.mainContext.insert(lgUpcoming)
            container.mainContext.insert(lgWin)
            container.mainContext.insert(lgLoss)
            container.mainContext.insert(fcDraw)
            container.mainContext.insert(skLoss)
            
            // ── 문화 샘플 데이터 ──
            
            // 폴더 생성
            let btsFolder = CultureFanFolder(name: "BTS", cultureType: .concert, orderIndex: 0)
            let musicalFolder = CultureFanFolder(name: "뮤지컬 모음", cultureType: .musical, orderIndex: 1)
            
            container.mainContext.insert(btsFolder)
            container.mainContext.insert(musicalFolder)
            
            // BTS — 예정 이벤트
            let btsUpcoming = CultureModel(
                title: "BTS 월드투어 서울",
                artist: "BTS",
                date: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
                location: "잠실 올림픽 주경기장",
                seatInfo: "VIP A구역 3열",
                eventStatus: .upcoming,
                orderIndex: 0
            )
            btsUpcoming.folder = btsFolder
            
            // BTS — 완료 1 (별점 5)
            let btsConcert1 = CultureModel(
                title: "BTS 팬미팅 2025",
                artist: "BTS",
                date: Calendar.current.date(byAdding: .day, value: -30, to: Date()),
                location: "고척 스카이돔",
                seatInfo: "스탠딩 A구역",
                rating: 5,
                eventStatus: .completed,
                memo: "소름 돋는 무대! 앵콜곡 Spring Day 최고였다",
                orderIndex: 1
            )
            btsConcert1.folder = btsFolder
            
            // BTS — 완료 2 (별점 4)
            let btsConcert2 = CultureModel(
                title: "BTS Yet To Come in 부산",
                artist: "BTS",
                date: Calendar.current.date(byAdding: .day, value: -90, to: Date()),
                location: "부산 아시아드 주경기장",
                rating: 4,
                eventStatus: .completed,
                memo: "야외 공연이라 비가 좀 왔지만 역대급 셋리스트!",
                orderIndex: 2
            )
            btsConcert2.folder = btsFolder
            
            // 뮤지컬 — 완료 (별점 5)
            let wicked = CultureModel(
                title: "위키드 내한",
                artist: "옥주현, 정선아",
                date: Calendar.current.date(byAdding: .day, value: -15, to: Date()),
                location: "블루스퀘어",
                seatInfo: "1층 R석 12열 5번",
                rating: 5,
                eventStatus: .completed,
                memo: "Defying Gravity에서 소름... 옥주현 미쳤다",
                orderIndex: 0
            )
            wicked.folder = musicalFolder
            
            // 뮤지컬 — 완료 (별점 3)
            let phantom = CultureModel(
                title: "오페라의 유령",
                artist: "캐스팅 미정",
                date: Calendar.current.date(byAdding: .day, value: -60, to: Date()),
                location: "샤롯데 씨어터",
                seatInfo: "2층 A석",
                rating: 3,
                eventStatus: .completed,
                memo: "클래식한 작품, 좌석이 좀 아쉬웠다",
                orderIndex: 1
            )
            phantom.folder = musicalFolder
            
            container.mainContext.insert(btsUpcoming)
            container.mainContext.insert(btsConcert1)
            container.mainContext.insert(btsConcert2)
            container.mainContext.insert(wicked)
            container.mainContext.insert(phantom)
            
            return container
            
        } catch {
            fatalError("프리뷰 컨테이너 생성 실패: \(error)")
        }
    }()
}
