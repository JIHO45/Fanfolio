//
//  ArchivePhotoStore.swift
//  Fanfolio
//
//  직관/현장 사진을 Document 상대 경로로 저장. DB에는 상대 경로만 저장해
//  앱 업데이트 후에도 이미지가 깨지지 않도록 함.
//

import Foundation
import UIKit
import os.log

enum ArchivePhotoFolder {
    case match   // MatchPhotos/
    case culture // CulturePhotos/
    
    var directoryName: String {
        switch self {
        case .match:   return "MatchPhotos"
        case .culture: return "CulturePhotos"
        }
    }
}

enum ArchivePhotoStore {
    private static let maxWidth: CGFloat = 1024
    private static let jpegQuality: CGFloat = 0.8
    
    /// 원본 Data를 다운샘플(가로 1024px) + JPEG 0.8로 저장 후 **상대 경로** 반환.
    static func savePhoto(_ imageData: Data, itemID: UUID, index: Int, folder: ArchivePhotoFolder) throws -> String {
        try ensureDirectoryExists(folder: folder)
        
        guard let image = UIImage(data: imageData) else {
            throw ArchivePhotoStoreError.invalidImageData
        }
        let resized = downscale(image, maxWidth: maxWidth)
        guard let data = resized.jpegData(compressionQuality: jpegQuality) else {
            throw ArchivePhotoStoreError.encodingFailed
        }
        
        let fileName = "\(itemID.uuidString)_\(index).jpg"
        let relativePath = "\(folder.directoryName)/\(fileName)"
        let fileURL = try url(forRelativePath: relativePath)
        try data.write(to: fileURL, options: .atomic)
        
        Logger.data.info("Saved archive photo \(relativePath, privacy: .public)")
        return relativePath
    }
    
    /// 상대 경로로 저장된 이미지 로드. Document 경로는 런타임에 붙임.
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
                Logger.data.error("Failed to delete archive photo at \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    static func url(forRelativePath path: String) throws -> URL {
        try documentsDirectoryURL().appendingPathComponent(path, isDirectory: false)
    }
    
    private static func ensureDirectoryExists(folder: ArchivePhotoFolder) throws {
        let dirURL = try directoryURL(folder: folder)
        if !FileManager.default.fileExists(atPath: dirURL.path) {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
    }
    
    private static func directoryURL(folder: ArchivePhotoFolder) throws -> URL {
        try documentsDirectoryURL().appendingPathComponent(folder.directoryName, isDirectory: true)
    }
    
    private static func documentsDirectoryURL() throws -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ArchivePhotoStoreError.documentsDirectoryUnavailable
        }
        return url
    }
    
    private static func downscale(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
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
}

enum ArchivePhotoStoreError: LocalizedError {
    case documentsDirectoryUnavailable
    case invalidImageData
    case encodingFailed
    
    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            return String(localized: "error.storage.documentsUnavailable", defaultValue: "문서 저장소를 찾을 수 없습니다.")
        case .invalidImageData:
            return String(localized: "error.image.readFailed", defaultValue: "이미지 데이터를 읽을 수 없습니다.")
        case .encodingFailed:
            return String(localized: "error.image.saveFailed", defaultValue: "이미지를 저장할 수 없습니다.")
        }
    }
}
