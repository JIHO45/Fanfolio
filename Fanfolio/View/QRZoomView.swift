//
//  QRZoomView.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import SwiftUI

/// QR코드 전체 화면 확대 뷰 (입장 스캔용)
struct QRZoomView: View {
    let imageData: Data
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // 흰 배경 (스캔 시 대비 좋음)
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                if let uiImage = UIImage(data: imageData) {
                    GeometryReader { geometry in
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: min(geometry.size.width - 80, 400),
                                   maxHeight: min(geometry.size.height * 0.5, 400))
                            .padding(24)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                            .frame(maxWidth: .infinity)
                    }
                }
                
                Text(String(localized: "qr.zoom.hint", defaultValue: "입장 시 이 QR을 스캔하세요"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.gray.opacity(0.6))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .padding(20)
                }
                Spacer()
            }
        }
    }
}
