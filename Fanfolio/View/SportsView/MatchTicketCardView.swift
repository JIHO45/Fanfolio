//
//  MatchTicketCardView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/24/26.
//

import SwiftUI
import UIKit

// MARK: - 티켓 디자인 스타일

enum TicketDesignStyle: CaseIterable {
    case standard     // 수평 텍스트 상단 중앙
    case rotatedText  // 90도 회전, 카드 왼쪽 배치
    case customText   // 사용자 입력 텍스트 (Sports + Culture 공용)

    var label: LocalizedStringKey {
        switch self {
        case .standard:    return "기본"
        case .rotatedText: return "세로"
        case .customText:  return "내 글"
        }
    }
}

// MARK: - 공용 커스텀 텍스트 오버레이
// Sports와 Culture 티켓 카드에서 공통으로 사용하는 오버레이 레이어

struct TicketCustomTextOverlay: View {
    let text: String
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("FANFOLIO")
                    .font(.system(size: 10, weight: .black))
                    .tracking(4.5)
                    .foregroundStyle(.white.opacity(0.50))
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Text(text)
                .font(.system(size: 54, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: cardWidth - 40, alignment: .center)
                .padding(.top, cardHeight * 0.11)

            Spacer()
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .top)
    }
}

// MARK: - 매치 티켓 데이터 모델

struct MatchTicketModel {
    var teamName: String
    var opponentTeam: String
    var myTeamScore: Int
    var opponentScore: Int
    var matchResult: MatchResult
    var matchStatus: MatchStatus
    var sportType: SportType
    var teamColor: Color
    var teamLogoImage: UIImage?
    var opponentLogoImage: UIImage?
    var userPhoto: UIImage? = nil
    /// Vision으로 추출한 누끼 이미지 (사람이 없으면 nil)
    var userPhotoCutout: UIImage? = nil
    /// 드래그 패닝 오프셋 (디자인 좌표 기준)
    var photoOffset: CGSize = .zero
    /// 핀치 줌 스케일 (1.0 = 기본)
    var photoScale: CGFloat = 1.0
    var date: Date?
    var leagueCode: String?
    var designStyle: TicketDesignStyle = .standard
    var customOverlayText: String? = nil
}

// MARK: - 모델 헬퍼

private extension MatchTicketModel {
    var resultHeadline: String {
        switch matchStatus {
        case .completed:
            switch matchResult {
            case .win:  return "WIN"
            case .loss: return "DEFEAT"
            case .draw: return "DRAW"
            }
        case .live:     return "LIVE"
        case .upcoming: return "MATCHDAY"
        }
    }

    var resultColor: Color {
        switch matchStatus {
        case .completed:
            switch matchResult {
            case .win:  return Color(red: 0.20, green: 0.90, blue: 0.45)
            case .loss: return Color(red: 1.00, green: 0.28, blue: 0.28)
            case .draw: return Color(red: 1.00, green: 0.65, blue: 0.10)
            }
        case .live:     return Color(red: 1.00, green: 0.28, blue: 0.28)
        case .upcoming: return .white
        }
    }
}

// MARK: - 날짜 포맷터

private extension DateFormatter {
    static let ticketDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return f
    }()

    static let ticketTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.timeStyle = .short
        return f
    }()
}

// MARK: - 매치 티켓 카드 뷰 (9:16 세로형)
//
//  구조:
//  ┌────────────────────────────┐
//  │           FANFOLIO  [우상단]│
//  │                            │
//  │          WIN / DEFEAT      │  ← 상단 중앙, 크게
//  │                            │
//  │                            │
//  │  ┌──────────────────────┐  │
//  │  │ 🔴 VS 🔵 │ 3 - 1  WIN│  │  ← 하단 바
//  │  └──────────────────────┘  │
//  └────────────────────────────┘

struct MatchTicketCardView: View {
    let model: MatchTicketModel

    /// 디자인 좌표 (pt). @3x 렌더링 시 1080×1920 px
    static let designWidth: CGFloat  = 360
    static let designHeight: CGFloat = 640

