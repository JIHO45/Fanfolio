//
//  AddFolderView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import Kingfisher
import SwiftData

struct AddFolderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    /// nil이면 새 폴더 생성, 값이 있으면 편집 모드
    let editingFolder: SportsFanFolder?
    let nextOrderIndex: Int
    
    @State private var name: String
    @State private var sportType: SportType
    @State private var selectedLeague: LeagueInfo?
    @State private var selectedTeam: ESPNTeam?
    @State private var teamNickname: String
    @State private var matchHasOpponent: Bool
    
    private var isEditing: Bool { editingFolder != nil }

    private var folderNamePlaceholder: String {
        if !sportType.requiresTeamSelection {
            return sportType == .other
                ? String(localized: "sports.folder.placeholder.otherSport", defaultValue: "예: 테니스 직관, 복싱 경기")
                : String(localized: "sports.folder.placeholder.teamExamples", defaultValue: "예: LG 트윈스, FC서울")
        }
        if let league = selectedLeague {
            return String(format: String(localized: "sports.folder.placeholder.withLeague", defaultValue: "예: %@ 관람, LG 트윈스"), locale: .autoupdatingCurrent, league.localizedDisplayName)
        }
        return String(localized: "sports.folder.placeholder.teamExamples", defaultValue: "예: LG 트윈스, FC서울")
    }

    private var folderNameFooter: String {
        if !sportType.requiresTeamSelection {
            if selectedLeague != nil {
                return String(localized: "sports.folder.footer.freeNameWithLeague", defaultValue: "좋아하는 선수 이름이나 폴더 이름을 자유롭게 입력하세요.")
            }
            return String(localized: "sports.folder.footer.playerOrEvent", defaultValue: "응원하는 선수나 관심 있는 대회 이름을 입력하세요.")
        }
        if selectedLeague != nil {
            return String(localized: "sports.folder.footer.teamPickerHint", defaultValue: "팀을 탭하면 이름이 자동 입력됩니다. 응원 팀이 없으면 팀을 건너뛰고 직접 입력하세요. (리그만 선택해도 경기 추가 시 상대팀 선택이 가능합니다.)")
        }
        return String(localized: "sports.folder.footer.teamOrInterest", defaultValue: "응원하는 팀이나 관심사 이름을 입력하세요.")
    }

    private var leagues: [LeagueInfo] { sportType.supportedLeagues }
    private var teams: [ESPNTeam] {
        guard let league = selectedLeague else { return [] }
        return ESPNTeamsLoader.teams(for: league.code)
    }
    
    init(nextOrderIndex: Int) {
        self.editingFolder = nil
        self.nextOrderIndex = nextOrderIndex
        _name = State(initialValue: "")
        _sportType = State(initialValue: .baseball)
        _selectedLeague = State(initialValue: nil)
        _selectedTeam = State(initialValue: nil)
        _teamNickname = State(initialValue: "")
        _matchHasOpponent = State(initialValue: true)
    }
    
    init(folder: SportsFanFolder) {
        self.editingFolder = folder
        self.nextOrderIndex = folder.orderIndex
        _name = State(initialValue: folder.name)
        _sportType = State(initialValue: folder.sportType)
        _selectedLeague = State(initialValue: folder.leagueCode.flatMap { code in
            folder.sportType.supportedLeagues.first { $0.code == code }
        })
        _selectedTeam = State(initialValue: folder.leagueCode.flatMap { code in
            ESPNTeamsLoader.teams(for: code).first { $0.name_en == folder.name }
        })
        _teamNickname = State(initialValue: folder.teamNickname ?? "")
        _matchHasOpponent = State(initialValue: folder.matchHasOpponent)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if isEditing {
                    // 편집 모드: 폴더 이름과 애칭만 표시
                    Section {
                        TextField(String(localized: "sports.folder.name.field", defaultValue: "폴더 이름"), text: $name)
                    } header: {
                        Text(String(localized: "sports.folder.name.header", defaultValue: "폴더 이름"))
                    }

                    if sportType.requiresTeamSelection {
                        Section {
                            TextField(String(localized: "sports.folder.nickname.placeholder", defaultValue: "예: 49ers, 닌자스"), text: $teamNickname)
                        } header: {
                            Text(String(localized: "sports.folder.nickname.header", defaultValue: "팀 애칭 (선택)"))
                        } footer: {
                            Text(String(localized: "sports.folder.nickname.footer", defaultValue: "설정하면 경기 카드·상세 화면 등에서 공식 팀명 대신 이 이름이 표시됩니다."))
                        }
                    }
                } else {
                    // 생성 모드: 종목·리그·팀·이름 전체 표시
                    Section {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible()), count: 4),
                            spacing: 12
                        ) {
                            ForEach(SportType.allCases) { type in
                                Button {
                                    sportType = type
                                    selectedLeague = nil
                                    selectedTeam = nil
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: type.iconName)
                                            .font(.title2)
                                            .frame(width: 48, height: 48)
                                            .background(
                                                Circle()
                                                    .fill(sportType == type
                                                          ? Color.blue.opacity(0.15)
                                                          : Color.secondary.opacity(0.08))
                                            )
                                            .foregroundStyle(sportType == type ? .blue : .secondary)
                                        
                                        Text(type.displayName)
                                            .font(.caption2)
                                            .foregroundStyle(sportType == type ? .blue : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text(String(localized: "sports.folder.section.sportType", defaultValue: "종목 선택"))
                    }
                    
                    if sportType == .other {
                        Section {
                            Picker(String(localized: "sports.folder.matchType.picker", defaultValue: "경기 유형"), selection: $matchHasOpponent) {
                                Text(String(localized: "sports.folder.matchType.withOpponent", defaultValue: "상대팀 있음")).tag(true)
                                Text(String(localized: "sports.folder.matchType.solo", defaultValue: "상대팀 없음")).tag(false)
                            }
                            .pickerStyle(.segmented)
                        } header: {
                            Text(String(localized: "sports.folder.matchType.header", defaultValue: "경기 유형"))
                        } footer: {
                            Text(matchHasOpponent
                                 ? String(localized: "sports.folder.matchType.footer.withOpponent", defaultValue: "테니스, UFC 등 상대방이 있는 경기를 기록합니다.")
                                 : String(localized: "sports.folder.matchType.footer.solo", defaultValue: "마라톤, 수영 등 혼자 참가하는 경기를 기록합니다. 생성 후에는 변경할 수 없습니다."))
                        }
                    }

                    if !leagues.isEmpty {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(leagues) { league in
                                        Button {
                                            selectedLeague = league
                                            selectedTeam = nil
                                            if name.isEmpty {
                                                name = String(format: String(localized: "sports.folder.defaultName.leagueWatch", defaultValue: "%@ 관람"), locale: .autoupdatingCurrent, league.localizedDisplayName)
                                            }
                                        } label: {
                                            Text(league.localizedDisplayName)
                                                .font(.subheadline.weight(.medium))
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                                .background(
                                                    selectedLeague?.id == league.id
                                                        ? Color.blue
                                                        : Color.secondary.opacity(0.15)
                                                )
                                                .foregroundStyle(selectedLeague?.id == league.id ? .white : .primary)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            Text(String(localized: "sports.folder.section.league", defaultValue: "리그 선택"))
                        }
                    }
                    
                    if sportType.requiresTeamSelection, selectedLeague != nil, !teams.isEmpty {
                        Section {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible()), count: 4),
                                spacing: 16
                            ) {
                                ForEach(teams) { team in
                                    Button {
                                        name = team.name_en
                                        selectedTeam = team
                                    } label: {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                LinearGradient(
                                                    colors: team.gradientColors,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                                
                                                KFImage.url(URL(string: team.logo_url))
                                                    .placeholder { ProgressView().tint(.white) }
                                                    .onFailureView {
                                                        Image(systemName: "photo")
                                                            .font(.title2)
                                                            .foregroundStyle(.white.opacity(0.8))
                                                    }
                                                    .resizable()
                                                    .scaledToFit()
                                                    .padding(8)
                                            }
                                            .frame(width: 56, height: 56)
                                            
                                            Text(team.name_en)
                                                .font(.system(size: 9))
                                                .lineLimit(2)
                                                .multilineTextAlignment(.center)
                                                .foregroundStyle(.primary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(selectedTeam?.id == team.id ? Color.blue.opacity(0.1) : Color.clear)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .strokeBorder(selectedTeam?.id == team.id ? Color.blue : Color.clear, lineWidth: 2)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 8)
                        } header: {
                            Text(String(localized: "sports.folder.section.team", defaultValue: "팀 선택"))
                        }
                    }
                    
                    if sportType.requiresTeamSelection, selectedTeam != nil {
                        Section {
                            TextField(String(localized: "sports.folder.nickname.placeholder", defaultValue: "예: 49ers, 닌자스"), text: $teamNickname)
                        } header: {
                            Text(String(localized: "sports.folder.nickname.header", defaultValue: "팀 애칭 (선택)"))
                        } footer: {
                            Text(String(localized: "sports.folder.nickname.footer", defaultValue: "설정하면 경기 카드·상세 화면 등에서 공식 팀명 대신 이 이름이 표시됩니다."))
                        }
                    }
                    
                    Section {
                        TextField(folderNamePlaceholder, text: $name)
                    } header: {
                        Text(sportType.requiresTeamSelection
                             ? String(localized: "sports.folder.combinedName.header", defaultValue: "팀 / 폴더 이름")
                             : String(localized: "sports.folder.name.header", defaultValue: "폴더 이름"))
                    } footer: {
                        Text(verbatim: folderNameFooter)
                    }
                }
            }
            .navigationTitle(isEditing
                ? String(localized: "sports.folder.editTitle", defaultValue: "폴더 편집")
                : String(localized: "sports.folder.newTitle", defaultValue: "새 폴더"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: sportType) { _, _ in
                matchHasOpponent = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.action.cancel", defaultValue: "취소")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing
                           ? String(localized: "common.action.save", defaultValue: "저장")
                           : String(localized: "common.action.create", defaultValue: "만들기")) {
                        isEditing ? updateFolder() : createFolder()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private func createFolder() {
        let hasOpponent = sportType == .other ? matchHasOpponent : true
        let folder = SportsFanFolder(
            name: name.trimmingCharacters(in: .whitespaces),
            sportType: sportType,
            orderIndex: nextOrderIndex,
            matchHasOpponent: hasOpponent
        )
        if let team = selectedTeam {
            folder.leagueCode = team.league
            folder.teamLogoUrl = team.logo_url
            folder.teamColor = team.color
            folder.teamAlternateColor = team.alternate_color
        } else if let league = selectedLeague {
            folder.leagueCode = league.code
        }
        let nick = teamNickname.trimmingCharacters(in: .whitespaces)
        folder.teamNickname = nick.isEmpty ? nil : nick
        modelContext.insert(folder)
        dismiss()
    }
    
    private func updateFolder() {
        guard let folder = editingFolder else { return }
        folder.name = name.trimmingCharacters(in: .whitespaces)
        folder.sportType = sportType
        if let team = selectedTeam {
            folder.leagueCode = team.league
            folder.teamLogoUrl = team.logo_url
            folder.teamColor = team.color
            folder.teamAlternateColor = team.alternate_color
        } else {
            folder.teamLogoUrl = nil
            folder.teamColor = nil
            folder.teamAlternateColor = nil
            if let league = selectedLeague {
                folder.leagueCode = league.code
            } else {
                folder.leagueCode = nil
            }
        }
        let nick = teamNickname.trimmingCharacters(in: .whitespaces)
        folder.teamNickname = nick.isEmpty ? nil : nick
        dismiss()
    }
}

#Preview("새 폴더") {
    AddFolderView(nextOrderIndex: 0)
        .modelContainer(SportsPreviewSampleData.container)
}

#Preview("편집") {
    AddFolderView(folder: SportsFanFolder(name: "LG 트윈스", sportType: .baseball))
        .modelContainer(SportsPreviewSampleData.container)
}
