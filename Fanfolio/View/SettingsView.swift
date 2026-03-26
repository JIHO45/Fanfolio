//
//  SettingsView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

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
            .navigationTitle(String(localized: "settings.navigationTitle", defaultValue: "설정"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.action.done", defaultValue: "완료")) { dismiss() }
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
                    TextField(String(localized: "settings.profile.nameField", defaultValue: "이름"), text: $nameInput)
                        .textFieldStyle(.roundedBorder)
                    
                    Button(String(localized: "common.action.save", defaultValue: "저장")) {
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
                    Text(String(localized: "settings.profile.nameLabel", defaultValue: "이름"))
                    Spacer()
                    Text(authService.isGuest ? String(localized: "settings.profile.guest", defaultValue: "게스트") : (authService.userName.isEmpty ? String(localized: "settings.profile.nameUnset", defaultValue: "미설정") : authService.userName))
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
                    Text(String(localized: "settings.profile.emailLabel", defaultValue: "이메일"))
                    Spacer()
                    Text(authService.userEmail)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(String(localized: "settings.section.profile", defaultValue: "프로필"))
        }
    }
    
    // MARK: - 계정 섹션
    private var accountSection: some View {
        Section {
            // iCloud 동기화 상태
            HStack {
                Label(String(localized: "settings.account.iCloudSync", defaultValue: "iCloud 동기화"), systemImage: "icloud")
                Spacer()
                if FileManager.default.ubiquityIdentityToken != nil {
                    Text(String(localized: "settings.account.connected", defaultValue: "연결됨"))
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Text(String(localized: "settings.account.disconnected", defaultValue: "연결 안 됨"))
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }
            
            // 로그인 상태 표시
            HStack {
                Label(String(localized: "settings.account.signInStatus", defaultValue: "로그인"), systemImage: "person.badge.key")
                Spacer()
                Text(authService.isSignedIn ? String(localized: "settings.account.appleID", defaultValue: "Apple ID") : String(localized: "settings.profile.guest", defaultValue: "게스트"))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            
            // 로그아웃
            Button {
                showingLogoutAlert = true
            } label: {
                Label(String(localized: "settings.account.signOut", defaultValue: "로그아웃"), systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(.red)
            }
            .alert(String(localized: "settings.logout.title", defaultValue: "로그아웃"), isPresented: $showingLogoutAlert) {
                Button(String(localized: "common.action.cancel", defaultValue: "취소"), role: .cancel) {}
                Button(String(localized: "settings.account.signOut", defaultValue: "로그아웃"), role: .destructive) {
                    authService.signOut()
                    dismiss()
                }
            } message: {
                Text(String(localized: "settings.logout.message", defaultValue: "로그인 화면으로 돌아갑니다. 직관·문화 기록과 티켓 사진 등 앱 데이터는 이 기기에서 삭제되지 않습니다."))
            }
            
            // 계정 삭제
            if authService.isSignedIn {
                Button {
                    showingDeleteAccountAlert = true
                } label: {
                    Label(String(localized: "settings.account.deleteAccount", defaultValue: "계정 삭제"), systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .alert(String(localized: "settings.deleteAccount.title", defaultValue: "계정 삭제"), isPresented: $showingDeleteAccountAlert) {
                    Button(String(localized: "common.action.cancel", defaultValue: "취소"), role: .cancel) {}
                    Button(String(localized: "common.action.delete", defaultValue: "삭제"), role: .destructive) {
                        profileImageData = nil
                        authService.deleteAccount()
                        dismiss()
                    }
                } message: {
                    Text(String(localized: "settings.deleteAccount.message", defaultValue: "이 기기에 저장된 Apple 로그인 식별 정보와 이름·이메일(저장된 경우), 프로필 사진이 제거됩니다. 직관·문화 기록과 티켓 이미지는 그대로 남습니다. iCloud에 동기화된 데이터는 기기의 iCloud 설정에서 관리됩니다."))
                }
            }
        } header: {
            Text(String(localized: "settings.section.account", defaultValue: "계정"))
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.account.footer.iCloud", defaultValue: "iCloud 동기화는 기기의 iCloud 계정으로 자동 작동합니다. 설정 > Apple ID > iCloud에서 확인할 수 있습니다."))
                Text(String(localized: "settings.account.footer.appData", defaultValue: "로그인 방식(Apple ID·게스트)과 관계없이 기록과 사진은 주로 이 기기의 앱 저장소에 남습니다. 로그아웃·계정 삭제는 앱에 저장된 로그인·프로필 정보만 지웁니다."))
            }
        }
    }
    
    // MARK: - 앱 정보 섹션
    private var aboutSection: some View {
        Section {
            HStack {
                Text(String(localized: "settings.about.version", defaultValue: "버전"))
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "settings.section.about", defaultValue: "앱 정보"))
        }
    }
    
    // MARK: - 사진 로드
    private func loadProfilePhoto(from item: PhotosPickerItem?) {
        Task {
            guard let data = try? await item?.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { return }

            let targetSize = CGSize(width: 150, height: 150)
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let resizedImage = renderer.image { _ in
                uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }

            guard let compressed = resizedImage.jpegData(compressionQuality: 0.8) else { return }

            await MainActor.run {
                profileImageData = compressed
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthService())
        .modelContainer(SportsPreviewSampleData.container)
}