    private let W = MatchTicketCardView.designWidth
    private let H = MatchTicketCardView.designHeight

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. 배경 (팀 컬러 or 원본 사진)
            backgroundLayer
            // 2. 오버레이 텍스트 (WIN / DEFEAT 등)
            overlayLayer
            // 3. 누끼 이미지 — 텍스트 위에 올라와 뚫고 나오는 효과
            photoCutoutLayer
            // 4. 하단 그라디언트 + 스코어 바
            bottomGradient
            footerBar
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
        }
        .frame(width: W, height: H)
        .clipped()
        .drawingGroup()
    }

    // MARK: - 배경

    @ViewBuilder
    private var backgroundLayer: some View {
        if let photo = model.userPhoto {
            let fillScale = max(W / max(1, photo.size.width),
                                H / max(1, photo.size.height)) * model.photoScale
            let drawW = photo.size.width * fillScale
            let drawH = photo.size.height * fillScale
            Image(uiImage: photo)
                .resizable()
                .interpolation(.high)
                .frame(width: drawW, height: drawH)
                .offset(model.photoOffset)
                .frame(width: W, height: H, alignment: .center)
                .clipped()
        } else {
            ZStack {
                Rectangle().fill(model.teamColor)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.52)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: W, height: H)
        }
    }

    // MARK: - 누끼 레이어 (원본 사진과 동일한 좌표로 렌더링)

    @ViewBuilder
    private var photoCutoutLayer: some View {
        if let cutout = model.userPhotoCutout,
           let photo = model.userPhoto {
            let fillScale = max(W / max(1, photo.size.width),
                                H / max(1, photo.size.height)) * model.photoScale
            let drawW = photo.size.width * fillScale
            let drawH = photo.size.height * fillScale
            Image(uiImage: cutout)
                .resizable()
                .interpolation(.high)
                .frame(width: drawW, height: drawH)
                .offset(model.photoOffset)
                .frame(width: W, height: H, alignment: .center)
                .clipped()
        }
    }

    // MARK: - 오버레이 (디자인 스타일별 분기)

    @ViewBuilder
    private var overlayLayer: some View {
        switch model.designStyle {
        case .standard:
            standardOverlay
        case .rotatedText:
            rotatedTextOverlay
        case .customText:
            TicketCustomTextOverlay(
                text: model.customOverlayText ?? String(localized: "ticket.overlay.placeholder", defaultValue: "여기에 글을 입력하세요"),
                cardWidth: W,
                cardHeight: H
            )
        }
    }

    // 기본: 수평 결과 텍스트 + 워터마크
    private var standardOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("FANFOLIO")
                    .font(.system(size: 10, weight: .black))
                    .tracking(4.5)
                    .foregroundStyle(.white.opacity(0.50))
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Text(model.resultHeadline)
                .font(.system(size: 58, weight: .black))
                .foregroundStyle(model.resultColor)
                .shadow(color: model.resultColor.opacity(0.45), radius: 28, y: 10)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, H * 0.13)

            Spacer()
        }
        .frame(width: W, height: H, alignment: .top)
    }

    // 세로: 결과 텍스트를 90도 회전하여 왼쪽에 배치
    private var rotatedTextOverlay: some View {
        ZStack {
            // 워터마크
            VStack {
                HStack {
                    Spacer()
                    Text("FANFOLIO")
                        .font(.system(size: 10, weight: .black))
                        .tracking(4.5)
                        .foregroundStyle(.white.opacity(0.50))
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                Spacer()
            }

            // 90도 회전 텍스트 — 왼쪽 세로 배치 (카드 중앙 높이 기준)
            Text(model.resultHeadline)
                .font(.system(size: 76, weight: .black))
                .foregroundStyle(model.resultColor)
                .shadow(color: model.resultColor.opacity(0.45), radius: 28, y: 10)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                // 회전 후: 텍스트의 중심을 카드 왼쪽 가장자리 + 텍스트 높이/2 위치에 배치
                .position(x: 42, y: H * 0.42)
        }
        .frame(width: W, height: H)
    }

    // MARK: - 하단 그라디언트

    private var bottomGradient: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.55), location: 0.40),
                    .init(color: .black.opacity(0.90), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: H * 0.40)
        }
        .frame(width: W, height: H)
    }

    // MARK: - 스코어 뷰

    @ViewBuilder
    private var scoreView: some View {
        if model.matchStatus == .completed {
            HStack(spacing: 6) {
                Text("\(model.myTeamScore)")
                Text("-").foregroundStyle(Color.black.opacity(0.4))
                Text("\(model.opponentScore)")
            }
            .font(.system(size: 28, weight: .black))
            .foregroundStyle(Color.black)
            .monospacedDigit()
        } else {
            HStack(spacing: 6) {
                if model.matchStatus == .live {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                }
                Text(model.matchStatus == .live ? "LIVE" : "UPCOMING")
            }
            .font(.system(size: 16, weight: .black))
            .foregroundStyle(Color.black)
        }
    }

    // MARK: - 하단 바

    private var footerBar: some View {
        return HStack(spacing: 12) {
            HStack(spacing: 6) {
                footerLogo(image: model.teamLogoImage)
                Text("VS")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.45))
                footerLogo(image: model.opponentLogoImage)
            }
            .frame(width: 72, alignment: .leading)

            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(width: 1, height: 30)

            scoreView

            Spacer(minLength: 10)

            footerMetaInfo
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.22), radius: 16, y: 8)
    }

    @ViewBuilder
    private var footerMetaInfo: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(model.resultHeadline)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(Color.black.opacity(0.72))
                .tracking(1.2)
            if let date = model.date {
                let cal = Calendar.current
                let hasTime = cal.component(.hour, from: date) != 0 || cal.component(.minute, from: date) != 0
                if model.matchStatus == .upcoming && hasTime {
                    HStack(spacing: 3) {
                        Text(DateFormatter.ticketDate.string(from: date))
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.48))
                        Text(DateFormatter.ticketTime.string(from: date))
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color(red: 0.12, green: 0.35, blue: 0.85))
                    }
                    .lineLimit(1)
                } else {
                    Text(DateFormatter.ticketDate.string(from: date))
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.48))
                        .lineLimit(1)
                }
            } else if let league = model.leagueCode {
                Text(league)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.48))
                    .tracking(0.8)
            }
        }
    }

    private func footerLogo(image: UIImage?) -> some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Circle()
                    .fill(model.teamColor.opacity(0.18))
                    .overlay(
                        Image(systemName: model.sportType.iconName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(model.teamColor)
                    )
            }
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Preview

