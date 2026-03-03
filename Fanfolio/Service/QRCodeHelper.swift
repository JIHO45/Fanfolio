//
//  QRCodeHelper.swift
//  Fanfolio
//
//  Created by 박지호 on 2/15/26.
//

import UIKit
import Vision

/// 이미지에서 QR/바코드를 자동 감지하고 해당 영역만 크롭하는 유틸리티
enum QRCodeHelper {
    /// 이미지 데이터에서 QR/바코드 영역을 감지하여 크롭된 이미지 데이터를 반환
    /// - Parameter imageData: 원본 이미지 데이터
    /// - Returns: (크롭된 이미지 데이터, QR 감지 여부) 튜플. QR 미감지 시 원본 반환.
    static func detectAndCrop(from imageData: Data) async -> (data: Data, detected: Bool) {
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            return (imageData, false)
        }
        
        // Vision 바코드 감지 요청
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr, .ean13, .ean8, .code128, .code39, .pdf417, .aztec, .dataMatrix]
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            return (imageData, false)
        }
        
        guard let results = request.results, !results.isEmpty else {
            return (imageData, false)
        }
        
        // 가장 큰 (가장 신뢰도 높은) 바코드 선택
        let bestResult = results.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }) ?? results[0]
        
        // boundingBox는 정규화된 좌표 (0~1), 원점은 좌하단. 딱 QR 사이즈에 맞게 크롭
        let bbox = bestResult.boundingBox
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        // 최소 패딩만 (스캔 안정성을 위해 픽셀 4~8 정도)
        let minPaddingPx: CGFloat = 6
        let paddingX = min(minPaddingPx, bbox.width * imageWidth * 0.1)
        let paddingY = min(minPaddingPx, bbox.height * imageHeight * 0.1)
        
        let x = max(0, (bbox.origin.x * imageWidth) - paddingX)
        let y = max(0, (1 - bbox.origin.y - bbox.height) * imageHeight - paddingY)
        let width = min(imageWidth - x, (bbox.width * imageWidth) + paddingX * 2)
        let height = min(imageHeight - y, (bbox.height * imageHeight) + paddingY * 2)
        
        let cropRect = CGRect(x: x, y: y, width: width, height: height)
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return (imageData, false)
        }
        
        let croppedImage = UIImage(cgImage: croppedCGImage)
        
        // PNG으로 저장 (QR은 선명도가 중요)
        if let croppedData = croppedImage.pngData() {
            return (croppedData, true)
        }
        
        return (imageData, false)
    }
}
