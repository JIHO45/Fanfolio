//
//  EditSportsMatchView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import Kingfisher
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
    @State private var includeTime: Bool
    @State private var location: String
    @State private var memo: String
    
    // MARK: - Photo State (QR)
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var qrCodeImageData: Data?
    @State private var qrDetected = false
    
    // MARK: - Photo State (직관 사진) — 경로(기존) + Data(신규 선택)
    private enum DisplayPhotoItem {
        case path(String)
        case data(Data)
    }
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var displayPhotoItems: [DisplayPhotoItem]
    
    @State private var showingMyScorePickerSheet = false
    @State private var showingOpponentScorePickerSheet = false
    
    private var hasFavoriteTeam: Bool { match.folder?.teamLogoUrl != nil }
    private var team1Name: String { hasFavoriteTeam ? (match.folder?.displayName ?? String(localized: "sports.match.myTeam", defaultValue: "내 팀")) : team1 }
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
        let existingDate = match.date ?? Date()
        _date = State(initialValue: existingDate)
        let cal = Calendar.current
        _includeTime = State(initialValue: cal.component(.hour, from: existingDate) != 0 || cal.component(.minute, from: existingDate) != 0)
        _location = State(initialValue: match.location ?? "")
        _memo = State(initialValue: match.memo ?? "")
        _qrCodeImageData = State(initialValue: match.qrCodeImageData)
        let paths = match.photoPaths ?? []
        let legacyData = match.photosData ?? []
        _displayPhotoItems = State(initialValue: paths.map { DisplayPhotoItem.path($0) } + legacyData.map { DisplayPhotoItem.data($0) })
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
            .navigationTitle(String(localized: "common.action.edit", defaultValue: "편집"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.action.cancel", defaultValue: "취소")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.action.save", defaultValue: "저장")) { saveChanges() }
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
                ScorePickerSheet(title: String(localized: "sports.match.opponentTeam", defaultValue: "상대 팀"), selection: $opponentScore, range: scoreRange, onConfirm: {
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
            Picker(String(localized: "sports.match.status.picker", defaultValue: "경기 상태"), selection: $matchStatus) {
                ForEach(MatchStatus.allCases) { status in
                    Label(status.displayName, systemImage: status.iconName)
                        .tag(status)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(String(localized: "sports.match.status.footer", defaultValue: "경기 전에는 '경기 예정', 경기 후에는 '완료'로 변경하세요."))
        }
    }
    
    private var teamInfoSection: some View {
        Section {
            if hasFavoriteTeam {
                HStack {
                    Text(String(localized: "sports.match.myTeam", defaultValue: "내 팀"))
                    Spacer()
                    Text(team1Name)
                        .foregroundStyle(.secondary)
                }
                teamPickerGrid(teams: opponentTeams, selection: $opponentTeam, label: String(localized: "sports.match.opponentTeam", defaultValue: "상대 팀"))
            } else if !opponentTeams.isEmpty {
                teamPickerGrid(teams: opponentTeams, selection: $team1, label: String(localized: "sports.match.team1", defaultValue: "팀 1"))
                teamPickerGrid(teams: teamsForTeam2, selection: $opponentTeam, label: String(localized: "sports.match.team2", defaultValue: "팀 2"))
            }
            
            if opponentTeams.isEmpty {
                if hasFavoriteTeam {
                    TextField(String(localized: "sports.match.opponentTeam", defaultValue: "상대 팀"), text: $opponentTeam)
                } else {
                    HStack {
                        TextField(String(localized: "sports.match.team1", defaultValue: "팀 1"), text: $team1)
                        TextField(String(localized: "sports.match.team2", defaultValue: "팀 2"), text: $opponentTeam)
                    }
                }
            }
            
            Toggle(String(localized: "sports.match.homeGame", defaultValue: "홈 경기"), isOn: $isHomeGame)
        } header: {
            Text(String(localized: "sports.match.infoSection", defaultValue: "경기 정보"))
        } footer: {
            if !opponentTeams.isEmpty {
                Text(hasFavoriteTeam
                     ? String(localized: "sports.match.teamPicker.footer.sameLeague", defaultValue: "같은 리그 팀을 탭하여 선택하세요.")
                     : String(localized: "sports.match.teamPicker.footer.twoTeams", defaultValue: "경기한 두 팀을 각각 탭하여 선택하세요."))
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
                                        
                                        KFImage.url(URL(string: team.logo_url))
                                            .placeholder { ProgressView().tint(.white) }
                                            .onFailureView {
                                                Image(systemName: "photo")
                                                    .font(.caption)
                                                    .foregroundStyle(.white.opacity(0.8))
                                            }
                                            .resizable()
                                            .scaledToFit()
                                            .padding(6)
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
        Section(String(localized: "sports.match.scoreSection", defaultValue: "스코어")) {
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
            
            Picker(String(localized: "sports.match.result", defaultValue: "결과"), selection: $matchResult) {
                ForEach(MatchResult.allCases) { result in
                    Text(result.displayName).tag(result)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var dateLocationSection: some View {
        Section(String(localized: "sports.match.dateLocationSection", defaultValue: "날짜 · 장소")) {
            DatePicker(String(localized: "sports.match.date", defaultValue: "날짜"), selection: $date, displayedComponents: .date)
            Toggle(isOn: $includeTime.animation()) {
                Label(String(localized: "sports.match.timeToggle", defaultValue: "시간 설정"), systemImage: "clock")
            }
            if includeTime {
                DatePicker(String(localized: "sports.match.time", defaultValue: "시간"), selection: $date, displayedComponents: .hourAndMinute)
            }
            TextField(String(localized: "sports.match.locationOptional", defaultValue: "장소 (선택)"), text: $location)
        }
    }
    
    private var ticketPhotoSection: some View {
        TicketPhotoSectionView(
            selectedPhoto: $selectedPhoto,
            qrCodeImageData: $qrCodeImageData,
            qrDetected: $qrDetected
        )
    }
    
    private var gamePhotosSection: some View {
        Section {
            if !displayPhotoItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(displayPhotoItems.indices, id: \.self) { index in
                            let item = displayPhotoItems[index]
                            if let uiImage = photoImage(for: item) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    
                                    Button {
                                        displayPhotoItems.remove(at: index)
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
                maxSelectionCount: max(0, 10 - displayPhotoItems.count),
                matching: .images
            ) {
                Label {
                    Text(displayPhotoItems.isEmpty
                         ? String(localized: "sports.match.photos.addFirst", defaultValue: "직관 사진 추가")
                         : String(format: String(localized: "sports.match.photos.addMore", defaultValue: "사진 추가 (%lld/10)"), locale: .autoupdatingCurrent, Int64(displayPhotoItems.count)))
                } icon: {
                    Image(systemName: "camera.fill")
                }
                .foregroundStyle(.blue)
            }
        } header: {
            Text(String(localized: "sports.match.photos.header", defaultValue: "직관 사진"))
        } footer: {
            Text(String(localized: "sports.match.photos.footer", defaultValue: "경기장 사진, 셀카, 음식 등 직관 추억을 기록하세요. (최대 10장)"))
        }
    }
    
    private func photoImage(for item: DisplayPhotoItem) -> UIImage? {
        switch item {
        case .path(let p): return ArchivePhotoStore.loadImage(path: p)
        case .data(let d): return UIImage(data: d)
        }
    }
    
    private var memoSection: some View {
        Section(String(localized: "sports.match.memoSection", defaultValue: "메모")) {
            TextField(String(localized: "sports.match.memo.placeholder", defaultValue: "경기 감상, 하이라이트 등"), text: $memo, axis: .vertical)
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
            var newItems: [DisplayPhotoItem] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    newItems.append(.data(data))
                }
            }
            let allowed = max(0, 10 - displayPhotoItems.count)
            await MainActor.run {
                displayPhotoItems.append(contentsOf: newItems.prefix(allowed))
            }
        }
    }
    
    private func saveChanges() {
        let oldLocKey = (match.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let newLocKey = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldResetVenueCoords =
            match.opponentTeam != opponentTeam
            || match.isHomeGame != isHomeGame
            || oldLocKey != newLocKey

        match.opponentTeam = opponentTeam
        match.team1 = hasFavoriteTeam ? nil : (team1.isEmpty ? nil : team1)
        match.myTeamScore = myTeamScore
        match.opponentScore = opponentScore
        match.matchResult = matchResult
        match.matchStatus = matchStatus
        match.isHomeGame = isHomeGame
        match.date = includeTime ? date : Calendar.current.startOfDay(for: date)
        match.location = location.isEmpty ? nil : location
        if shouldResetVenueCoords {
            match.venueLatitude = nil
            match.venueLongitude = nil
        }
        match.memo = memo.isEmpty ? nil : memo
        match.qrCodeImageData = qrCodeImageData
        
        var paths: [String] = []
        let batchID = UUID()
        for (index, item) in displayPhotoItems.enumerated() {
            switch item {
            case .path(let p): paths.append(p)
            case .data(let d):
                if let p = try? ArchivePhotoStore.savePhoto(d, itemID: batchID, index: index, folder: .match) {
                    paths.append(p)
                }
            }
        }
        let previousPaths = match.photoPaths ?? []
        let toDelete = previousPaths.filter { !paths.contains($0) }
        ArchivePhotoStore.delete(paths: toDelete)
        match.photoPaths = paths.isEmpty ? nil : paths
        match.photosData = nil
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
