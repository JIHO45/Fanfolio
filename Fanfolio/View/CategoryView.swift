//
//  CategoryView.swift
//  Fanfolio
//
//  Created by 박지호 on 12/14/25.
//

import SwiftUI
import SwiftData

struct CategoryView: View {
    @Query(sort: \SportsFanFolder.orderIndex) private var sportsFolders: [SportsFanFolder]
    @Query(sort: \CultureFanFolder.orderIndex) private var cultureFolders: [CultureFanFolder]
    
    @State private var isSidebarVisible: Bool = false
    @State private var selectedSportsFolder: SportsFanFolder?
    @State private var selectedCultureFolder: CultureFanFolder?
    @State private var activeSection: ArchiveCategory = .sports
    @State private var hasRestoredState = false
    
    // 마지막 상태 저장
    @AppStorage("lastSection") private var savedSection: String = ArchiveCategory.sports.rawValue
    @AppStorage("lastFolderName") private var savedFolderName: String = ""
    @AppStorage("lastFolderType") private var savedFolderType: String = "sports"
    
    var body: some View {
        ZStack(alignment: .leading) {
            MainContentView(
                isSidebarVisible: $isSidebarVisible,
                selectedSportsFolder: selectedSportsFolder,
                selectedCultureFolder: selectedCultureFolder,
                activeSection: activeSection
            )
            .disabled(isSidebarVisible)
            
            if isSidebarVisible {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            isSidebarVisible = false
                        }
                    }
                    .transition(.opacity)
            }
            
            SidebarView(
                isSidebarVisible: $isSidebarVisible,
                selectedSportsFolder: $selectedSportsFolder,
                selectedCultureFolder: $selectedCultureFolder,
                activeSection: $activeSection
            )
            .frame(width: 270)
            .offset(x: isSidebarVisible ? 0 : -270)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSidebarVisible)
        .task {
            // 앱 시작 시 마지막 상태 복원 (한 번만)
            guard !hasRestoredState else { return }
            hasRestoredState = true
            
            if let section = ArchiveCategory(rawValue: savedSection) {
                activeSection = section
            }
            if !savedFolderName.isEmpty {
                if savedFolderType == "culture" {
                    selectedCultureFolder = cultureFolders.first { $0.name == savedFolderName }
                } else {
                    selectedSportsFolder = sportsFolders.first { $0.name == savedFolderName }
                }
            }
        }
        .onChange(of: selectedSportsFolder) { _, folder in
            if folder != nil {
                savedFolderName = folder?.name ?? ""
                savedFolderType = "sports"
            } else if selectedCultureFolder == nil {
                savedFolderName = ""
            }
        }
        .onChange(of: selectedCultureFolder) { _, folder in
            if folder != nil {
                savedFolderName = folder?.name ?? ""
                savedFolderType = "culture"
            } else if selectedSportsFolder == nil {
                savedFolderName = ""
            }
        }
        .onChange(of: activeSection) { _, section in
            savedSection = section.rawValue
        }
    }
}

// MARK: - Sidebar
struct SidebarView: View {
    @Query(sort: \SportsFanFolder.orderIndex) private var sportsFolders: [SportsFanFolder]
    @Query(sort: \CultureFanFolder.orderIndex) private var cultureFolders: [CultureFanFolder]
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    
    @Binding var isSidebarVisible: Bool
    @Binding var selectedSportsFolder: SportsFanFolder?
    @Binding var selectedCultureFolder: CultureFanFolder?
    @Binding var activeSection: ArchiveCategory
    
    // 스포츠 폴더 상태
    @State private var showingAddSportsFolderSheet = false
    @State private var sportsFolderForEditSheet: SportsFanFolder?
    @State private var sportsFolderToDelete: SportsFanFolder?
    @State private var showingSportsDeleteAlert = false
    
    // 문화 폴더 상태
    @State private var showingAddCultureFolderSheet = false
    @State private var cultureFolderForEditSheet: CultureFanFolder?
    @State private var cultureFolderToDelete: CultureFanFolder?
    @State private var showingCultureDeleteAlert = false
    
    // 설정 시트
    @State private var showingSettingsSheet = false
    
    // 프로필 사진
    @AppStorage("profileImageData") private var profileImageData: Data?
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                // 프로필 영역
                profileSection
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        // 스포츠 섹션
                        sportsSectionHeader
                        sportsFolderList
                        
                        Divider()
                            .padding(.vertical, 12)
                        
