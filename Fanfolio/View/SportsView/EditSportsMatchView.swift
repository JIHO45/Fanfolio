//
//  EditSportsMatchView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import SwiftData
import PhotosUI

struct EditSportsMatchView: View {
    let match: SportsModel
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - @State 복사본 (취소 시 원본 보존)
    @State private var team1: String
    @State private var opponentTeam: String
    @State private var myTeamScore: Int
    @State private var opponentScore: Int
    @State private var matchResult: MatchResult
    @State private var matchStatus: MatchStatus
    @State private var isHomeGame: Bool
    @State private var date: Date
    @State private var location: String
    @State private var memo: String
    
    // MARK: - Photo State (QR)
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var qrCodeImageData: Data?
    @State private var qrDetected = false
    
    // MARK: - Photo State (직관 사진)
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photosData: [Data]
    
    @State private var showingMyScorePickerSheet = false
    @State private var showingOpponentScorePickerSheet = false
    
    private var hasFavoriteTeam: Bool { match.folder?.teamLogoUrl != nil }
    private var team1Name: String { hasFavoriteTeam ? (match.folder?.displayName ?? "내 팀") : team1 }
    private var team2Name: String { opponentTeam }
    
    /// 폴더에 리그가 있으면 같은 리그 팀 목록 (응원 팀 선택 시에만 내 팀 제외)
    private var opponentTeams: [ESPNTeam] {
        guard let folder = match.folder, let code = folder.leagueCode else { return [] }
        let teams = ESPNTeamsLoader.teams(for: code)
        return folder.teamLogoUrl != nil
            ? teams.filter { $0.name_en != folder.name }
            : teams
    }
    
    private var teamsForTeam2: [ESPNTeam] {
        guard let folder = match.folder, let code = folder.leagueCode else { return [] }
        return ESPNTeamsLoader.teams(for: code).filter { $0.name_en != team1 }
    }
    
    init(match: SportsModel) {
        self.match = match
        _team1 = State(initialValue: match.team1 ?? match.folder?.displayName ?? "")
        _opponentTeam = State(initialValue: match.opponentTeam)
        _myTeamScore = State(initialValue: match.myTeamScore)
        _opponentScore = State(initialValue: match.opponentScore)
        _matchResult = State(initialValue: match.matchResult)
        _matchStatus = State(initialValue: match.matchStatus)
        _isHomeGame = State(initialValue: match.isHomeGame)
        _date = State(initialValue: match.date ?? Date())
        _location = State(initialValue: match.location ?? "")
        _memo = State(initialValue: match.memo ?? "")
        _qrCodeImageData = State(initialValue: match.qrCodeImageData)
        _photosData = State(initialValue: match.photosData ?? [])
    }
    
    var body: some View {
        NavigationStack {
            Form {
                statusSection
                teamInfoSection
                scoreSection
                dateLocationSection
                ticketPhotoSection
                gamePhotosSection
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
                        .disabled(hasFavoriteTeam ? opponentTeam.isEmpty : (team1.isEmpty || opponentTeam.isEmpty))
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                loadPhoto(from: newValue)
            }
            .onChange(of: selectedPhotos) { _, newValues in
                loadPhotos(from: newValues)
            }
            .onChange(of: myTeamScore) { _, _ in autoUpdateResult() }
            .onChange(of: opponentScore) { _, _ in autoUpdateResult() }
            .onChange(of: team1) { _, newTeam1 in
                if opponentTeam == newTeam1 { opponentTeam = "" }
            }
            .sheet(isPresented: $showingMyScorePickerSheet) {
                ScorePickerSheet(title: team1Name, selection: $myTeamScore, range: scoreRange, onConfirm: {
                    showingMyScorePickerSheet = false
                })
            }
            .sheet(isPresented: $showingOpponentScorePickerSheet) {
                ScorePickerSheet(title: "상대 팀", selection: $opponentScore, range: scoreRange, onConfirm: {
                    showingOpponentScorePickerSheet = false
                })
            }
        }
    }
}

// MARK: - Sections
extension EditSportsMatchView {
    
