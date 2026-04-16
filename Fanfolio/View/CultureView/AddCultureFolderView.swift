//
//  AddCultureFolderView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import SwiftData

struct AddCultureFolderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    /// nil이면 새 폴더 생성, 값이 있으면 편집 모드
    let editingFolder: CultureFanFolder?
    let nextOrderIndex: Int
    
    @State private var name: String
    @State private var cultureType: CultureType
    
    private var isEditing: Bool { editingFolder != nil }
    
    init(nextOrderIndex: Int) {
        self.editingFolder = nil
        self.nextOrderIndex = nextOrderIndex
        _name = State(initialValue: "")
        _cultureType = State(initialValue: .concert)
    }
    
    init(folder: CultureFanFolder) {
        self.editingFolder = folder
        self.nextOrderIndex = folder.orderIndex
        _name = State(initialValue: folder.name)
        _cultureType = State(initialValue: folder.cultureType)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 카테고리 선택 (아이콘 그리드)
                Section(String(localized: "addFolder.section.category", defaultValue: "카테고리 선택")) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 3),
                        spacing: 12
                    ) {
                        ForEach(CultureType.allCases) { type in
                            Button {
                                cultureType = type
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: type.iconName)
                                        .font(.title2)
                                        .frame(width: 48, height: 48)
                                        .background(
                                            Circle()
                                                .fill(cultureType == type
                                                      ? Color.purple.opacity(0.15)
                                                      : Color.secondary.opacity(0.08))
                                        )
                                        .foregroundStyle(cultureType == type ? .purple : .secondary)
                                    
                                    Text(type.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(cultureType == type ? .purple : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // 폴더 이름
                Section {
                    TextField(String(localized: "addFolder.textField.placeholder", defaultValue: "예: BTS, 위키드, CGV 영화"), text: $name)
                } header: {
                    Text(String(localized: "addFolder.artistName", defaultValue: "아티스트 / 폴더 이름"))
                } footer: {
                    Text(String(localized: "addFolder.artistHint", defaultValue: "좋아하는 아티스트, 작품, 또는 관심사 이름을 입력하세요."))
                }
            }
            .navigationTitle(isEditing
                             ? String(localized: "addFolder.nav.edit", defaultValue: "폴더 편집")
                             : String(localized: "addFolder.nav.new", defaultValue: "새 폴더"))
            .navigationBarTitleDisplayMode(.inline)
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
        let folder = CultureFanFolder(
            name: name.trimmingCharacters(in: .whitespaces),
            cultureType: cultureType,
            orderIndex: nextOrderIndex
        )
        modelContext.insert(folder)
        dismiss()
    }
    
    private func updateFolder() {
        guard let folder = editingFolder else { return }
        folder.name = name.trimmingCharacters(in: .whitespaces)
        folder.cultureType = cultureType
        dismiss()
    }
}

#Preview("새 폴더") {
    AddCultureFolderView(nextOrderIndex: 0)
        .modelContainer(SportsPreviewSampleData.container)
}

#Preview("편집") {
    AddCultureFolderView(folder: CultureFanFolder(name: "BTS", cultureType: .concert))
        .modelContainer(SportsPreviewSampleData.container)
}
