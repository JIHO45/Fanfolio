//
//  AddF1RaceView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/24/26.
//

import SwiftUI
import SwiftData
import PhotosUI

// MARK: - AddF1RaceView

struct AddF1RaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let folder: SportsFanFolder
    let nextOrderIndex: Int

    // 편집 모드 (기존 기록 수정)
    var editingRace: F1RaceModel? = nil

    // MARK: - Form State

    @State private var raceTitle = ""
    @State private var circuitName = ""
    @State private var date = Date()
    @State private var raceStatus: MatchStatus = .upcoming

    // 내 드라이버
    @State private var selectedDriver: F1Driver? = nil
    @State private var availableDrivers: [F1Driver] = []
    @State private var isLoadingDrivers = false

    // 순위
    @State private var finishPosition: Int? = nil
    @State private var isDNF = false
    @State private var showingPositionPicker = false

    // 포디움
    @State private var podium1 = ""
    @State private var podium2 = ""
    @State private var podium3 = ""

    // 미디어
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var qrCodeImageData: Data?
    @State private var qrDetected = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photosData: [Data] = []

    @State private var memo = ""

    // MARK: - 편집 모드 초기화

    private var isEditing: Bool { editingRace != nil }

    private var saveDisabled: Bool { raceTitle.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                raceInfoSection
                if raceStatus == .completed {
                    driverSection
                    podiumSection
                }
                dateLocationSection
                ticketPhotoSection
                gamePhotosSection
                memoSection
            }
            .navigationTitle(isEditing ? "레이스 편집" : "레이스 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { saveRace() }
                        .fontWeight(.semibold)
                        .disabled(saveDisabled)
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in loadQRPhoto(from: newValue) }
            .onChange(of: selectedPhotos) { _, newValues in loadGamePhotos(from: newValues) }
            .onChange(of: raceStatus) { _, newStatus in
                if newStatus == .completed && availableDrivers.isEmpty {
                    Task { await loadDrivers() }
                }
            }
            .sheet(isPresented: $showingPositionPicker) {
                positionPickerSheet
            }
            .task {
                setupIfEditing()
                if raceStatus == .completed {
                    await loadDrivers()
                }
            }
        }
    }

    // MARK: - Sections

    private var raceInfoSection: some View {
        Section {
            TextField("예: 2026 일본 그랑프리", text: $raceTitle)

            TextField("서킷 이름 (선택)", text: $circuitName)

            Picker("레이스 상태", selection: $raceStatus) {
                ForEach([MatchStatus.upcoming, .completed], id: \.self) { s in
                    Label(s.rawValue, systemImage: s.iconName).tag(s)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("레이스 정보")
        } footer: {
            Text("직관하기 전이면 '경기 예정', 이미 끝난 레이스를 기록하면 '완료'를 선택하세요.")
        }
    }

    private var driverSection: some View {
        Section {
            if isLoadingDrivers {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("드라이버 목록 로딩 중…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // "선택 안 함" 셀
                        driverCell(driver: nil)

                        ForEach(availableDrivers) { driver in
                            driverCell(driver: driver)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }

            // 순위 입력
            if selectedDriver != nil {
                HStack {
                    Text("최종 순위")
                    Spacer()
                    if isDNF {
                        Text("DNF")
                            .font(.subheadline.bold())
                            .foregroundStyle(.red)
                    } else if let pos = finishPosition {
                        Text("\(pos)위")
                            .font(.subheadline.bold())
                            .foregroundStyle(positionColor(pos))
                    } else {
                        Text("탭하여 선택")
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { showingPositionPicker = true }

                Toggle("리타이어(DNF)", isOn: $isDNF)
                    .onChange(of: isDNF) { _, newVal in
                        if newVal { finishPosition = nil }
                    }
            }
        } header: {
            Text("내 드라이버")
        } footer: {
            if selectedDriver == nil {
                Text("응원하는 드라이버를 선택하면 결과를 기록할 수 있습니다.")
            }
        }
    }

    private var podiumSection: some View {
        Section {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                TextField("1위 드라이버", text: $podium1)
            }
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Color(red: 0.75, green: 0.75, blue: 0.75))
                TextField("2위 드라이버", text: $podium2)
            }
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Color(red: 0.8, green: 0.5, blue: 0.2))
                TextField("3위 드라이버", text: $podium3)
            }
        } header: {
            Text("포디움 (선택)")
        } footer: {
            Text("시상대에 오른 1~3위 드라이버를 입력하세요.")
        }
    }

    private var dateLocationSection: some View {
        Section("날짜") {
            DatePicker("날짜", selection: $date, displayedComponents: .date)
        }
    }

    private var ticketPhotoSection: some View {
        Section {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                if let data = qrCodeImageData, let uiImage = UIImage(data: data) {
                    VStack(spacing: 8) {
                        Image(uiImage: uiImage)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        if qrDetected {
                            Label("QR코드 자동 감지됨", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        }
                        Text("탭하여 변경")
                            .font(.caption).foregroundStyle(.secondary)
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

    private var gamePhotosSection: some View {
        Section {
            if !photosData.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photosData.indices, id: \.self) { index in
                            if let uiImage = UIImage(data: photosData[index]) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable().scaledToFill()
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
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
                Label(
                    photosData.isEmpty ? "직관 사진 추가" : "사진 추가 (\(photosData.count)/10)",
                    systemImage: "camera.fill"
                ).foregroundStyle(.blue)
            }
        } header: {
            Text("직관 사진")
        } footer: {
            Text("경기장 사진, 셀카 등 직관 추억을 기록하세요. (최대 10장)")
        }
    }

    private var memoSection: some View {
        Section("메모") {
            TextField("레이스 감상, 인상적인 장면 등", text: $memo, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - 드라이버 피커 셀

    private func driverCell(driver: F1Driver?) -> some View {
        let isSelected: Bool = {
            if driver == nil { return selectedDriver == nil }
            return driver?.id == selectedDriver?.id
        }()

        return Button {
            selectedDriver = driver
            if driver == nil {
                finishPosition = nil
                isDNF = false
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.red.opacity(0.25) : Color.secondary.opacity(0.1))
                        .frame(width: 58, height: 58)

                    if let driver {
                        AsyncImage(url: URL(string: driver.headshotURL ?? "")) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                Image(systemName: "person.fill")
                                    .font(.title2)
                                    .foregroundStyle(isSelected ? Color.red : .secondary)
                            }
                        }
                        .frame(width: 54, height: 54)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.slash")
                            .font(.title2)
                            .foregroundStyle(isSelected ? Color.red : .secondary)
                    }
                }
                .overlay(Circle().strokeBorder(isSelected ? Color.red : Color.clear, lineWidth: 2))

                VStack(spacing: 2) {
                    Text(driver?.name.split(separator: " ").last.map(String.init) ?? "없음")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                    if let num = driver?.number {
                        Text("#\(num)")
                            .font(.system(size: 9))
                            .foregroundStyle(isSelected ? Color.red : Color.secondary.opacity(0.6))
                    }
                }
                .frame(width: 62)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - 순위 피커 시트

    private var positionPickerSheet: some View {
        NavigationStack {
            Picker("최종 순위", selection: Binding(
                get: { finishPosition ?? 1 },
                set: { finishPosition = $0 }
            )) {
                ForEach(1...20, id: \.self) { n in
                    Text("\(n)위").tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .navigationTitle("최종 순위")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("확인") {
                        isDNF = false
                        showingPositionPicker = false
                    }
                }
            }
        }
    }

    // MARK: - 순위 색상

    private func positionColor(_ pos: Int) -> Color {
        switch pos {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return .secondary
        }
    }
}

// MARK: - Actions

extension AddF1RaceView {

    private func setupIfEditing() {
        guard let race = editingRace else { return }
        raceTitle = race.title
        circuitName = race.circuitName ?? ""
        date = race.date ?? Date()
        raceStatus = race.raceStatus
        podium1 = race.podium1DriverName ?? ""
        podium2 = race.podium2DriverName ?? ""
        podium3 = race.podium3DriverName ?? ""
        memo = race.memo ?? ""
        qrCodeImageData = race.qrCodeImageData
        photosData = race.photosData ?? []

        if let driverName = race.myDriverName {
            selectedDriver = F1Driver(
                id: race.myDriverESPNId ?? "",
                name: driverName,
                team: race.myConstructorName ?? "",
                number: nil
            )
        }

        if let pos = race.myFinishPosition {
            if pos == 0 {
                isDNF = true
            } else {
                finishPosition = pos
            }
        }
    }

    private func loadDrivers() async {
        isLoadingDrivers = true
        defer { isLoadingDrivers = false }

        // ESPN F1 scoreboard에서 드라이버 추출 시도
        let espnAthletes = await ESPNPlayerService.shared.fetchLeagueAthletes(leagueCode: "F1_SCOREBOARD")
        if !espnAthletes.isEmpty {
            availableDrivers = espnAthletes.map { a in
                F1Driver(id: a.id, name: a.name, team: "", number: nil)
            }
            return
        }

        // fallback: 2026 시즌 하드코딩 목록
        availableDrivers = F1Data.drivers2026
    }

    private func loadQRPhoto(from item: PhotosPickerItem?) {
        Task {
            guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
            let result = await QRCodeHelper.detectAndCrop(from: data)
            qrCodeImageData = result.data
            qrDetected = result.detected
        }
    }

    private func loadGamePhotos(from items: [PhotosPickerItem]) {
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

    private func saveRace() {
        let finalPosition: Int? = isDNF ? 0 : finishPosition

        if let race = editingRace {
            // 편집 모드
            race.title = raceTitle.trimmingCharacters(in: .whitespaces)
            race.circuitName = circuitName.isEmpty ? nil : circuitName
            race.date = date
            race.raceStatus = raceStatus
            race.myDriverName = selectedDriver?.name
            race.myDriverESPNId = selectedDriver?.id
            race.myConstructorName = selectedDriver?.team
            race.myFinishPosition = finalPosition
            race.podium1DriverName = podium1.isEmpty ? nil : podium1
            race.podium2DriverName = podium2.isEmpty ? nil : podium2
            race.podium3DriverName = podium3.isEmpty ? nil : podium3
            race.memo = memo.isEmpty ? nil : memo
            race.qrCodeImageData = qrCodeImageData
            race.photosData = photosData.isEmpty ? nil : photosData
        } else {
            // 신규 기록
            let race = F1RaceModel(
                title: raceTitle.trimmingCharacters(in: .whitespaces),
                date: date,
                circuitName: circuitName.isEmpty ? nil : circuitName,
                raceStatus: raceStatus,
                myDriverName: selectedDriver?.name,
                myDriverESPNId: selectedDriver?.id,
                myConstructorName: selectedDriver?.team,
                myFinishPosition: finalPosition,
                podium1DriverName: podium1.isEmpty ? nil : podium1,
                podium2DriverName: podium2.isEmpty ? nil : podium2,
                podium3DriverName: podium3.isEmpty ? nil : podium3,
                memo: memo.isEmpty ? nil : memo,
                qrCodeImageData: qrCodeImageData,
                photosData: photosData.isEmpty ? nil : photosData,
                orderIndex: nextOrderIndex
            )
            race.folder = folder
            modelContext.insert(race)
        }

        dismiss()
    }
}

// MARK: - Preview

#Preview("레이스 추가 - 페라리 폴더") {
    let folder = SportsFanFolder(name: "Ferrari", sportType: .racing)
    folder.teamColor = "DC0000"
    folder.leagueCode = "F1"
    return AddF1RaceView(folder: folder, nextOrderIndex: 0)
        .modelContainer(SportsPreviewSampleData.container)
}
