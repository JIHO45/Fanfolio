//
//  LegacyArchivePhotoMigration.swift
//  Fanfolio
//
//  DB에만 있던 직관/현장 사진(photosData)을 Document 파일 + photoPaths로 1회 이전합니다.
//

import Foundation
import SwiftData
import os.log

enum LegacyArchivePhotoMigration {
    private static let completedKey = "fanfolio_legacy_photo_migration_v1"

    /// 메인 액터에서 호출. 이미 완료된 경우 즉시 반환.
    @MainActor
    static func runIfNeeded(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: completedKey) else { return }

        var changed = false
        do {
            let matches = try context.fetch(FetchDescriptor<SportsModel>())
            for match in matches {
                if migrateSportsMatch(match) { changed = true }
            }

            let events = try context.fetch(FetchDescriptor<CultureModel>())
            for event in events {
                if migrateCultureEvent(event) { changed = true }
            }

            if changed {
                try context.save()
            }
            UserDefaults.standard.set(true, forKey: completedKey)
        } catch {
            Logger.data.error("Legacy photo migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `photosData`만 있고 파일 경로가 비어 있을 때 파일로 저장 후 `photoPaths`로 옮깁니다.
    @discardableResult
    private static func migrateSportsMatch(_ match: SportsModel) -> Bool {
        guard let blobs = match.photosData, !blobs.isEmpty else { return false }
        if let paths = match.photoPaths, !paths.isEmpty {
            match.photosData = nil
            return true
        }
        let batchID = UUID()
        var newPaths: [String] = []
        for i in blobs.indices {
            if let path = try? ArchivePhotoStore.savePhoto(blobs[i], itemID: batchID, index: i, folder: .match) {
                newPaths.append(path)
            }
        }
        match.photoPaths = newPaths.isEmpty ? nil : newPaths
        match.photosData = nil
        return true
    }

    @discardableResult
    private static func migrateCultureEvent(_ event: CultureModel) -> Bool {
        guard let blobs = event.photosData, !blobs.isEmpty else { return false }
        if let paths = event.photoPaths, !paths.isEmpty {
            event.photosData = nil
            return true
        }
        let batchID = UUID()
        var newPaths: [String] = []
        for i in blobs.indices {
            if let path = try? ArchivePhotoStore.savePhoto(blobs[i], itemID: batchID, index: i, folder: .culture) {
                newPaths.append(path)
            }
        }
        event.photoPaths = newPaths.isEmpty ? nil : newPaths
        event.photosData = nil
        return true
    }
}
