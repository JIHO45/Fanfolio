//
//  SignInView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // 앱 로고 + 소개
            VStack(spacing: 20) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(spacing: 8) {
                    Text("Fanfolio")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                    
                    Text(String(localized: "auth.tagline", defaultValue: "나만의 팬 아카이브"))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                
                VStack(spacing: 6) {
                    featureRow(icon: "sportscourt", text: String(localized: "auth.feature.sportsRecord", defaultValue: "직관 경기를 기록하고 승률을 확인하세요"))
                    featureRow(icon: "theatermasks", text: String(localized: "auth.feature.cultureArchive", defaultValue: "콘서트, 뮤지컬 관람을 아카이빙하세요"))
                    featureRow(icon: "square.and.arrow.up", text: String(localized: "auth.feature.shareTickets", defaultValue: "티켓 이미지로 추억을 공유하세요"))
                }
                .padding(.top, 12)
            }
            
            Spacer()
            
            // 인증 에러 메시지
            if let errorMessage = authService.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            // 로그인 버튼들
            VStack(spacing: 14) {
                // Sign in with Apple
                SignInWithAppleButton(
                    .signIn,
                    onRequest: { request in
                        request.requestedScopes = [.fullName, .email]
                    },
                    onCompletion: { _ in
                        // AuthService의 delegate가 처리
                    }
                )
                .signInWithAppleButtonStyle(
                    colorScheme == .dark ? .white : .black
                )
                .frame(height: 52)
                .cornerRadius(14)
                .overlay {
                    // SignInWithAppleButton 위에 투명 버튼으로 AuthService 연결
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            authService.signInWithApple()
                        }
                }
                
                // 게스트 모드
                Button {
                    authService.continueAsGuest()
                } label: {
                    Text(String(localized: "auth.continueAsGuest", defaultValue: "로그인 없이 시작"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                
                Text(String(localized: "auth.guestModeDisclaimer", defaultValue: "로그인 없이도 모든 기능을 사용할 수 있습니다.\niCloud 동기화는 기기 설정에서 자동으로 작동합니다."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemBackground))
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 28)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

#Preview {
    SignInView()
        .environment(AuthService())
}
