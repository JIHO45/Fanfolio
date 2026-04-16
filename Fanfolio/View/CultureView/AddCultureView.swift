//
//  AddCultureView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import SwiftData
import PhotosUI

struct AddCultureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let folder: CultureFanFolder
    let nextOrderIndex: Int
    
    // MARK: - Form State
    @State private var eventStatus: EventStatus = .upcoming
    @State private var title = ""
    @State private var artist = ""
    @State private var date = Date()
    @State private var includeTime = false
    @State private var location = ""
    @State private var seatInfo = ""
    @State private var rating = 0
    @State private var memo = ""
    
    // MARK: - Photo State (QR)
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var qrCodeImageData: Data?
    @State private var qrDetected = false
    
    // MARK: - Photo State (현장 사진)
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photosData: [Data] = []
    
    var body: some View {
        NavigationStack {
            Form {
                statusSection
                eventInfoSection
                if eventStatus == .completed {
                    ratingSection
                }
                dateLocationSection
                ticketPhotoSection
                eventPhotosSection
                memoSection
            }
            .navigationTitle("관람 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { saveEvent() }
                        .fontWeight(.semibold)
                        .disabled(title.isEmpty)
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                loadPhoto(from: newValue)
            }
            .onChange(of: selectedPhotos) { _, newValues in
                loadPhotos(from: newValues)
            }
        }
    }
}

// MARK: - Sections
extension AddCultureView {
    
    private var statusSection: some View {
        Section {
            Picker("상태", selection: $eventStatus) {
                ForEach(EventStatus.allCases) { status in
                    Label(status.displayName, systemImage: status.iconName)
                        .tag(status)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(String(localized: "addCulture.statusHint", defaultValue: "관람 전이면 '예정', 이미 본 공연/영화를 기록하면 '완료'를 선택하세요."))
        }
    }
    
    private var eventInfoSection: some View {
        Section {
            // 폴더 정보 표시
            HStack {
                Text(String(localized: "addCulture.folderLabel", defaultValue: "폴더"))
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: folder.cultureType.iconName)
                        .foregroundStyle(.secondary)
                    Text(folder.name)
                        .foregroundStyle(.secondary)
                }
            }
            
            TextField("제목 (예: 위키드 첫 관람)", text: $title)
            TextField("아티스트 / 출연진 (선택)", text: $artist)
        } header: {
            Text(String(localized: "addCulture.eventInfo", defaultValue: "이벤트 정보"))
        }
    }
    
    private var ratingSection: some View {
        Section("평가") {
            VStack(spacing: 8) {
                Text(ratingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            rating = star
                        } label: {
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundStyle(star <= rating ? .yellow : .secondary.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
        }
    }
    
    private var ratingText: LocalizedStringKey {
        switch rating {
        case 5: return "최고의 경험!"
        case 4: return "매우 좋았어요"
        case 3: return "괜찮았어요"
        case 2: return "아쉬웠어요"
        case 1: return "별로였어요"
        default: return "별점을 선택하세요"
        }
    }
    
    private var dateLocationSection: some View {
        Section("날짜 · 장소") {
            DatePicker("날짜", selection: $date, displayedComponents: .date)
            Toggle(isOn: $includeTime.animation()) {
                Label("시간 설정", systemImage: "clock")
            }
            if includeTime {
                DatePicker("시간", selection: $date, displayedComponents: .hourAndMinute)
            }
            TextField("장소 (선택)", text: $location)
            TextField("좌석 정보 (선택)", text: $seatInfo)
        }
    }
    
    private var ticketPhotoSection: some View {
        TicketPhotoSectionView(
            selectedPhoto: $selectedPhoto,
            qrCodeImageData: $qrCodeImageData,
            qrDetected: $qrDetected
        )
    }
    
    private var eventPhotosSection: some View {
        Section {
            if !photosData.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photosData.indices, id: \.self) { index in
                            if let uiImage = UIImage(data: photosData[index]) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    
                                    Button {
                                        photosData.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .offset(x: 4, y: -4)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label(
                    photosData.isEmpty ? "현장 사진 추가" : "사진 추가 (\(photosData.count)/10)",
                    systemImage: "camera.fill"
                )
                .foregroundStyle(.blue)
            }
        } header: {
            Text(String(localized: "addCulture.photosSection", defaultValue: "현장 사진"))
        } footer: {
            Text(String(localized: "addCulture.photosHint", defaultValue: "공연장 사진, 셀카, 포토카드 등 추억을 기록하세요. (최대 10장)"))
        }
    }
    
    private var memoSection: some View {
        Section("메모") {
            TextField("감상평, 하이라이트, 셋리스트 등", text: $memo, axis: .vertical)
                .lineLimit(3...6)
        }
    }
}

// MARK: - Actions
extension AddCultureView {
    
    /// QR 사진 로드 (자동 QR 감지 & 크롭)
    private func loadPhoto(from item: PhotosPickerItem?) {
        Task {
            guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
            let result = await QRCodeHelper.detectAndCrop(from: data)
            qrCodeImageData = result.data
            qrDetected = result.detected
        }
    }
    
    private func loadPhotos(from items: [PhotosPickerItem]) {
        Task {
            var newPhotos: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    newPhotos.append(data)
                }
            }
            photosData = newPhotos
        }
    }
    
    private func saveEvent() {
        var photoPaths: [String]?
        if !photosData.isEmpty {
            let batchID = UUID()
            photoPaths = (0..<photosData.count).compactMap { i -> String? in
                try? ArchivePhotoStore.savePhoto(photosData[i], itemID: batchID, index: i, folder: .culture)
            }
        }
        let event = CultureModel(
            title: title,
            artist: artist.isEmpty ? nil : artist,
            date: includeTime ? date : Calendar.current.startOfDay(for: date),
            location: location.isEmpty ? nil : location,
            seatInfo: seatInfo.isEmpty ? nil : seatInfo,
            rating: rating,
            eventStatus: eventStatus,
            memo: memo.isEmpty ? nil : memo,
            qrCodeImageData: qrCodeImageData,
            photosData: nil,
            photoPaths: photoPaths,
            orderIndex: nextOrderIndex
        )
        event.folder = folder
        modelContext.insert(event)
        dismiss()
    }
}

#Preview {
    AddCultureView(
        folder: CultureFanFolder(name: "BTS", cultureType: .concert),
        nextOrderIndex: 0
    )
    .modelContainer(SportsPreviewSampleData.container)
}
