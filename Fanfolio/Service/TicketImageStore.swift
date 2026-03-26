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
    private static let thumbnailSize = CGSize(width: 270, height: 480)
    private static let maxFullWidth: CGFloat = 1024
    private static let fullImageJPEGQuality: CGFloat = 0.8
    
    static func save(image: UIImage, ticketID: UUID = UUID()) throws -> TicketImageFiles {
        try ensureDirectoryExists()
        
        let baseName = ticketID.uuidString
        let imagePath = "\(directoryName)/\(baseName).jpg"
        let thumbnailPath = "\(directoryName)/\(baseName)_thumb.jpg"
        let imageURL = try url(forRelativePath: imagePath)
        let thumbnailURL = try url(forRelativePath: thumbnailPath)
        
        let resized = downscaleForStorage(image, maxWidth: maxFullWidth)
        guard let imageData = resized.jpegData(compressionQuality: fullImageJPEGQuality) else {
            throw TicketImageStoreError.encodingFailed
        }
        try imageData.write(to: imageURL, options: .atomic)
        
        let thumbnail = makeThumbnail(from: resized, targetSize: thumbnailSize)
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.82) else {
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
    
    private static func downscaleForStorage(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        guard width > maxWidth else { return image }
        let scale = maxWidth / width
        let newSize = CGSize(width: maxWidth, height: height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    private static func makeThumbnail(from image: UIImage, targetSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        
        return renderer.image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            
            let widthRatio = targetSize.width / image.size.width
            let heightRatio = targetSize.height / image.size.height
            let scale = max(widthRatio, heightRatio)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let drawOrigin = CGPoint(
                x: (targetSize.width - drawSize.width) / 2,
                y: (targetSize.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
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
