//
//  TicketGalleryView.swift
//  Fanfolio
//
//  Created by Cursor on 3/14/26.
//

import SwiftUI
import SwiftData

struct TicketGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedTicket.createdAt, order: .reverse) private var tickets: [SavedTicket]
    
    @State private var selectedSportType: SportType?
    @State private var selectedTicket: SavedTicket?
    @State private var ticketToDelete: SavedTicket?
    @State private var shareImage: UIImage?
    @State private var shareErrorMessage: String?
    @State private var isPreparingShare = false
    
    private var filteredTickets: [SavedTicket] {
        guard let selectedSportType else { return tickets }
        return tickets.filter { $0.sportType == selectedSportType }
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            filterSection
            galleryGridContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(String(localized: "ticket.gallery.navigationTitle", defaultValue: "티켓 갤러리"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "ticket.gallery.delete.title", defaultValue: "티켓 삭제"), isPresented: Binding(
            get: { ticketToDelete != nil },
            set: { if !$0 { ticketToDelete = nil } }
        )) {
            Button(String(localized: "common.action.cancel", defaultValue: "취소"), role: .cancel) {
                ticketToDelete = nil
            }
            Button(String(localized: "common.action.delete", defaultValue: "삭제"), role: .destructive) {
                deleteSelectedTicket()
            }
        } message: {
            Text(String(localized: "ticket.gallery.delete.message", defaultValue: "선택한 티켓을 갤러리에서 삭제합니다. 저장된 이미지 파일도 함께 제거됩니다."))
        }
        .alert(String(localized: "ticket.gallery.shareUnavailable.title", defaultValue: "공유할 수 없음"), isPresented: Binding(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )) {
            Button(String(localized: "common.action.ok", defaultValue: "확인"), role: .cancel) {
                shareErrorMessage = nil
            }
        } message: {
            Text(shareErrorMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { shareImage != nil },
            set: { if !$0 { shareImage = nil } }
        )) {
            if let shareImage {
                FanfolioShareSheet(items: [shareImage])
            }
        }
        .fullScreenCover(item: $selectedTicket) { ticket in
            TicketImageViewerView(ticket: ticket)
        }
    }

    @ViewBuilder
    private var galleryGridContent: some View {
        if filteredTickets.isEmpty {
            ContentUnavailableView {
                Label {
                    Text(tickets.isEmpty
                        ? String(localized: "ticket.gallery.empty.title", defaultValue: "저장된 티켓이 없습니다")
                        : String(localized: "ticket.gallery.filteredEmpty.title", defaultValue: "조건에 맞는 티켓이 없습니다"))
                } icon: {
                    Image(systemName: "ticket")
                }
            } description: {
                Text(tickets.isEmpty
                    ? String(localized: "ticket.gallery.empty.description", defaultValue: "경기 상세에서 티켓 이미지를 저장하면 여기에서 다시 볼 수 있습니다.")
                    : String(localized: "ticket.gallery.filteredEmpty.description", defaultValue: "다른 종목 필터를 선택해보세요."))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredTickets) { ticket in
                        SavedTicketThumbnailView(ticket: ticket)
                            .contentShape(RoundedRectangle(cornerRadius: 18))
                            .onTapGesture {
                                selectedTicket = ticket
                            }
                            .contextMenu {
                                Button {
                                    shareTicket(ticket)
                                } label: {
                                    Label(String(localized: "common.action.share", defaultValue: "공유"), systemImage: "square.and.arrow.up")
                                }

                                Button(role: .destructive) {
                                    ticketToDelete = ticket
                                } label: {
                                    Label(String(localized: "common.action.delete", defaultValue: "삭제"), systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
    }
    
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TicketFilterChip(
                    title: String(localized: "common.filter.all", defaultValue: "전체"),
                    iconName: "square.grid.2x2",
                    isSelected: selectedSportType == nil
                ) {
                    selectedSportType = nil
                }
                
                ForEach(SportType.allCases) { sportType in
                    TicketFilterChip(
                        title: sportType.displayName,
                        iconName: sportType.iconName,
                        isSelected: selectedSportType == sportType
                    ) {
                        selectedSportType = sportType
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }
    
    private func shareTicket(_ ticket: SavedTicket) {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        let path = ticket.imagePath
        Task {
            let image = await TicketImageExport.prepareSavedTicketShareImage(
                relativeMasterPath: path,
                isPro: FanfolioEntitlements.isPro
            )
            await MainActor.run {
                isPreparingShare = false
                if let image {
                    shareImage = image
                } else {
                    shareErrorMessage = String(localized: "ticket.gallery.error.sharePrepareFailed", defaultValue: "공유용 이미지를 만들지 못했습니다.")
                }
            }
        }
    }
    
    private func deleteSelectedTicket() {
        guard let ticket = ticketToDelete else { return }
        TicketImageStore.delete(paths: [ticket.imagePath, ticket.thumbnailPath])
        modelContext.delete(ticket)
        ticketToDelete = nil
    }
}

struct SavedTicketThumbnailView: View {
    let ticket: SavedTicket
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.08))
                
                if let image = TicketImageStore.loadImageCached(path: ticket.thumbnailPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    MissingTicketImagePlaceholder(
                        title: String(localized: "ticket.gallery.placeholder.missingLocalImage.title", defaultValue: "로컬 이미지 없음"),
                        subtitle: String(localized: "ticket.gallery.placeholder.missingLocalImage.subtitle", defaultValue: "이 기기에서 생성된 티켓만 볼 수 있어요.")
                    )
                    .padding(16)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(ticket.team1Name) vs \(ticket.team2Name)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                
                Label(ticket.sportType.displayName, systemImage: ticket.sportType.iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    Text("\(ticket.myTeamScore)")
                    Text(":")
                    Text("\(ticket.opponentScore)")
                    Text(ticket.matchResult.displayName)
                        .foregroundStyle(ticket.matchResult.color)
                }
                .font(.caption.weight(.semibold))
                
                if let matchDate = ticket.matchDate {
                    Text(Self.dateFormatter.string(from: matchDate))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

struct TicketImageViewerView: View {
    @Environment(\.dismiss) private var dismiss
    
    let ticket: SavedTicket
    
    @State private var shareImage: UIImage?
    @State private var isPreparingShare = false
    @State private var shareFailedMessage: String?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let image = TicketImageStore.loadImage(path: ticket.imagePath) {
                GeometryReader { geometry in
                    // 9:16 티켓 이미지의 실제 렌더 크기 계산
                    let screenW = geometry.size.width
                    let screenH = geometry.size.height
                    let imageAspect = image.size.width / max(1, image.size.height)
                    let screenAspect = screenW / max(1, screenH)
                    // scaledToFit 결과: 세로형 티켓은 대부분 높이 기준으로 맞춰짐
                    let fittedW = imageAspect < screenAspect
                        ? screenH * imageAspect
                        : screenW
                    let fittedH = imageAspect < screenAspect
                        ? screenH
                        : screenW / imageAspect
                    
                    // scale > 1일 때 드래그 가능 범위 (이미지 밖으로 나가지 않도록)
                    let maxOffsetX = max(0, (fittedW * scale - screenW) / 2)
                    let maxOffsetY = max(0, (fittedH * scale - screenH) / 2)
                    
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: screenW, height: screenH)
                        // scale = 1이면 드래그 비활성, scale > 1이면 이미지 범위 내 이동
                        .gesture(
                            scale > 1
                                ? DragGesture()
                                    .onChanged { value in
                                        let newX = lastOffset.width + value.translation.width
                                        let newY = lastOffset.height + value.translation.height
                                        offset = CGSize(
                                            width:  max(-maxOffsetX, min(maxOffsetX, newX)),
                                            height: max(-maxOffsetY, min(maxOffsetY, newY))
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                                : nil
                        )
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(max(lastScale * value, 1), 4)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale <= 1.01 {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            scale = 1
                                            lastScale = 1
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    } else {
                                        // 줌 축소 후 이미지가 범위를 벗어났으면 재클램핑
                                        let clampedX = max(-maxOffsetX, min(maxOffsetX, offset.width))
                                        let clampedY = max(-maxOffsetY, min(maxOffsetY, offset.height))
                                        if clampedX != offset.width || clampedY != offset.height {
                                            withAnimation(.easeOut(duration: 0.15)) {
                                                offset = CGSize(width: clampedX, height: clampedY)
                                                lastOffset = offset
                                            }
                                        }
                                    }
                                }
                        )
                }
            } else {
                MissingTicketImagePlaceholder(
                    title: String(localized: "ticket.gallery.placeholder.viewerMissing.title", defaultValue: "티켓 이미지를 찾을 수 없습니다"),
                    subtitle: String(localized: "ticket.gallery.placeholder.viewerMissing.subtitle", defaultValue: "다른 기기에서 동기화된 기록이거나 파일이 삭제되었을 수 있습니다.")
                )
                .padding(24)
            }
            
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Button {
                        guard !isPreparingShare else { return }
                        isPreparingShare = true
                        let path = ticket.imagePath
                        Task {
                            let image = await TicketImageExport.prepareSavedTicketShareImage(
                                relativeMasterPath: path,
                                isPro: FanfolioEntitlements.isPro
                            )
                            await MainActor.run {
                                isPreparingShare = false
                                if let image {
                                    shareImage = image
                                } else {
                                    shareFailedMessage = String(localized: "ticket.gallery.error.sharePrepareFailed", defaultValue: "공유용 이미지를 만들지 못했습니다.")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                            .overlay {
                                if isPreparingShare {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.9)
                                }
                            }
                    }
                    .disabled(isPreparingShare)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(ticket.team1Name) vs \(ticket.team2Name)")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(ticket.myTeamScore) : \(ticket.opponentScore) · \(ticket.matchResult.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                    Label(ticket.sportType.displayName, systemImage: ticket.sportType.iconName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: Binding(
            get: { shareImage != nil },
            set: { if !$0 { shareImage = nil } }
        )) {
            if let shareImage {
                FanfolioShareSheet(items: [shareImage])
            }
        }
        .alert(String(localized: "ticket.gallery.shareUnavailable.title", defaultValue: "공유할 수 없음"), isPresented: Binding(
            get: { shareFailedMessage != nil },
            set: { if !$0 { shareFailedMessage = nil } }
        )) {
            Button(String(localized: "common.action.ok", defaultValue: "확인"), role: .cancel) {
                shareFailedMessage = nil
            }
        } message: {
            Text(shareFailedMessage ?? "")
        }
    }
}

private struct TicketFilterChip: View {
    let title: String
    let iconName: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                Text(title)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color.secondary.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct MissingTicketImagePlaceholder: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "icloud.slash")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.8))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
