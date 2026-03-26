//
//  NetworkMonitor.swift
//  Fanfolio
//
//  NWPathMonitor 기반 실시간 네트워크 상태 감지.
//  오프라인 상태에서 API 호출을 사전에 차단합니다.
//

import Foundation
import Network
import Observation
import os.log

@MainActor
@Observable
final class NetworkMonitor {

    static let shared = NetworkMonitor()

    // MARK: - 상태

    /// 현재 인터넷 연결 여부
    private(set) var isConnected: Bool = true

    /// 연결 유형 (Wi-Fi / 셀룰러 / 기타)
    private(set) var connectionType: ConnectionType = .unknown

    enum ConnectionType {
        case wifi, cellular, other, unknown

        var displayName: String {
            switch self {
            case .wifi:     return "Wi-Fi"
            case .cellular: return String(localized: "network.connection.cellular", defaultValue: "셀룰러")
            case .other:    return String(localized: "network.connection.other", defaultValue: "기타")
            case .unknown:  return String(localized: "network.connection.unknown", defaultValue: "알 수 없음")
            }
        }
    }

    // MARK: - 내부

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let connected = path.status == .satisfied
                self?.isConnected = connected

                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = .cellular
                } else if connected {
                    self?.connectionType = .other
                } else {
                    self?.connectionType = .unknown
                }

                Logger.network.info(
                    "Network: \(connected ? "connected" : "disconnected") via \(self?.connectionType.displayName ?? "unknown")"
                )
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.fanfolio.network", qos: .utility))
    }

    deinit {
        monitor.cancel()
    }
}
