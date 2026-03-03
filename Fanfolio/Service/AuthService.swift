//
//  AuthService.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import Foundation
import AuthenticationServices
import os.log

/// Sign in with Apple 인증 상태를 관리하는 서비스.
/// iCloud 동기화(CloudKit)는 기기 iCloud 계정으로 자동 작동하므로 이 서비스와 독립적.
/// 이 서비스는 앱 내 프로필(이름 표시, 향후 소셜 기능)을 위한 것.
@Observable
final class AuthService: NSObject {

    // MARK: - 상태
    var isSignedIn: Bool = false
    var isGuest: Bool = false
    var userName: String = ""
    var userEmail: String = ""

    /// 인증 실패 시 사용자에게 표시할 에러 메시지
    var errorMessage: String? = nil
    
    // MARK: - 저장 키 (AppStorage 호환)
    private static let userIDKey = "appleUserID"
    private static let userNameKey = "appleUserName"
    private static let userEmailKey = "appleUserEmail"
    private static let isGuestKey = "isGuestMode"
    
    override init() {
        super.init()
        restoreState()
    }
    
    // MARK: - 기존 상태 복원
    /// 앱 시작 시 저장된 인증 상태를 복원한다.
    private func restoreState() {
        let defaults = UserDefaults.standard
        
        // 게스트 모드 확인
        if defaults.bool(forKey: Self.isGuestKey) {
            isGuest = true
            userName = defaults.string(forKey: Self.userNameKey) ?? "게스트"
            return
        }
        
        // Apple ID 인증 상태 확인
        guard let userID = defaults.string(forKey: Self.userIDKey) else {
            isSignedIn = false
            return
        }
        
        userName = defaults.string(forKey: Self.userNameKey) ?? ""
        userEmail = defaults.string(forKey: Self.userEmailKey) ?? ""
        
        // Apple 서버에 인증 상태 확인
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userID) { [weak self] state, _ in
            DispatchQueue.main.async {
                switch state {
                case .authorized:
                    self?.isSignedIn = true
                case .revoked, .notFound:
                    self?.clearState()
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - Sign in with Apple 실행
    func signInWithApple() {
        errorMessage = nil
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        Logger.auth.info("Sign in with Apple initiated")
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }
    
    // MARK: - 게스트 모드
    func continueAsGuest() {
        isGuest = true
        userName = "게스트"
        UserDefaults.standard.set(true, forKey: Self.isGuestKey)
        UserDefaults.standard.set("게스트", forKey: Self.userNameKey)
    }
    
    // MARK: - 이름 업데이트
    func updateUserName(_ name: String) {
        userName = name
        UserDefaults.standard.set(name, forKey: Self.userNameKey)
    }
    
    // MARK: - 로그아웃
    func signOut() {
        clearState()
    }
    
    // MARK: - 계정 삭제
    func deleteAccount() {
        clearState()
    }
    
    private func clearState() {
        isSignedIn = false
        isGuest = false
        userName = ""
        userEmail = ""
        
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.userIDKey)
        defaults.removeObject(forKey: Self.userNameKey)
        defaults.removeObject(forKey: Self.userEmailKey)
        defaults.removeObject(forKey: Self.isGuestKey)
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AuthService: ASAuthorizationControllerDelegate {
    
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }
        
        let userID = credential.user
        
        // Apple은 이름/이메일을 최초 로그인 시에만 제공
        let fullName = [credential.fullName?.familyName, credential.fullName?.givenName]
            .compactMap { $0 }
            .joined(separator: "")
        let email = credential.email ?? ""
        
        let defaults = UserDefaults.standard
        defaults.set(userID, forKey: Self.userIDKey)
        
        // 이름이 비어있지 않을 때만 저장 (재로그인 시 이전 이름 유지)
        if !fullName.isEmpty {
            defaults.set(fullName, forKey: Self.userNameKey)
            userName = fullName
        } else {
            userName = defaults.string(forKey: Self.userNameKey) ?? ""
        }
        
        if !email.isEmpty {
            defaults.set(email, forKey: Self.userEmailKey)
            userEmail = email
        } else {
            userEmail = defaults.string(forKey: Self.userEmailKey) ?? ""
        }
        
        // 게스트 모드 해제
        defaults.removeObject(forKey: Self.isGuestKey)
        isGuest = false
        isSignedIn = true
    }
    
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        // ASAuthorizationError.canceled(1001)는 사용자가 직접 취소한 것이므로 에러 표시 불필요
        let authError = error as? ASAuthorizationError
        guard authError?.code != .canceled else {
            Logger.auth.info("Sign in with Apple cancelled by user")
            return
        }

        Logger.auth.error("Sign in with Apple failed: \(error.localizedDescription)")

        DispatchQueue.main.async {
            self.errorMessage = "로그인에 실패했습니다. 다시 시도해주세요."
        }
    }
}