    private var statusSection: some View {
        Section {
            Picker("경기 상태", selection: $matchStatus) {
                ForEach(MatchStatus.allCases) { status in
                    Label(status.rawValue, systemImage: status.iconName)
                        .tag(status)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("경기 전에는 '경기 예정', 경기 후에는 '완료'로 변경하세요.")
        }
    }
    
    private var teamInfoSection: some View {
        Section {
            if hasFavoriteTeam {
                HStack {
                    Text("내 팀")
                    Spacer()
                    Text(team1Name)
                        .foregroundStyle(.secondary)
                }
                teamPickerGrid(teams: opponentTeams, selection: $opponentTeam, label: "상대 팀")
            } else if !opponentTeams.isEmpty {
                teamPickerGrid(teams: opponentTeams, selection: $team1, label: "팀 1")
                teamPickerGrid(teams: teamsForTeam2, selection: $opponentTeam, label: "팀 2")
            }
            
            if opponentTeams.isEmpty {
                if hasFavoriteTeam {
                    TextField("상대 팀", text: $opponentTeam)
                } else {
                    HStack {
                        TextField("팀 1", text: $team1)
                        TextField("팀 2", text: $opponentTeam)
                    }
                }
            }
            
            Toggle("홈 경기", isOn: $isHomeGame)
        } header: {
            Text("경기 정보")
        } footer: {
            if !opponentTeams.isEmpty {
                Text(hasFavoriteTeam ? "같은 리그 팀을 탭하여 선택하세요." : "경기한 두 팀을 각각 탭하여 선택하세요.")
            }
        }
    }
    
    @ViewBuilder
    private func teamPickerGrid(teams: [ESPNTeam], selection: Binding<String>, label: String) -> some View {
        if !teams.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 4),
                    spacing: 12
                ) {
                    ForEach(teams) { team in
                        Button {
                            selection.wrappedValue = team.name_en
                        } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        LinearGradient(
                                            colors: team.gradientColors,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        
                                        AsyncImage(url: URL(string: team.logo_url)) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image.resizable().scaledToFit().padding(6)
                                            case .failure:
                                                Image(systemName: "photo")
                                                    .font(.caption)
                                                    .foregroundStyle(.white.opacity(0.8))
                                            case .empty:
                                                ProgressView().tint(.white)
                                            @unknown default:
                                                EmptyView()
                                            }
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                    
                                    Text(team.name_en)
                                        .font(.system(size: 8))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selection.wrappedValue == team.name_en ? Color.blue.opacity(0.1) : Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(selection.wrappedValue == team.name_en ? Color.blue : Color.clear, lineWidth: 2)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }

    
    
    private var scoreRange: ClosedRange<Int> {
        0...max(300, myTeamScore, opponentScore)
    }
    
    private var scoreSection: some View {
        Section("스코어") {
            Button {
                showingMyScorePickerSheet = true
            } label: {
                HStack {
                    Text(team1Name)
                    Spacer()
                    Text("\(myTeamScore)")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            
            Button {
                showingOpponentScorePickerSheet = true
            } label: {
                HStack {
                    Text(team2Name)
                    Spacer()
                    Text("\(opponentScore)")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            
            Picker("결과", selection: $matchResult) {
                ForEach(MatchResult.allCases) { result in
                    Text(result.rawValue).tag(result)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var dateLocationSection: some View {
        Section("날짜 · 장소") {
            DatePicker("날짜", selection: $date, displayedComponents: .date)
            TextField("장소 (선택)", text: $location)
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
    
    private var gamePhotosSection: some View {
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
                    photosData.isEmpty ? "직관 사진 추가" : "사진 추가 (\(photosData.count)/10)",
                    systemImage: "camera.fill"
                )
                .foregroundStyle(.blue)
            }
        } header: {
            Text("직관 사진")
        } footer: {
            Text("경기장 사진, 셀카, 음식 등 직관 추억을 기록하세요. (최대 10장)")
        }
    }
    
    private var memoSection: some View {
        Section("메모") {
            TextField("경기 감상, 하이라이트 등", text: $memo, axis: .vertical)
                .lineLimit(3...6)
        }
    }
}

// MARK: - Actions
extension EditSportsMatchView {
    
    private func autoUpdateResult() {
        if myTeamScore > opponentScore {
            matchResult = .win
        } else if myTeamScore < opponentScore {
            matchResult = .loss
        } else {
            matchResult = .draw
        }
    }
    
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
        match.opponentTeam = opponentTeam
        match.team1 = hasFavoriteTeam ? nil : (team1.isEmpty ? nil : team1)
        match.myTeamScore = myTeamScore
        match.opponentScore = opponentScore
        match.matchResult = matchResult
        match.matchStatus = matchStatus
        match.isHomeGame = isHomeGame
        match.date = date
        match.location = location.isEmpty ? nil : location
        match.memo = memo.isEmpty ? nil : memo
        match.qrCodeImageData = qrCodeImageData
        match.photosData = photosData.isEmpty ? nil : photosData
        match.title = "\(team1Name) vs \(opponentTeam)"
        dismiss()
    }
}

#Preview {
    let folder = SportsFanFolder(name: "LG 트윈스", sportType: .baseball)
    let match = SportsModel(
        title: "LG vs 두산",
        opponentTeam: "두산 베어스",
        myTeamScore: 5,
        opponentScore: 2,
        matchResult: .win,
        matchStatus: .completed,
        date: Date(),
        location: "잠실 야구장",
        memo: "오지환 끝내기 홈런!"
    )
    match.folder = folder
    
    return EditSportsMatchView(match: match)
}
