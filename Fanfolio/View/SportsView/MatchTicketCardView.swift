//
//  MatchTicketCardView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/24/26.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - 매치 티켓 데이터 모델

struct MatchTicketModel {
    var teamName: String
    /// 팀 닉네임 (워터마크 + 대형 타이포 용, e.g. "49ers", "트윈스")
    var teamNickname: String
    var opponentTeam: String
    var myTeamScore: Int
    var opponentScore: Int
    var matchResult: MatchResult
    var matchStatus: MatchStatus
    var sportType: SportType
    var isHomeGame: Bool
    var gameNumber: Int
    var teamColor: Color
    var teamLogoImage: UIImage?
    var opponentLogoImage: UIImage?
    /// 선수 누끼 이미지 (없으면 팀 로고 fallback)
    var playerCutoutImage: UIImage?
    var date: Date?
    var location: String?
    var style: ShareStyle
    /// 티켓 스텁용 좌석 정보
    var sec: String
    var row: String
    var seat: String
}

// MARK: - 노이즈 텍스처 뷰

/// CIRandomGenerator 필터로 흑백 그레인 노이즈를 생성해 표시.
/// static 프로퍼티로 한 번만 렌더링해 재사용 (ImageRenderer 호환).
struct NoiseTextureView: View {

    static let noiseImage: UIImage? = {
        guard let randomFilter = CIFilter(name: "CIRandomGenerator"),
              let rawNoise = randomFilter.outputImage else { return nil }

        // 흑백 변환 + 대비 강화
        guard let colorFilter = CIFilter(name: "CIColorControls") else { return nil }
        colorFilter.setValue(
            rawNoise.cropped(to: CGRect(origin: .zero, size: CGSize(width: 512, height: 256))),
            forKey: kCIInputImageKey
        )
        colorFilter.setValue(0.0, forKey: kCIInputSaturationKey)
        colorFilter.setValue(0.0, forKey: kCIInputBrightnessKey)
        colorFilter.setValue(1.8, forKey: kCIInputContrastKey)

        guard let processed = colorFilter.outputImage else { return nil }
        let cropRect = CGRect(origin: .zero, size: CGSize(width: 512, height: 256))
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = ctx.createCGImage(processed, from: cropRect) else { return nil }
        return UIImage(cgImage: cg)
    }()

    var body: some View {
        if let img = Self.noiseImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        }
    }
}

// MARK: - 수직 점선 절취선

private struct VerticalDashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

// MARK: - 매치 티켓 카드 뷰

struct MatchTicketCardView: View {
    let model: MatchTicketModel

    // MARK: - 왼쪽 메인 패널

