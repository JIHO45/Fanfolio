//
//  CultureTicketCardView.swift
//  Fanfolio
//
//  Created by 박지호 on 3/15/26.
//

import SwiftUI
import UIKit

// MARK: - Culture 티켓 데이터 모델

struct CultureTicketModel {
    var title: String
    var artist: String?
    var cultureType: CultureType
    var rating: Int
    var eventStatus: EventStatus
    var seatInfo: String?
    var date: Date?
    var location: String?
    var bandColor: Color
    var userPhoto: UIImage? = nil
    /// Vision으로 추출한 누끼 이미지
    var userPhotoCutout: UIImage? = nil
    var photoOffset: CGSize = .zero
    var photoScale: CGFloat = 1.0
    /// 사용자 커스텀 오버레이 텍스트 (nil이면 오버레이 없음)
    var customOverlayText: String? = nil
}

// MARK: - 날짜 포맷터

private extension DateFormatter {
    static let cultureTicketDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return f
    }()
}

// MARK: - Culture 티켓 카드 뷰 (9:16 세로형)
//
//  구조:
//  ┌────────────────────────────┐
//  │           FANFOLIO  [우상단]│
//  │   (커스텀 텍스트 오버레이)   │
//  │                            │
//  │  ┌──────────────────────┐  │
//  │  │ 🎵 제목  ★★★★★  날짜  │  │  ← 하단 바
//  │  └──────────────────────┘  │
//  └────────────────────────────┘

struct CultureTicketCardView: View {
    let model: CultureTicketModel

    static let designWidth: CGFloat  = 360
    static let designHeight: CGFloat = 640

    private let W = CultureTicketCardView.designWidth
    private let H = CultureTicketCardView.designHeight

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundLayer
            if model.customOverlayText != nil {
                overlayLayer
            } else {
                watermmarkOnlyLayer
            }
            photoCutoutLayer
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
                Rectangle().fill(model.bandColor)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.52)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: W, height: H)
        }
    }

    // MARK: - 누끼 레이어

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

    // MARK: - 커스텀 텍스트 오버레이

    private var overlayLayer: some View {
        TicketCustomTextOverlay(
            text: model.customOverlayText ?? "",
            cardWidth: W,
            cardHeight: H
        )
    }

    // MARK: - 워터마크만 (커스텀 텍스트 없을 때)

    private var watermmarkOnlyLayer: some View {
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
            Spacer()
        }
        .frame(width: W, height: H, alignment: .top)
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

    // MARK: - 하단 바

    private var footerBar: some View {
        HStack(spacing: 10) {
            // 카테고리 아이콘
            ZStack {
                Circle()
                    .fill(model.bandColor.opacity(0.18))
                Image(systemName: model.cultureType.iconName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(model.bandColor)
            }
            .frame(width: 28, height: 28)

            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(width: 1, height: 30)

            // 제목 + 아티스트
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                if let artist = model.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

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
            // 별점
            if model.eventStatus == .completed && model.rating > 0 {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= model.rating ? "star.fill" : "star")
                            .font(.system(size: 7))
                            .foregroundStyle(star <= model.rating ? Color.yellow : Color.black.opacity(0.2))
                    }
                }
            }
            // 날짜
            if let date = model.date {
                Text(DateFormatter.cultureTicketDate.string(from: date))
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.48))
                    .lineLimit(1)
            }
            // 장소
            if let location = model.location, !location.isEmpty {
                Text(location)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.38))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Preview

#Preview("콘서트 - 커스텀 텍스트") {
    CultureTicketCardView(model: CultureTicketModel(
        title: "BTS 월드투어 서울",
        artist: "BTS",
        cultureType: .concert,
        rating: 5,
        eventStatus: .completed,
        seatInfo: "VIP A구역 3열",
        date: Date(),
        location: "잠실 올림픽 주경기장",
        bandColor: .purple,
        customOverlayText: "인생 공연이다!!!"
    ))
    .padding()
    .background(Color(red: 0.08, green: 0.08, blue: 0.10))
}

#Preview("뮤지컬 - 텍스트 없음") {
    CultureTicketCardView(model: CultureTicketModel(
        title: "위키드 내한",
        artist: "옥주현, 정선아",
        cultureType: .musical,
        rating: 4,
        eventStatus: .completed,
        date: Date(),
        location: "블루스퀘어",
        bandColor: .red
    ))
    .padding()
    .background(Color(red: 0.08, green: 0.08, blue: 0.10))
}
