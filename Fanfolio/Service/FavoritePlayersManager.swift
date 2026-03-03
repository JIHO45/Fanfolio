//
//  FavoritePlayersManager.swift
//  Fanfolio
//
//  UserDefaults 기반 선수 즐겨찾기 관리. [String] 형태의 선수 ID 배열을 저장합니다.
//
//  핵심 설계: @Observable은 stored property만 변경을 추적합니다.
//  favoriteIDs를 stored property로 선언하고, 변경 시 UserDefaults에 동기화합니다.

import Foundation
import Observation

@Observable
final class FavoritePlayersManager {

    static let shared = FavoritePlayersManager()

    private let storageKey = "favoritePlayerIDs"

    /// 즐겨찾기된 선수 ID 배열 - stored property이므로 @Observable이 변경을 감지합니다.
    private(set) var favoriteIDs: [String]

    private init() {
        if let data = UserDefaults.standard.data(forKey: "favoritePlayerIDs"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.favoriteIDs = decoded
        } else {
            self.favoriteIDs = []
        }
    }

    // MARK: - 공개 인터페이스

    func isFavorite(_ playerID: String) -> Bool {
        favoriteIDs.contains(playerID)
    }

    func toggleFavorite(_ playerID: String) {
        if let index = favoriteIDs.firstIndex(of: playerID) {
            favoriteIDs.remove(at: index)
        } else {
            favoriteIDs.append(playerID)
        }
        persist()
    }

    func addFavorite(_ playerID: String) {
        guard !isFavorite(playerID) else { return }
        favoriteIDs.append(playerID)
        persist()
    }

    func removeFavorite(_ playerID: String) {
        favoriteIDs.removeAll { $0 == playerID }
        persist()
    }

    // MARK: - UserDefaults 동기화

    private func persist() {
        if let encoded = try? JSONEncoder().encode(favoriteIDs) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
