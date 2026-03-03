//
//  AddFolderView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
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
    
    private var isEditing: Bool { editingFolder != nil }

    private var folderNamePlaceholder: String {
        if !sportType.requiresTeamSelection {
            return sportType.noTeamNameHint
        }
        return selectedLeague.map { "예: \($0.displayName) 관람, LG 트윈스" } ?? "예: LG 트윈스, FC서울"
    }

    private var folderNameFooter: String {
        if !sportType.requiresTeamSelection {
            if selectedLeague != nil {
                return "좋아하는 선수 이름이나 폴더 이름을 자유롭게 입력하세요."
            }
            return "응원하는 선수나 관심 있는 대회 이름을 입력하세요."
        }
        if selectedLeague != nil {
            return "팀을 탭하면 이름이 자동 입력됩니다. 응원 팀이 없으면 팀을 건너뛰고 직접 입력하세요. (리그만 선택해도 경기 추가 시 상대팀 선택이 가능합니다.)"
        }
        return "응원하는 팀이나 관심사 이름을 입력하세요."
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
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 종목 선택 (아이콘 그리드)
                Section("종목 선택") {
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
                                    
                                    Text(type.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(sportType == type ? .blue : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // 리그 선택 (종목에 리그가 있을 때만)
                if !leagues.isEmpty {
                    Section("리그 선택") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(leagues) { league in
                                    Button {
                                        selectedLeague = league
                                        selectedTeam = nil
                                        if name.isEmpty {
                                            name = "\(league.displayName) 관람"
                                        }
                                    } label: {
                                        Text(league.displayName)
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
                    }
                }
                
                // 팀 로고 그리드 (팀 선택이 필요한 종목 + 리그 선택 시에만 렌더링)
                if sportType.requiresTeamSelection, selectedLeague != nil, !teams.isEmpty {
                    Section("팀 선택") {
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
                                            
                                            AsyncImage(url: URL(string: team.logo_url)) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image
                                                        .resizable()
                                                        .scaledToFit()
                                                        .padding(8)
                                                case .failure:
                                                    Image(systemName: "photo")
                                                        .font(.title2)
                                                        .foregroundStyle(.white.opacity(0.8))
                                                case .empty:
                                                    ProgressView()
                                                        .tint(.white)
                                                @unknown default:
                                                    EmptyView()
                                                }
                                            }
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
                    }
                }
                
                // 팀 애칭 (팀 선택이 필요한 종목 + 팀 선택 시에만)
                if sportType.requiresTeamSelection, selectedTeam != nil {
                    Section {
                        TextField("예: 49ers, 닌자스", text: $teamNickname)
                    } header: {
                        Text("팀 애칭 (선택)")
                    } footer: {
                        Text("설정하면 경기 카드·상세 화면 등에서 공식 팀명 대신 이 이름이 표시됩니다.")
                    }
                }
                
                // 폴더 이름
                Section {
                    TextField(folderNamePlaceholder, text: $name)
                } header: {
                    Text(sportType.requiresTeamSelection ? "팀 / 폴더 이름" : "폴더 이름")
                } footer: {
                    Text(folderNameFooter)
                }
            }
            .navigationTitle(isEditing ? "폴더 편집" : "새 폴더")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "저장" : "만들기") {
                        isEditing ? updateFolder() : createFolder()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private func createFolder() {
        let folder = SportsFanFolder(
            name: name.trimmingCharacters(in: .whitespaces),
            sportType: sportType,
            orderIndex: nextOrderIndex
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
