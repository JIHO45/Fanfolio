//
//  SettingsView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import PhotosUI

struct SettingsView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    
    @State private var editingName = false
    @State private var nameInput = ""
    @State private var showingLogoutAlert = false
    @State private var showingDeleteAccountAlert = false
    
    // 프로필 사진
    @State private var selectedPhoto: PhotosPickerItem?
    @AppStorage("profileImageData") private var profileImageData: Data?
    
    var body: some View {
        NavigationStack {
            List {
                profileSection
                accountSection
                aboutSection
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                loadProfilePhoto(from: newValue)
            }
        }
    }
    
    // MARK: - 프로필 섹션
    private var profileSection: some View {
        Section {
            // 프로필 사진
            HStack {
                Spacer()
                
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        if let data = profileImageData,
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 80, height: 80)
                                .foregroundStyle(.gray)
                        }
                        
                        Image(systemName: "camera.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .blue)
                    }
                }
                
                Spacer()
            }
            .listRowBackground(Color.clear)
            
            // 이름
            if editingName {
                HStack {
                    TextField("이름", text: $nameInput)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("저장") {
                        let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            authService.updateUserName(trimmed)
                        }
                        editingName = false
                    }
                    .fontWeight(.semibold)
                }
            } else {
                HStack {
                    Text("이름")
                    Spacer()
                    Text(authService.userName.isEmpty ? "미설정" : authService.userName)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        nameInput = authService.userName
                        editingName = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            // 이메일 (Apple ID로 로그인한 경우)
            if authService.isSignedIn && !authService.userEmail.isEmpty {
                HStack {
                    Text("이메일")
                    Spacer()
                    Text(authService.userEmail)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("프로필")
        }
    }
    
    // MARK: - 계정 섹션
    private var accountSection: some View {
        Section {
            // iCloud 동기화 상태
            HStack {
                Label("iCloud 동기화", systemImage: "icloud")
                Spacer()
                if FileManager.default.ubiquityIdentityToken != nil {
                    Text("연결됨")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Text("연결 안 됨")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }
            
            // 로그인 상태 표시
            HStack {
                Label("로그인", systemImage: "person.badge.key")
                Spacer()
                Text(authService.isSignedIn ? "Apple ID" : "게스트")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            
            // 로그아웃
            Button {
                showingLogoutAlert = true
            } label: {
                Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(.red)
            }
            .alert("로그아웃", isPresented: $showingLogoutAlert) {
                Button("취소", role: .cancel) {}
                Button("로그아웃", role: .destructive) {
                    authService.signOut()
                    dismiss()
                }
            } message: {
                Text("로그아웃하면 로그인 화면으로 돌아갑니다. 기록 데이터는 기기에 유지됩니다.")
            }
            
            // 계정 삭제
            if authService.isSignedIn {
                Button {
                    showingDeleteAccountAlert = true
                } label: {
                    Label("계정 삭제", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .alert("계정 삭제", isPresented: $showingDeleteAccountAlert) {
                    Button("취소", role: .cancel) {}
                    Button("삭제", role: .destructive) {
                        profileImageData = nil
                        authService.deleteAccount()
                        dismiss()
                    }
                } message: {
                    Text("계정을 삭제하면 프로필 정보가 초기화됩니다. 기록 데이터는 기기에 유지됩니다.")
                }
            }
        } header: {
            Text("계정")
        } footer: {
            Text("iCloud 동기화는 기기의 iCloud 계정으로 자동 작동합니다. 설정 > Apple ID > iCloud에서 확인할 수 있습니다.")
        }
    }
    
    // MARK: - 앱 정보 섹션
    private var aboutSection: some View {
        Section {
            HStack {
                Text("버전")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("앱 정보")
        }
    }
    
    // MARK: - 사진 로드
    private func loadProfilePhoto(from item: PhotosPickerItem?) {
        Task {
            if let data = try? await item?.loadTransferable(type: Data.self) {
                // 프로필 사진은 작게 압축해서 저장
                if let uiImage = UIImage(data: data),
                   let compressed = uiImage.jpegData(compressionQuality: 0.5) {
                    profileImageData = compressed
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthService())
}
