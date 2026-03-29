//
//  TicketImageStore.swift
//  Fanfolio
//
//  Created by Cursor on 3/14/26.
//

import Foundation
import UIKit
import os.log

struct TicketImageFiles {
    let ticketID: UUID
    let imagePath: String
    let thumbnailPath: String
}

enum TicketImageStore {
    private static let directoryName = "TicketImages"
    /// 리스트·그리드용 썸네일 (긴 변)
    private static let thumbnailLongEdge: CGFloat = 400
    private static let thumbnailJPEGQuality: CGFloat = 0.7
    /// 상세·공유 소스 마스터 (긴 변)
    private static let masterLongEdge: CGFloat = 2048
    private static let masterJPEGQuality: CGFloat = 0.8
    
    static func save(image: UIImage, ticketID: UUID = UUID()) throws -> TicketImageFiles {
        try ensureDirectoryExists()
        
        let baseName = ticketID.uuidString
        let imagePath = "\(directoryName)/\(baseName)_master.jpg"
        let thumbnailPath = "\(directoryName)/\(baseName)_thumb.jpg"
        let imageURL = try url(forRelativePath: imagePath)
        let thumbnailURL = try url(forRelativePath: thumbnailPath)
        
        let master = downscaleForStorage(image, maxLongEdge: masterLongEdge)
        guard let imageData = master.jpegData(compressionQuality: masterJPEGQuality) else {
            throw TicketImageStoreError.encodingFailed
        }
        try imageData.write(to: imageURL, options: .atomic)
        
        let thumbnail = downscaleForStorage(image, maxLongEdge: thumbnailLongEdge)
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: thumbnailJPEGQuality) else {
            try? FileManager.default.removeItem(at: imageURL)
            throw TicketImageStoreError.thumbnailEncodingFailed
        }
        try thumbnailData.write(to: thumbnailURL, options: .atomic)
        
        Logger.data.info("Saved ticket image \(baseName, privacy: .public)")
        return TicketImageFiles(
            ticketID: ticketID,
            imagePath: imagePath,
            thumbnailPath: thumbnailPath
        )
    }
    
    static func loadImage(path: String) -> UIImage? {
        guard let url = try? url(forRelativePath: path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }
    
    static func imageExists(path: String) -> Bool {
        guard let url = try? url(forRelativePath: path) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    static func delete(paths: [String]) {
        let uniquePaths = Array(Set(paths.filter { !$0.isEmpty }))
        for path in uniquePaths {
            guard let url = try? url(forRelativePath: path) else { continue }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                Logger.data.error("Failed to delete ticket asset at \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    static func totalSize() -> Int64 {
        guard let directoryURL = try? directoryURL(),
              let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return 0
        }
        
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = values.fileSize else { continue }
            total += Int64(fileSize)
        }
        return total
    }
    
    static func url(forRelativePath path: String) throws -> URL {
        try documentsDirectoryURL().appendingPathComponent(path, isDirectory: false)
    }
    
    private static func ensureDirectoryExists() throws {
        let directoryURL = try directoryURL()
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
    
    private static func directoryURL() throws -> URL {
        try documentsDirectoryURL().appendingPathComponent(directoryName, isDirectory: true)
    }
    
    private static func documentsDirectoryURL() throws -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw TicketImageStoreError.documentsDirectoryUnavailable
        }
        return url
    }
    
    /// 긴 변 기준으로 축소. 이미 작으면 원본 반환.
    private static func downscaleForStorage(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        let longEdge = max(width, height)
        guard longEdge > maxLongEdge else { return image }
        let scale = maxLongEdge / longEdge
        let newSize = CGSize(width: floor(width * scale), height: floor(height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

enum TicketImageStoreError: LocalizedError {
    case documentsDirectoryUnavailable
    case encodingFailed
    case thumbnailEncodingFailed
    
    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            return String(localized: "error.storage.documentsUnavailable", defaultValue: "문서 저장소를 찾을 수 없습니다.")
        case .encodingFailed:
            return String(localized: "ticket.error.saveImageFailed", defaultValue: "티켓 이미지를 저장할 수 없습니다.")
        case .thumbnailEncodingFailed:
            return String(localized: "ticket.error.thumbnailFailed", defaultValue: "티켓 썸네일을 생성하지 못했습니다.")
        }
    }
}
