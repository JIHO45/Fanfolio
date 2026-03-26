//
//  FavoritePlayersManager.swift
//  Fanfolio
//
//  UserDefaults 기반 선수 즐겨찾기 관리.
//  폴더(folderID)별로 선수 ID 목록을 분리 저장합니다.
//  저장 형식: [folderID문자열: [선수ID문자열]] (JSON)

import Foundation
import Observation

@Observable
final class FavoritePlayersManager {

    static let shared = FavoritePlayersManager()

    private let storageKey = "favoritePlayerIDsByFolder"

    /// 폴더별 즐겨찾기 선수 ID 딕셔너리 [folderID: [playerID]]
    private(set) var favoritesByFolder: [String: [String]]

    private init() {
        if let data = UserDefaults.standard.data(forKey: "favoritePlayerIDsByFolder"),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            self.favoritesByFolder = decoded
        } else {
            // 기존 전역 저장 데이터가 있으면 버리고 빈 상태로 시작
            self.favoritesByFolder = [:]
        }
    }

    // MARK: - 공개 인터페이스

    func favoriteIDs(inFolder folderID: String) -> [String] {
        favoritesByFolder[folderID] ?? []
    }

    func favoriteCount(inFolder folderID: String) -> Int {
        favoritesByFolder[folderID]?.count ?? 0
    }

    func isFavorite(_ playerID: String, inFolder folderID: String) -> Bool {
        favoritesByFolder[folderID]?.contains(playerID) ?? false
    }

    func toggleFavorite(_ playerID: String, inFolder folderID: String) {
        var ids = favoritesByFolder[folderID] ?? []
        if let index = ids.firstIndex(of: playerID) {
            ids.remove(at: index)
        } else {
            ids.append(playerID)
        }
        favoritesByFolder[folderID] = ids
        persist()
    }

    /// 폴더 삭제 시 해당 폴더의 즐겨찾기를 모두 제거합니다.
    /// 폴더를 삭제할 때 반드시 호출해 고아 데이터를 방지하세요.
    func removeFavorites(forFolder folderID: String) {
        guard favoritesByFolder[folderID] != nil else { return }
        favoritesByFolder.removeValue(forKey: folderID)
        persist()
    }

    // MARK: - UserDefaults 동기화

    private func persist() {
        if let encoded = try? JSONEncoder().encode(favoritesByFolder) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
