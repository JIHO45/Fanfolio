//
//  EditCultureView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import SwiftData
import PhotosUI

struct EditCultureView: View {
    let event: CultureModel
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - @State 복사본 (취소 시 원본 보존)
    @State private var eventStatus: EventStatus
    @State private var title: String
    @State private var artist: String
    @State private var date: Date
    @State private var location: String
    @State private var seatInfo: String
    @State private var rating: Int
    @State private var memo: String
    
    // MARK: - Photo State (QR)
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var qrCodeImageData: Data?
    @State private var qrDetected = false
    
    // MARK: - Photo State (현장 사진)
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photosData: [Data]
    
    private var folderName: String {
        event.folder?.name ?? ""
    }
    
    private var cultureType: CultureType {
        event.folder?.cultureType ?? .other
    }
    
    init(event: CultureModel) {
        self.event = event
        _eventStatus = State(initialValue: event.eventStatus)
        _title = State(initialValue: event.title)
        _artist = State(initialValue: event.artist ?? "")
        _date = State(initialValue: event.date ?? Date())
        _location = State(initialValue: event.location ?? "")
        _seatInfo = State(initialValue: event.seatInfo ?? "")
        _rating = State(initialValue: event.rating)
        _memo = State(initialValue: event.memo ?? "")
        _qrCodeImageData = State(initialValue: event.qrCodeImageData)
        _photosData = State(initialValue: event.photosData ?? [])
    }
    
    var body: some View {
        NavigationStack {
            Form {
                statusSection
                eventInfoSection
                ratingSection
                dateLocationSection
                ticketPhotoSection
                eventPhotosSection
                memoSection
            }
            .navigationTitle("편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { saveChanges() }
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
extension EditCultureView {
    
    private var statusSection: some View {
        Section {
            Picker("상태", selection: $eventStatus) {
                ForEach(EventStatus.allCases) { status in
                    Label(status.rawValue, systemImage: status.iconName)
                        .tag(status)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("관람 전에는 '예정', 관람 후에는 '완료'로 변경하세요.")
        }
    }
    
    private var eventInfoSection: some View {
        Section {
            HStack {
                Text("폴더")
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: cultureType.iconName)
                        .foregroundStyle(.secondary)
                    Text(folderName)
                        .foregroundStyle(.secondary)
                }
            }
            
            TextField("제목", text: $title)
            TextField("아티스트 / 출연진", text: $artist)
        } header: {
            Text("이벤트 정보")
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
    
    private var ratingText: String {
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
            TextField("장소 (선택)", text: $location)
            TextField("좌석 정보 (선택)", text: $seatInfo)
        }
    }
    
    private var ticketPhotoSection: some View {
        Section {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                if let data = qrCodeImageData,
                   let uiImage = UIImage(data: data) {
                    VStack(spacing: 8) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        if qrDetected {
                            Label("QR코드 자동 감지됨", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        }
                        
                        Text("탭하여 변경")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("티켓 · QR코드 사진 추가", systemImage: "qrcode.viewfinder")
                        .foregroundStyle(.blue)
                }
            }
            
            if qrCodeImageData != nil {
                Button("사진 삭제", role: .destructive) {
                    qrCodeImageData = nil
                    selectedPhoto = nil
                    qrDetected = false
                }
            }
        } header: {
            Text("티켓 · QR코드")
        } footer: {
            Text("사진에 QR코드가 포함되어 있으면 자동으로 감지하여 QR 영역만 추출합니다.")
        }
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
            Text("현장 사진")
        } footer: {
            Text("공연장 사진, 셀카, 포토카드 등 추억을 기록하세요. (최대 10장)")
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
extension EditCultureView {
    
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
    
    private func saveChanges() {
        event.eventStatus = eventStatus
        event.title = title
        event.artist = artist.isEmpty ? nil : artist
        event.date = date
        event.location = location.isEmpty ? nil : location
        event.seatInfo = seatInfo.isEmpty ? nil : seatInfo
        event.rating = rating
        event.memo = memo.isEmpty ? nil : memo
        event.qrCodeImageData = qrCodeImageData
        event.photosData = photosData.isEmpty ? nil : photosData
        dismiss()
    }
}

#Preview {
    let folder = CultureFanFolder(name: "BTS", cultureType: .concert)
    let event = CultureModel(
        title: "BTS 콘서트",
        artist: "BTS",
        date: Date(),
        location: "잠실 올림픽 주경기장",
        seatInfo: "VIP A구역 3열",
        rating: 5,
        eventStatus: .completed,
        memo: "최고의 공연이었다!"
    )
    event.folder = folder
    
    return EditCultureView(event: event)
}