    private var leftPanel: some View {
        ZStack(alignment: .bottomLeading) {

            // 1. 배경 그라디언트 (팀 컬러 → 검정)
            LinearGradient(
                colors: [
                    model.style == .light
                        ? model.teamColor
                        : model.teamColor.opacity(0.85),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 2. 노이즈 텍스처 (콘크리트/그레인 질감)
            NoiseTextureView()
                .opacity(model.style == .light ? 0.12 : 0.20)
                .blendMode(.multiply)
                .clipped()

            // 3. 팀 닉네임 워터마크 (거대, 비스듬)
            Text(model.teamNickname.uppercased())
                .font(.system(size: 104, weight: .black))
                .foregroundStyle(Color.white.opacity(0.07))
                .rotationEffect(.degrees(-10))
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            // 4. 선수 누끼 / 팀 로고 (우측, 하단 페이드 마스크)
            HStack(spacing: 0) {
                Spacer()
                Group {
                    if let playerImg = model.playerCutoutImage {
                        Image(uiImage: playerImg)
                            .resizable()
                            .scaledToFit()
                    } else if let logoImg = model.teamLogoImage {
                        Image(uiImage: logoImg)
                            .resizable()
                            .scaledToFit()
                            .padding(32)
                            .opacity(0.22)
                    }
                }
                .frame(height: 235)
                .mask(
                    LinearGradient(
                        colors: [.black, .black, .black.opacity(0.65), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.55), radius: 16, x: -6, y: 4)
            }

            // 5. 전경 타이포그래피 (좌하단)
            VStack(alignment: .leading, spacing: 4) {

                // GAME N 배지
                Text("GAME \(model.gameNumber)")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(model.teamColor)
                    .tracking(1.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                // 팀 닉네임 (대형 헤드라인)
                Text(model.teamNickname.uppercased())
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .shadow(color: .black.opacity(0.6), radius: 4)

                // 점수 또는 VS
                if model.matchStatus == .completed {
                    HStack(alignment: .center, spacing: 6) {
                        Text("\(model.myTeamScore)")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(Color.white)
                            .monospacedDigit()

                        Text("—")
                            .font(.system(size: 18, weight: .thin))
                            .foregroundStyle(Color.white.opacity(0.4))

                        Text("\(model.opponentScore)")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.52))
                            .monospacedDigit()

                        Text(model.matchResult.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(model.matchResult.color)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                } else {
                    HStack(spacing: 4) {
                        Text("VS")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Color.white.opacity(0.5))
                        Text(model.opponentTeam)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    // MARK: - 오른쪽 스텁

    private func stubRow(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.red)
                .tracking(1.5)
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }

    private var rightStub: some View {
        ZStack {
            Color.black

            VStack(spacing: 0) {
                // 스포츠 종목 아이콘
                Image(systemName: model.sportType.iconName)
                    .font(.system(size: 13))
                    .foregroundStyle(model.teamColor)
                    .padding(.top, 14)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                // 좌석 정보
                VStack(spacing: 10) {
                    stubRow(title: "SEC", value: model.sec)
                    stubRow(title: "ROW", value: model.row)
                    stubRow(title: "SEAT", value: model.seat)
                }

                Spacer()

                // 세로 바코드
                Image(systemName: "barcode")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .rotationEffect(.degrees(-90))
                    .padding(.bottom, 14)
            }
        }
        .frame(width: 76)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            leftPanel

            VerticalDashLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.white.opacity(0.3))
                .frame(width: 1)

            rightStub
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }
}

// MARK: - Preview

#Preview("완료 - 미식축구 (다크)") {
    MatchTicketCardView(model: MatchTicketModel(
        teamName: "San Francisco 49ers",
        teamNickname: "49ers",
        opponentTeam: "Kansas City Chiefs",
        myTeamScore: 31,
        opponentScore: 20,
        matchResult: .win,
        matchStatus: .completed,
        sportType: .americanFootball,
        isHomeGame: true,
        gameNumber: 1,
        teamColor: Color(red: 0.67, green: 0.13, blue: 0.17),
        teamLogoImage: nil,
        opponentLogoImage: nil,
        playerCutoutImage: nil,
        date: Date(),
        location: "Levi's Stadium",
        style: .dark,
        sec: "C7",
        row: "12",
        seat: "5"
    ))
    .padding()
    .background(Color(red: 0.08, green: 0.08, blue: 0.10))
}

#Preview("완료 - 농구 (라이트)") {
    MatchTicketCardView(model: MatchTicketModel(
        teamName: "Detroit Pistons",
        teamNickname: "Pistons",
        opponentTeam: "LA Lakers",
        myTeamScore: 87,
        opponentScore: 75,
        matchResult: .win,
        matchStatus: .completed,
        sportType: .basketball,
        isHomeGame: false,
        gameNumber: 1,
        teamColor: Color(red: 0.0, green: 0.36, blue: 0.70),
        teamLogoImage: nil,
        opponentLogoImage: nil,
        playerCutoutImage: nil,
        date: Date(),
        location: "Little Caesars Arena",
        style: .light,
        sec: "A3",
        row: "7",
        seat: "22"
    ))
    .padding()
    .background(Color(red: 0.08, green: 0.08, blue: 0.10))
}

#Preview("예정 - 야구") {
    MatchTicketCardView(model: MatchTicketModel(
        teamName: "LG 트윈스",
        teamNickname: "트윈스",
        opponentTeam: "두산 베어스",
        myTeamScore: 0,
        opponentScore: 0,
        matchResult: .draw,
        matchStatus: .upcoming,
        sportType: .baseball,
        isHomeGame: true,
        gameNumber: 3,
        teamColor: Color(red: 0.80, green: 0.08, blue: 0.12),
        teamLogoImage: nil,
        opponentLogoImage: nil,
        playerCutoutImage: nil,
        date: Date(),
        location: "잠실 야구장",
        style: .dark,
        sec: "3루",
        row: "E",
        seat: "17"
    ))
    .padding()
    .background(Color(red: 0.08, green: 0.08, blue: 0.10))
}
