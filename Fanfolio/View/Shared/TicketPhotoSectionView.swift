//
//  TicketPhotoSectionView.swift
//  Fanfolio
//
//  AddSportsMatchView, EditSportsMatchView, AddCultureView, EditCultureView에서
//  동일하게 사용되는 티켓·QR코드 사진 섹션 공통 컴포넌트.
//

import SwiftUI
import PhotosUI

struct TicketPhotoSectionView: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var qrCodeImageData: Data?
    @Binding var qrDetected: Bool

    var body: some View {
        Section {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                if let data = qrCodeImageData,
                   let uiImage = UIImage(data: data) {
                    VStack(spacing: 8) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        if qrDetected {
                            Label(
                                String(localized: "ticket.qrDetected", defaultValue: "QR코드 자동 감지됨"),
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                        }

                        Text(String(localized: "ticket.tapToChange", defaultValue: "탭하여 변경"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label(
                        String(localized: "ticket.addPhoto", defaultValue: "티켓 · QR코드 사진 추가"),
                        systemImage: "qrcode.viewfinder"
                    )
                    .foregroundStyle(.blue)
                }
            }

            if qrCodeImageData != nil {
                Button(String(localized: "ticket.deletePhoto", defaultValue: "사진 삭제"), role: .destructive) {
                    qrCodeImageData = nil
                    selectedPhoto = nil
                    qrDetected = false
                }
            }
        } header: {
            Text(String(localized: "ticket.sectionHeader", defaultValue: "티켓 · QR코드"))
        } footer: {
            Text(String(localized: "ticket.sectionFooter", defaultValue: "사진에 QR코드가 포함되어 있으면 자동으로 감지하여 QR 영역만 추출합니다."))
        }
    }
}
