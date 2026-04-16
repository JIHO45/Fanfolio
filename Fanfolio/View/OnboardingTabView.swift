//
//  OnboardingTabView.swift
//  Fanfolio
//
//  첫 실행 시 전체 화면 페이지 스타일로 앱 기능을 소개합니다.
//

import SwiftUI

struct OnboardingTabView: View {
    @Binding var hasCompletedWelcome: Bool
    @State private var currentPage = 0

    private let pageCount = 4
    private var lastPageIndex: Int { pageCount - 1 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(String(localized: "welcome.title", defaultValue: "Fanfolio 시작하기"))
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(String(localized: "welcome.subtitle", defaultValue: "직관과 공연 기록을 한곳에 모아보세요."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 4)

                TabView(selection: $currentPage) {
                    OnboardingPage(
                        icon: "folder.badge.plus",
                        iconColor: .blue,
                        title: String(localized: "welcome.step1.title", defaultValue: "폴더 만들기"),
                        detail: String(localized: "welcome.step1.detail", defaultValue: "사이드바에서 스포츠 팀이나 문화 관심사 폴더를 추가합니다.")
                    )
                    .tag(0)

                    OnboardingPage(
                        icon: "calendar.badge.plus",
                        iconColor: .orange,
                        title: String(localized: "welcome.step2.title", defaultValue: "경기·관람 기록"),
                        detail: String(localized: "welcome.step2.detail", defaultValue: "경기를 불러오거나 직접 입력하고, 사진과 메모를 남깁니다.")
                    )
                    .tag(1)

                    OnboardingPage(
                        icon: "ticket",
                        iconColor: .purple,
                        title: String(localized: "welcome.step3.title", defaultValue: "티켓 갤러리"),
                        detail: String(localized: "welcome.step3.detail", defaultValue: "저장한 티켓 이미지는 갤러리에서 모아 볼 수 있습니다.")
                    )
                    .tag(2)

                    OnboardingPage(
                        icon: "map.fill",
                        iconColor: .teal,
                        title: String(localized: "onboarding.map.title", defaultValue: "직관 지도"),
                        detail: String(localized: "onboarding.map.detail", defaultValue: "방문한 구장을 지도에서 모아 보고, 원정 여정을 한눈에 확인하세요.")
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Group {
                    if currentPage == lastPageIndex {
                        VStack(spacing: 16) {
                            Text(String(localized: "welcome.icloud.hint", defaultValue: "iCloud에 로그인되어 있으면 기기 간 동기화를 사용할 수 있습니다."))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)

                            Button {
                                completeWelcome()
                            } label: {
                                Text(String(localized: "welcome.start", defaultValue: "시작하기"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    } else {
                        Text(String(localized: "onboarding.swipeHint", defaultValue: "옆으로 넘겨 계속하기"))
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(minHeight: 140)
                .animation(.easeInOut(duration: 0.2), value: currentPage)
            }

            Button {
                completeWelcome()
            } label: {
                Text(String(localized: "onboarding.skip", defaultValue: "건너뛰기"))
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .padding(.trailing, 20)
            .accessibilityHint(String(localized: "onboarding.skip.hint", defaultValue: "소개를 건너뛰고 메인 화면으로 이동합니다."))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func completeWelcome() {
        withAnimation(.easeInOut(duration: 0.25)) {
            hasCompletedWelcome = true
        }
    }
}

private struct OnboardingPage: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingTabView(hasCompletedWelcome: .constant(false))
}
