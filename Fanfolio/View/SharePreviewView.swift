//
//  SharePreviewView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI

// MARK: - URL → UIImage 로드 (공유 이미지용, ImageRenderer는 동기 렌더링 필요)
func loadImage(from urlString: String) async -> UIImage? {
    guard let url = URL(string: urlString) else { return nil }
    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        return UIImage(data: data)
    } catch {
        return nil
    }
}

// MARK: - 공유 스타일
enum ShareStyle: String, CaseIterable {
    case light = "라이트"
    case dark = "다크"
}

// MARK: - 공유 미리보기 뷰
/// 공유 전 이미지 미리보기 + 스타일(라이트/다크) 선택 화면
struct SharePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStyle: ShareStyle = .light
    @State private var currentImage: UIImage?
    @State private var showLoadingIndicator = false
    @State private var showingActivityShareSheet = false
    
    /// 스타일에 따라 공유 이미지를 생성하는 클로저 (비동기 - 로고 등 네트워크 이미지 로드 지원)
    let generateImage: (ShareStyle) async -> UIImage?
    
    /// 빠르게 완료되면 로딩 UI를 보여주지 않기 위한 지연 시간 (ms)
    private static let loadingDelayMs: UInt64 = 200
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 어두운 배경 (이미지가 잘 보이도록)
                Color(red: 0.06, green: 0.06, blue: 0.08)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // ── 스타일 선택 ──
                    Picker("스타일", selection: $selectedStyle) {
                        ForEach(ShareStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    
                    // ── 이미지 프리뷰 ──
                    ScrollView {
                        if let image = currentImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 20)
                        } else if showLoadingIndicator {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(.white)
                                Text("이미지 생성 중...")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .padding(.top, 80)
                        }
                        // 200ms 이내 완료 시 아무것도 안 보임 (깜빡임 방지)
                    }
                    
                    // ── 하단 버튼 ──
                    Button {
                        showingActivityShareSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body.weight(.semibold))
                            Text("공유하기")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(currentImage == nil)
                    .opacity(currentImage == nil ? 0.5 : 1)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("공유 미리보기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .onChange(of: selectedStyle) { _, style in
                showLoadingIndicator = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    currentImage = nil
                }
                Task { @MainActor in
                    await runGeneration(style: style)
                }
            }
            .task {
                await runGeneration(style: selectedStyle)
            }
            .sheet(isPresented: $showingActivityShareSheet) {
                if let currentImage {
                    FanfolioShareSheet(items: [currentImage])
                }
            }
        }
    }
    
    /// 이미지 생성 + 지연 로딩 (빠르면 로딩 UI 미표시)
    private func runGeneration(style: ShareStyle) async {
        showLoadingIndicator = false
        
        // 200ms 후에도 이미지가 없을 때만 로딩 표시
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Self.loadingDelayMs))
            if currentImage == nil {
                showLoadingIndicator = true
            }
        }
        
        let image = await generateImage(style)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            currentImage = image
            showLoadingIndicator = false
        }
    }
}

// MARK: - 공통 공유 시트 (UIActivityViewController)
struct FanfolioShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 공통 티켓 점선 Shape
struct ShareTicketDashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
