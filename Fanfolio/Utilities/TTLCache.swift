//
//  TTLCache.swift
//  Fanfolio
//
//  TTL(Time-To-Live) 기반 인메모리 캐시.
//  NSLock으로 내부 동기화를 처리하므로 어떤 actor에서든 안전하게 사용 가능합니다.
//

import Foundation

private struct CacheEntry<Value>: Sendable where Value: Sendable {
    let value: Value
    let expiresAt: Date
    var isExpired: Bool { Date() > expiresAt }
}

/// 범용 TTL 캐시. NSLock 기반 내부 동기화로 스레드 안전합니다.
final class TTLCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {

    private let lock = NSLock()
    nonisolated(unsafe) private var storage: [Key: CacheEntry<Value>] = [:]

    let ttl: TimeInterval

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    // MARK: - 읽기

    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = storage[key] else { return nil }
        if entry.isExpired {
            storage.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    // MARK: - 쓰기

    func set(_ key: Key, value: Value) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = CacheEntry(value: value, expiresAt: Date().addingTimeInterval(ttl))
    }

    // MARK: - 삭제

    func remove(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }

    /// 만료된 항목만 정리 (메모리 최적화 시 호출)
    func purgeExpired() {
        lock.lock()
        defer { lock.unlock() }
        storage = storage.filter { !$0.value.isExpired }
    }
}
