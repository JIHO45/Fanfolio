//
//  AddGolfRoundView.swift
//  Fanfolio
//

import SwiftUI
import SwiftData
import PhotosUI

// MARK: - AddGolfRoundView

struct AddGolfRoundView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let folder: SportsFanFolder
    let nextOrderIndex: Int

    // 편집 모드 (기존 기록 수정)
    var editingRound: GolfRoundModel? = nil

    // MARK: - Form State

    @State private var roundTitle = ""
    @State private var courseName = ""
    @State private var date = Date()
    @State private var roundStatus: MatchStatus = .upcoming
    @State private var numberOfHoles = 18
    @State private var isTournament = false

    // 스코어
    @State private var totalScore: Int = 72
    @State private var par: Int = 72
    @State private var myPosition: Int = 1
    @State private var hasTotalScore = false
    @State private var hasPosition = false
    @State private var showingTotalScorePicker = false
    @State private var showingParPicker = false
    @State private var showingPositionPicker = false

    // 세부 스코어
    @State private var showDetailScore = false
    @State private var eagleCount = 0
    @State private var birdieCount = 0
    @State private var parCount = 0
    @State private var bogeyCount = 0
    @State private var doubleBogeyPlusCount = 0
    @State private var putts = 0
    @State private var fairwaysHit = 0
    @State private var greensInRegulation = 0
    @State private var hasPutts = false
    @State private var hasFairways = false
    @State private var hasGIR = false

    // 미디어
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var qrCodeImageData: Data?
    @State private var qrDetected = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photosData: [Data] = []

    @State private var memo = ""

    // MARK: - 편집 모드

    private var isEditing: Bool { editingRound != nil }
    private var saveDisabled: Bool { roundTitle.trimmingCharacters(in: .whitespaces).isEmpty }

    private var folderColor: Color {
        Color.from(hex: folder.teamColor) ?? .green
    }

    var body: some View {
        NavigationStack {
            Form {
                roundInfoSection
                if roundStatus == .completed {
                    scoreSection
                    detailScoreSection
                }
                dateSection
                ticketPhotoSection
                gamePhotosSection
                memoSection
            }
            .navigationTitle(isEditing ? "라운드 편집" : "라운드 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { saveRound() }
                        .fontWeight(.semibold)
                        .disabled(saveDisabled)
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in loadQRPhoto(from: newValue) }
            .onChange(of: selectedPhotos) { _, newValues in loadGamePhotos(from: newValues) }
            .sheet(isPresented: $showingTotalScorePicker) {
                scorePickerSheet(
                    title: "총 타수",
                    range: 50...200,
                    binding: $totalScore,
                    isPresented: $showingTotalScorePicker
                )
            }
            .sheet(isPresented: $showingParPicker) {
                scorePickerSheet(
                    title: "코스 파",
                    range: 27...75,
                    binding: $par,
                    isPresented: $showingParPicker
                )
            }
            .sheet(isPresented: $showingPositionPicker) {
                positionPickerSheet
            }
            .task {
                if isEditing { setupIfEditing() }
            }
        }
    }

    // MARK: - Sections

    private var roundInfoSection: some View {
        Section {
            TextField("예: 버디힐스 CC 봄 라운드", text: $roundTitle)
            TextField("골프장 이름 (선택)", text: $courseName)

            Picker("라운드 상태", selection: $roundStatus) {
                ForEach([MatchStatus.upcoming, .completed], id: \.self) { s in
                    Label(s.rawValue, systemImage: s.iconName).tag(s)
                }
            }
            .pickerStyle(.segmented)

            Picker("홀 수", selection: $numberOfHoles) {
                Text("9홀").tag(9)
                Text("18홀").tag(18)
            }
            .pickerStyle(.segmented)

            Toggle("대회 라운드", isOn: $isTournament)
        } header: {
            Text("라운드 정보")
        } footer: {
            Text("직관 전이면 '경기 예정', 이미 끝난 라운드를 기록하면 '완료'를 선택하세요.")
        }
    }

    private var scoreSection: some View {
        Section {
            Toggle("총 타수 입력", isOn: $hasTotalScore)

            if hasTotalScore {
                Button {
                    showingTotalScorePicker = true
                } label: {
                    HStack {
                        Text("총 타수")
                        Spacer()
                        Text("\(totalScore)타")
                            .foregroundStyle(folderColor)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showingParPicker = true
                } label: {
                    HStack {
                        Text("코스 파")
                        Spacer()
                        Text("Par \(par)")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                // 파 대비 스코어 미리보기
                let diff = totalScore - par
                HStack {
                    Text("파 대비")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(diff == 0 ? "E" : (diff < 0 ? "\(diff)" : "+\(diff)"))
                        .fontWeight(.bold)
                        .foregroundStyle(diff < 0 ? .green : (diff == 0 ? .blue : .red))
                }
                .font(.subheadline)
            }

            if isTournament {
                Toggle("순위 입력", isOn: $hasPosition)
                if hasPosition {
                    Button {
                        showingPositionPicker = true
                    } label: {
                        HStack {
                            Text("대회 순위")
                            Spacer()
                            Text("\(myPosition)위")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("스코어")
        }
    }

    private var detailScoreSection: some View {
        Section {
            Toggle("세부 스코어 입력", isOn: $showDetailScore)

            if showDetailScore {
                holeResultRow(
                    icon: "🦅",
                    label: "이글 이하",
                    accent: .yellow,
                    value: $eagleCount
                )
                holeResultRow(
                    icon: "🐦",
                    label: "버디",
                    accent: .green,
                    value: $birdieCount
                )
                holeResultRow(
                    icon: "⚪️",
                    label: "파",
                    accent: .secondary,
                    value: $parCount
                )
                holeResultRow(
                    icon: "🟠",
                    label: "보기",
                    accent: .orange,
                    value: $bogeyCount
                )
                holeResultRow(
                    icon: "🔴",
                    label: "더블보기 이상",
                    accent: .red,
                    value: $doubleBogeyPlusCount
                )

                Divider()

                Toggle("퍼팅 수 입력", isOn: $hasPutts)
                if hasPutts {
                    Stepper("퍼팅: \(putts)개", value: $putts, in: 0...100)
                }

                Toggle("페어웨이 안착 입력", isOn: $hasFairways)
                if hasFairways {
                    let total = numberOfHoles == 18 ? 14 : 7
                    Stepper(
                        "페어웨이: \(fairwaysHit)/\(total)",
                        value: $fairwaysHit,
                        in: 0...total
                    )
                }

                Toggle("그린 적중(GIR) 입력", isOn: $hasGIR)
                if hasGIR {
                    Stepper(
                        "GIR: \(greensInRegulation)/\(numberOfHoles)",
                        value: $greensInRegulation,
                        in: 0...numberOfHoles
                    )
                }
            }
        } header: {
            Text("세부 스코어 (선택)")
        } footer: {
            Text("홀별 세부 결과를 기록하면 통계를 더 자세히 볼 수 있습니다.")
        }
    }

    @ViewBuilder
    private func holeResultRow(icon: String, label: String, accent: Color, value: Binding<Int>) -> some View {
        HStack {
            Text(icon)
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 12) {
                Button {
                    if value.wrappedValue > 0 { value.wrappedValue -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accent == .secondary ? Color.secondary : accent)
                }
                .buttonStyle(.plain)

                Text("\(value.wrappedValue)")
                    .font(.subheadline.bold())
                    .frame(width: 24, alignment: .center)

                Button {
                    value.wrappedValue += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accent == .secondary ? Color.secondary : accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dateSection: some View {
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
            Text("골프장 사진, 셀카 등 직관 추억을 기록하세요. (최대 10장)")
        }
    }

    private var memoSection: some View {
        Section("메모") {
            TextField("라운드 감상, 인상적인 샷 등", text: $memo, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - 총 타수 / 파 피커 시트

    private func scorePickerSheet(
        title: String,
        range: ClosedRange<Int>,
        binding: Binding<Int>,
        isPresented: Binding<Bool>
    ) -> some View {
        NavigationStack {
            Picker(title, selection: binding) {
                ForEach(range, id: \.self) { n in
                    Text("\(n)").tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("확인") { isPresented.wrappedValue = false }
                }
            }
        }
    }

    // MARK: - 순위 피커 시트

    private var positionPickerSheet: some View {
        NavigationStack {
            Picker("대회 순위", selection: $myPosition) {
                ForEach(1...100, id: \.self) { n in
                    Text("\(n)위").tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .navigationTitle("대회 순위")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("확인") { showingPositionPicker = false }
                }
            }
        }
    }
}

// MARK: - Actions

extension AddGolfRoundView {

    private func setupIfEditing() {
        guard let round = editingRound else { return }
        roundTitle = round.title
        courseName = round.courseName ?? ""
        date = round.date ?? Date()
        roundStatus = round.roundStatus
        numberOfHoles = round.numberOfHoles
        isTournament = round.isTournament
        memo = round.memo ?? ""
        qrCodeImageData = round.qrCodeImageData
        photosData = round.photosData ?? []

        if let score = round.totalScore {
            hasTotalScore = true
            totalScore = score
        }
        if let p = round.par { par = p }

        if let pos = round.myPosition {
            hasPosition = true
            myPosition = pos
        }

        if round.hasDetailScore {
            showDetailScore = true
            eagleCount = round.eagleCount ?? 0
            birdieCount = round.birdieCount ?? 0
            parCount = round.parCount ?? 0
            bogeyCount = round.bogeyCount ?? 0
            doubleBogeyPlusCount = round.doubleBogeyPlusCount ?? 0
        }
        if let p = round.putts { hasPutts = true; putts = p }
        if let f = round.fairwaysHit { hasFairways = true; fairwaysHit = f }
        if let g = round.greensInRegulation { hasGIR = true; greensInRegulation = g }
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

    private func saveRound() {
        let finalScore: Int? = hasTotalScore ? totalScore : nil
        let finalPar: Int? = hasTotalScore ? par : nil
        let finalPosition: Int? = (isTournament && hasPosition) ? myPosition : nil

        let finalEagle: Int? = showDetailScore ? eagleCount : nil
        let finalBirdie: Int? = showDetailScore ? birdieCount : nil
        let finalPar2: Int? = showDetailScore ? parCount : nil
        let finalBogey: Int? = showDetailScore ? bogeyCount : nil
        let finalDouble: Int? = showDetailScore ? doubleBogeyPlusCount : nil
        let finalPutts: Int? = (showDetailScore && hasPutts) ? putts : nil
        let finalFairways: Int? = (showDetailScore && hasFairways) ? fairwaysHit : nil
        let finalGIR: Int? = (showDetailScore && hasGIR) ? greensInRegulation : nil

        if let round = editingRound {
            round.title = roundTitle.trimmingCharacters(in: .whitespaces)
            round.courseName = courseName.isEmpty ? nil : courseName
            round.date = date
            round.roundStatus = roundStatus
            round.numberOfHoles = numberOfHoles
            round.isTournament = isTournament
            round.totalScore = finalScore
            round.par = finalPar
            round.myPosition = finalPosition
            round.eagleCount = finalEagle
            round.birdieCount = finalBirdie
            round.parCount = finalPar2
            round.bogeyCount = finalBogey
            round.doubleBogeyPlusCount = finalDouble
            round.putts = finalPutts
            round.fairwaysHit = finalFairways
            round.greensInRegulation = finalGIR
            round.memo = memo.isEmpty ? nil : memo
            round.qrCodeImageData = qrCodeImageData
            round.photosData = photosData.isEmpty ? nil : photosData
        } else {
            let round = GolfRoundModel(
                title: roundTitle.trimmingCharacters(in: .whitespaces),
                date: date,
                courseName: courseName.isEmpty ? nil : courseName,
                roundStatus: roundStatus,
                numberOfHoles: numberOfHoles,
                isTournament: isTournament,
                myPosition: finalPosition,
                totalScore: finalScore,
                par: finalPar,
                eagleCount: finalEagle,
                birdieCount: finalBirdie,
                parCount: finalPar2,
                bogeyCount: finalBogey,
                doubleBogeyPlusCount: finalDouble,
                putts: finalPutts,
                fairwaysHit: finalFairways,
                greensInRegulation: finalGIR,
                memo: memo.isEmpty ? nil : memo,
                qrCodeImageData: qrCodeImageData,
                photosData: photosData.isEmpty ? nil : photosData,
                orderIndex: nextOrderIndex
            )
            round.folder = folder
            modelContext.insert(round)
        }

        dismiss()
    }
}

// MARK: - Preview

#Preview("라운드 추가") {
    let folder = SportsFanFolder(name: "골프", sportType: .golf)
    folder.teamColor = "2E7D32"
    return AddGolfRoundView(folder: folder, nextOrderIndex: 0)
        .modelContainer(SportsPreviewSampleData.container)
}