                        // 문화 섹션
                        cultureSectionHeader
                        cultureFolderList
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
        }
        .shadow(color: .black.opacity(0.1), radius: 5, x: 5, y: 0)
        // 스포츠 폴더 시트
        .sheet(isPresented: $showingAddSportsFolderSheet) {
            AddFolderView(nextOrderIndex: sportsFolders.count)
        }
        .sheet(item: $sportsFolderForEditSheet) { folder in
            AddFolderView(folder: folder)
        }
        .alert("폴더 삭제", isPresented: $showingSportsDeleteAlert) {
            Button("취소", role: .cancel) {
                sportsFolderToDelete = nil
            }
            Button("삭제", role: .destructive) {
                if let folder = sportsFolderToDelete {
                    if selectedSportsFolder?.id == folder.id {
                        selectedSportsFolder = nil
                    }
                    modelContext.delete(folder)
                    sportsFolderToDelete = nil
                }
            }
        } message: {
            if let folder = sportsFolderToDelete {
                Text("'\(folder.displayName)' 폴더와 \(folder.matches.count)개의 경기 기록이 모두 삭제됩니다. 이 작업은 되돌릴 수 없습니다.")
            }
        }
        // 문화 폴더 시트
        .sheet(isPresented: $showingAddCultureFolderSheet) {
            AddCultureFolderView(nextOrderIndex: cultureFolders.count)
        }
        .sheet(item: $cultureFolderForEditSheet) { folder in
            AddCultureFolderView(folder: folder)
        }
        .alert("폴더 삭제", isPresented: $showingCultureDeleteAlert) {
            Button("취소", role: .cancel) {
                cultureFolderToDelete = nil
            }
            Button("삭제", role: .destructive) {
                if let folder = cultureFolderToDelete {
                    if selectedCultureFolder?.id == folder.id {
                        selectedCultureFolder = nil
                    }
                    modelContext.delete(folder)
                    cultureFolderToDelete = nil
                }
            }
        } message: {
            if let folder = cultureFolderToDelete {
                Text("'\(folder.name)' 폴더와 \(folder.events.count)개의 기록이 모두 삭제됩니다. 이 작업은 되돌릴 수 없습니다.")
            }
        }
    }
    
    // MARK: - 프로필
    private var profileSection: some View {
        Button {
            showingSettingsSheet = true
        } label: {
            HStack {
                if let data = profileImageData,
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(authService.userName.isEmpty ? "사용자" : authService.userName)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(authService.isSignedIn ? "Apple ID" : "게스트")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "gearshape")
                    .foregroundColor(.gray)
            }
            .padding(.top, 50)
            .padding(.bottom, 30)
            .padding(.horizontal)
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsView()
        }
    }
    
    // MARK: - 스포츠 섹션 헤더
    private var sportsSectionHeader: some View {
        HStack {
            Label("스포츠", systemImage: "sportscourt")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button {
                showingAddSportsFolderSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - 스포츠 폴더 목록
    private var sportsFolderList: some View {
        ForEach(sportsFolders) { folder in
            Button {
                selectedSportsFolder = folder
                selectedCultureFolder = nil
                activeSection = .sports
                withAnimation {
                    isSidebarVisible = false
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: folder.sportType.iconName)
                        .font(.title3)
                        .frame(width: 28)
                        .foregroundStyle(
                            selectedSportsFolder?.id == folder.id ? .blue : .secondary
                        )
                    
                    Text(folder.displayName)
                        .font(.body)
                        .fontWeight(selectedSportsFolder?.id == folder.id ? .bold : .regular)
                    
                    Spacer()
                    
                    Text("\(folder.matches.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if selectedSportsFolder?.id == folder.id {
                        Capsule()
                            .frame(width: 3, height: 20)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 8)
                .foregroundColor(selectedSportsFolder?.id == folder.id ? .blue : .primary)
            }
            .contextMenu {
                Button {
                    sportsFolderForEditSheet = folder
                } label: {
                    Label("편집", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    sportsFolderToDelete = folder
                    showingSportsDeleteAlert = true
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
        }
    }
    
    // MARK: - 문화 섹션 헤더
    private var cultureSectionHeader: some View {
        HStack {
            Label("문화", systemImage: "theatermasks")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button {
                showingAddCultureFolderSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.purple)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - 문화 폴더 목록
    private var cultureFolderList: some View {
        ForEach(cultureFolders) { folder in
            Button {
                selectedCultureFolder = folder
                selectedSportsFolder = nil
                activeSection = .culture
                withAnimation {
                    isSidebarVisible = false
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: folder.cultureType.iconName)
                        .font(.title3)
                        .frame(width: 28)
                        .foregroundStyle(
                            selectedCultureFolder?.id == folder.id ? .purple : .secondary
                        )
                    
                    Text(folder.name)
                        .font(.body)
                        .fontWeight(selectedCultureFolder?.id == folder.id ? .bold : .regular)
                    
                    Spacer()
                    
                    Text("\(folder.events.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if selectedCultureFolder?.id == folder.id {
                        Capsule()
                            .frame(width: 3, height: 20)
                            .foregroundColor(.purple)
                    }
                }
                .padding(.vertical, 8)
                .foregroundColor(selectedCultureFolder?.id == folder.id ? .purple : .primary)
            }
            .contextMenu {
                Button {
                    cultureFolderForEditSheet = folder
                } label: {
                    Label("편집", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    cultureFolderToDelete = folder
                    showingCultureDeleteAlert = true
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
        }
    }
    
}

// MARK: - Main Content
struct MainContentView: View {
    @Binding var isSidebarVisible: Bool
    var selectedSportsFolder: SportsFanFolder?
    var selectedCultureFolder: CultureFanFolder?
    var activeSection: ArchiveCategory
    
    private var navigationTitle: String {
        if let folder = selectedSportsFolder {
            return folder.displayName
        }
        if let folder = selectedCultureFolder {
            return folder.name
        }
        return activeSection.rawValue
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if let folder = selectedSportsFolder {
                    SportsView(folder: folder)
                } else if let folder = selectedCultureFolder {
                    CultureView(folder: folder)
                } else {
                    switch activeSection {
                    case .sports:
                        ContentUnavailableView(
                            "팀을 추가해보세요",
                            systemImage: "sportscourt",
                            description: Text("사이드바에서 + 버튼을 눌러\n응원하는 팀 폴더를 만들어보세요!")
                        )
                    case .culture:
                        ContentUnavailableView(
                            "관심사를 추가해보세요",
                            systemImage: "theatermasks",
                            description: Text("사이드바에서 + 버튼을 눌러\n좋아하는 아티스트 폴더를 만들어보세요!")
                        )
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation {
                            isSidebarVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
    }
}

#Preview {
    let auth = AuthService()
    auth.continueAsGuest()
    
    return CategoryView()
        .environment(auth)
        .modelContainer(SportsPreviewSampleData.container)
}
