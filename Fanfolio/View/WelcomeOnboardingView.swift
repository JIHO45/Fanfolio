//
//  WelcomeOnboardingView.swift
//  Fanfolio
//
//  첫 실행 시 앱 사용 흐름을 짧게 안내합니다.
//

import SwiftUI

struct WelcomeOnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(String(localized: "welcome.subtitle", defaultValue: "직관과 공연 기록을 한곳에 모아보세요."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 16) {
                        welcomeRow(
                            icon: "folder.badge.plus",
                            color: .blue,
                            title: String(localized: "welcome.step1.title", defaultValue: "폴더 만들기"),
                            detail: String(localized: "welcome.step1.detail", defaultValue: "사이드바에서 스포츠 팀이나 문화 관심사 폴더를 추가합니다.")
                        )
                        welcomeRow(
                            icon: "calendar.badge.plus",
                            color: .orange,
                            title: String(localized: "welcome.step2.title", defaultValue: "경기·관람 기록"),
                            detail: String(localized: "welcome.step2.detail", defaultValue: "경기를 불러오거나 직접 입력하고, 사진과 메모를 남깁니다.")
                        )
                        welcomeRow(
                            icon: "ticket",
                            color: .purple,
                            title: String(localized: "welcome.step3.title", defaultValue: "티켓 갤러리"),
                            detail: String(localized: "welcome.step3.detail", defaultValue: "저장한 티켓 이미지는 갤러리에서 모아 볼 수 있습니다.")
                        )
                    }
                    .padding(.top, 8)

                    Text(String(localized: "welcome.icloud.hint", defaultValue: "iCloud에 로그인되어 있으면 기기 간 동기화를 사용할 수 있습니다."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .navigationTitle(String(localized: "welcome.title", defaultValue: "Fanfolio 시작하기"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "welcome.start", defaultValue: "시작하기")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func welcomeRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    WelcomeOnboardingView()
}
