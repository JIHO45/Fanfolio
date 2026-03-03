//
//  CultureDetailView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import SwiftData

struct CultureDetailView: View {
    let event: CultureModel
    
    @State private var showingEditSheet = false
    @State private var showingSharePreviewSheet = false
    @State private var showingQRZoomCover = false
    
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy년 M월 d일 (E)"
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt
    }()
    
    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt
    }()
    
    private var cultureType: CultureType {
        event.folder?.cultureType ?? .other
    }
    
    private var folderName: String {
        event.folder?.name ?? ""
    }
    
    private var bandColor: Color {
        switch cultureType {
        case .concert: return .purple
        case .musical: return .red
        case .movie: return .blue
        case .exhibition: return .teal
        case .festival: return .orange
        case .other: return .secondary
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 예정 이벤트 배너
                if event.eventStatus == .upcoming {
                    statusBanner
                        .padding(.horizontal)
                }
                
                // 메인 티켓 카드
                ticketCard
                    .padding(.horizontal)
                
                // 완료된 이벤트: 공유 버튼
                if event.eventStatus == .completed {
                    shareCallToAction
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditSheet = true
                } label: {
                    Text("편집")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditCultureView(event: event)
        }
        .sheet(isPresented: $showingSharePreviewSheet) {
            SharePreviewView { style in
                await Task { generateTicketImage(style: style) }.value
            }
        }
    }
    
    // MARK: - 상태 배너 (예정)
    private var statusBanner: some View {
        HStack {
            Image(systemName: "clock")
                .foregroundStyle(.blue)
            
            Text("예정")
                .font(.subheadline.bold())
                .foregroundStyle(.blue)
            
            Spacer()
            
            Text("편집 버튼을 눌러 관람 후 평가를 남겨보세요")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.1))
        )
    }
    
    // MARK: - 티켓 카드
    private var ticketCard: some View {
        VStack(spacing: 0) {
            // ── 상단 컬러 밴드 ──
            bandColor
                .frame(height: 10)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 20, topTrailingRadius: 20
                ))
            
            // ── 상단 영역: 이벤트 정보 + 별점 ──
            VStack(spacing: 20) {
                // 카테고리 배지
                HStack(spacing: 6) {
                    Image(systemName: cultureType.iconName)
                        .font(.caption)
                    Text(cultureType.rawValue)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())
                
                // 제목
                VStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                    
                    if let artist = event.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 별점
                if event.eventStatus == .completed && event.rating > 0 {
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= event.rating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(star <= event.rating ? .yellow : .secondary.opacity(0.2))
                            }
                        }
                        
                        Text(ratingLabel)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .background(bandColor)
                            .clipShape(Capsule())
                    }
                } else if event.eventStatus == .upcoming {
                    // D-day 표시
                    if let dDay = dDayText {
                        Text(dDay)
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(.blue)
                    }
                }
                
                // 좌석 정보
                if let seat = event.seatInfo, !seat.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "ticket")
                            .font(.caption)
                        Text(seat)
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
            
            // ── 절취선 ──
            ticketDivider
            
            // ── 하단 영역: 정보 ──
            VStack(alignment: .leading, spacing: 18) {
                // 날짜 + 장소
                if event.date != nil || event.location != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        if let date = event.date {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar")
                                    .frame(width: 20)
                                    .foregroundStyle(bandColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.dateFormatter.string(from: date))
                                        .font(.subheadline.weight(.medium))
                                    Text(Self.timeFormatter.string(from: date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let location = event.location, !location.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.and.ellipse")
                                    .frame(width: 20)
                                    .foregroundStyle(bandColor)
                                Text(location)
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                    }
                }
                
                // QR / 티켓 이미지 (탭 시 확대)
                if let data = event.qrCodeImageData,
                   let uiImage = UIImage(data: data) {
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: "qrcode")
                                .foregroundStyle(bandColor)
                            Text("티켓 · QR코드")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("탭하여 확대")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        
                        Button {
                            showingQRZoomCover = true
                        } label: {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                    .fullScreenCover(isPresented: $showingQRZoomCover) {
                        QRZoomView(imageData: data)
                    }
                }
                
                // 현장 사진 갤러리
                if let photos = event.photosData, !photos.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(bandColor)
                            Text("현장 사진")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(photos.count)장")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(photos.indices, id: \.self) { index in
                                    if let uiImage = UIImage(data: photos[index]) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 140, height: 140)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, -20)
                        .padding(.leading, 20)
                    }
                }
                
                // 메모
                if let memo = event.memo, !memo.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "quote.opening")
                                .foregroundStyle(bandColor)
                            Text("메모")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(memo)
                            .font(.body)
                            .italic()
                            .foregroundStyle(.primary.opacity(0.8))
                            .padding(.leading, 4)
                    }
                }
                
                // 브랜딩 푸터
                HStack {
                    Spacer()
                    Text("Fanfolio")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.quaternary)
                        .tracking(1)
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(UnevenRoundedRectangle(
                bottomLeadingRadius: 20, bottomTrailingRadius: 20
            ))
        }
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 6)
    }
    
    // MARK: - 별점 라벨
    private var ratingLabel: String {
        switch event.rating {
        case 5: return "최고!"
        case 4: return "좋았어요"
        case 3: return "괜찮았어요"
        case 2: return "아쉬워요"
        case 1: return "별로"
        default: return ""
        }
    }
    
    // MARK: - D-day
    private var dDayText: String? {
        guard event.eventStatus == .upcoming,
              let date = event.date else { return nil }
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        if days > 0 { return "D-\(days)" }
        if days == 0 { return "D-Day" }
        return nil
    }
    
    // MARK: - 절취선 (점선 + 양쪽 반원 노치)
    private var ticketDivider: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
                .frame(height: 28)
            
            ShareTicketDashLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(.secondary.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 28)
            
            HStack {
                Circle()
                    .fill(Color(uiColor: .systemGroupedBackground))
                    .frame(width: 28, height: 28)
                    .offset(x: -14)
                Spacer()
                Circle()
                    .fill(Color(uiColor: .systemGroupedBackground))
                    .frame(width: 28, height: 28)
                    .offset(x: 14)
            }
        }
        .frame(height: 28)
        .clipped()
    }
    
    // MARK: - 공유 CTA 버튼
    private var shareCallToAction: some View {
        Button {
            showingSharePreviewSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                Text("티켓 이미지 공유하기")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(bandColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - 공유 이미지 생성 (스타일별)
    @MainActor
    private func generateTicketImage(style: ShareStyle) -> UIImage? {
        let content = CultureTicketShareContent(
            title: event.title,
            artist: event.artist,
            cultureType: cultureType,
            rating: event.rating,
            eventStatus: event.eventStatus,
            seatInfo: event.seatInfo,
            date: event.date,
            location: event.location,
            bandColor: bandColor,
            style: style
        )
        
        let renderer = ImageRenderer(
            content: content.frame(width: 390)
        )
        renderer.scale = 3
        return renderer.uiImage
    }
}

// MARK: - 공유용 티켓 이미지 뷰 (라이트/다크 지원, 컴팩트)
/// ImageRenderer로 렌더링되는 뷰. 명시적 색상만 사용 (system color 미사용).
private struct CultureTicketShareContent: View {
    let title: String
    let artist: String?
    let cultureType: CultureType
    let rating: Int
    let eventStatus: EventStatus
    let seatInfo: String?
    let date: Date?
    let location: String?
    let bandColor: Color
    let style: ShareStyle
    
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy년 M월 d일 (E)"
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt
    }()
    
    // 스타일별 색상
    private var cardBg: Color {
        style == .light
            ? Color(red: 0.98, green: 0.98, blue: 0.97)
            : Color(red: 0.13, green: 0.11, blue: 0.17)
    }
    private var outerBg: Color {
        style == .light
            ? Color(red: 0.94, green: 0.94, blue: 0.93)
            : Color(red: 0.06, green: 0.05, blue: 0.09)
    }
    private var textPrimary: Color {
        style == .light
            ? Color(red: 0.1, green: 0.1, blue: 0.1)
            : Color(red: 0.95, green: 0.95, blue: 0.95)
    }
    private var textSecondary: Color {
        style == .light
            ? Color(red: 0.5, green: 0.5, blue: 0.5)
            : Color(red: 0.6, green: 0.6, blue: 0.65)
    }
    private var textTertiary: Color {
        style == .light
            ? Color(red: 0.75, green: 0.75, blue: 0.75)
            : Color(red: 0.35, green: 0.35, blue: 0.4)
    }
    
    private var ratingLabel: String {
        switch rating {
        case 5: return "최고!"
        case 4: return "좋았어요"
        case 3: return "괜찮았어요"
        case 2: return "아쉬워요"
        case 1: return "별로"
        default: return ""
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ── 상단 컬러 밴드 ──
            bandColor
                .frame(height: 12)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 24, topTrailingRadius: 24
                ))
            
            // ── 상단 영역: 제목 + 아티스트 + 별점 ──
            VStack(spacing: 20) {
                // 카테고리 배지
                HStack(spacing: 6) {
                    Image(systemName: cultureType.iconName)
                        .font(.caption)
                    Text(cultureType.rawValue)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(textSecondary.opacity(0.1))
                .clipShape(Capsule())
                
                // 제목 + 아티스트
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(textPrimary)
                        .multilineTextAlignment(.center)
                    
                    if let artist, !artist.isEmpty {
                        Text(artist)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(textSecondary)
                    }
                }
                
                // 별점
                if eventStatus == .completed && rating > 0 {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(
                                        star <= rating
                                            ? Color.yellow
                                            : textTertiary.opacity(0.4)
                                    )
                            }
                        }
                        
                        Text(ratingLabel)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .background(bandColor)
                            .clipShape(Capsule())
                    }
                }
                
                // 좌석
                if let seat = seatInfo, !seat.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "ticket")
                            .font(.caption)
                        Text(seat)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(cardBg)
            
            // ── 절취선 ──
            ZStack {
                cardBg.frame(height: 28)
                
                ShareTicketDashLine()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundStyle(textTertiary.opacity(0.5))
                    .frame(height: 1)
                    .padding(.horizontal, 28)
                
                HStack {
                    Circle()
                        .fill(outerBg)
                        .frame(width: 28, height: 28)
                        .offset(x: -14)
                    Spacer()
                    Circle()
                        .fill(outerBg)
                        .frame(width: 28, height: 28)
                        .offset(x: 14)
                }
            }
            .frame(height: 28)
            .clipped()
            
            // ── 하단 영역: 날짜 + 장소 + 브랜딩 ──
            VStack(alignment: .leading, spacing: 16) {
                if date != nil || location != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        if let date {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar")
                                    .frame(width: 20)
                                    .foregroundStyle(bandColor)
                                Text(Self.dateFormatter.string(from: date))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(textPrimary)
                            }
                        }
                        if let location, !location.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.and.ellipse")
                                    .frame(width: 20)
                                    .foregroundStyle(bandColor)
                                Text(location)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(textPrimary)
                            }
                        }
                    }
                }
                
                // 브랜딩
                HStack {
                    Spacer()
                    Text("Fanfolio")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(textTertiary)
                        .tracking(2)
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBg)
            .clipShape(UnevenRoundedRectangle(
                bottomLeadingRadius: 24, bottomTrailingRadius: 24
            ))
        }
        .padding(20)
        .background(outerBg)
    }
}

// MARK: - Previews
#Preview("완료") {
    let folder = CultureFanFolder(name: "BTS", cultureType: .concert)
    let event = CultureModel(
        title: "BTS 월드투어 서울",
        artist: "BTS",
        date: Date(),
        location: "잠실 올림픽 주경기장",
        seatInfo: "VIP A구역 3열 15번",
        rating: 5,
        eventStatus: .completed,
        memo: "인생 최고의 콘서트! 앵콜곡 Spring Day에서 눈물..."
    )
    event.folder = folder
    
    return NavigationStack {
        CultureDetailView(event: event)
    }
}

#Preview("예정") {
    let folder = CultureFanFolder(name: "위키드", cultureType: .musical)
    let event = CultureModel(
        title: "위키드 내한 뮤지컬",
        artist: "옥주현, 정선아",
        date: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
        location: "블루스퀘어",
        seatInfo: "1층 R석 12열",
        eventStatus: .upcoming
    )
    event.folder = folder
    
    return NavigationStack {
        CultureDetailView(event: event)
    }
}