#Preview("WIN - 미식축구") {
    MatchTicketCardView(model: MatchTicketModel(
        teamName: "San Francisco 49ers",
        opponentTeam: "Kansas City Chiefs",
        myTeamScore: 31,
        opponentScore: 20,
        matchResult: .win,
        matchStatus: .completed,
        sportType: .americanFootball,
        teamColor: Color(red: 0.67, green: 0.13, blue: 0.17),
        teamLogoImage: nil,
        opponentLogoImage: nil,
        date: Date(),
        leagueCode: "NFL"
    ))
    .padding()
    .background(Color(red: 0.08, green: 0.08, blue: 0.10))
}

#Preview("DEFEAT - 농구") {
    MatchTicketCardView(model: MatchTicketModel(
        teamName: "Detroit Pistons",
        opponentTeam: "LA Lakers",
        myTeamScore: 87,
        opponentScore: 102,
        matchResult: .loss,
        matchStatus: .completed,
        sportType: .basketball,
        teamColor: Color(red: 0.0, green: 0.36, blue: 0.70),
        teamLogoImage: nil,
        opponentLogoImage: nil,
        date: Date(),
        leagueCode: "NBA"
    ))
    .padding()
    .background(Color(red: 0.08, green: 0.08, blue: 0.10))
}

#Preview("MATCHDAY - 야구") {
    MatchTicketCardView(model: MatchTicketModel(
        teamName: "LG 트윈스",
        opponentTeam: "두산 베어스",
        myTeamScore: 0,
        opponentScore: 0,
        matchResult: .draw,
        matchStatus: .upcoming,
        sportType: .baseball,
        teamColor: Color(red: 0.80, green: 0.08, blue: 0.12),
        teamLogoImage: nil,
        opponentLogoImage: nil,
        date: Date(),
        leagueCode: "KBO"
    ))
    .padding()
    .background(Color(red: 0.08, green: 0.08, blue: 0.10))
}

#Preview("LIVE - 축구") {
    MatchTicketCardView(model: MatchTicketModel(
        teamName: "Arsenal FC",
        opponentTeam: "Chelsea FC",
        myTeamScore: 2,
        opponentScore: 1,
        matchResult: .win,
        matchStatus: .live,
        sportType: .soccer,
        teamColor: Color(red: 0.80, green: 0.0, blue: 0.0),
        teamLogoImage: nil,
        opponentLogoImage: nil,
        date: Date(),
        leagueCode: "ENG.1"
    ))
    .padding()
    .background(Color(red: 0.08, green: 0.08, blue: 0.10))
}
