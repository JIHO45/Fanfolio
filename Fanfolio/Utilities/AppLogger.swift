//
//  AppLogger.swift
//  Fanfolio
//
//  os.Logger 카테고리별 싱글턴 정의.
//  Xcode의 Console에서 카테고리로 필터링할 수 있습니다.
//

import Foundation
import os.log

extension Logger {
    private static let subsystem = "com.fanfolio"

    static let api     = Logger(subsystem: subsystem, category: "API")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let auth    = Logger(subsystem: subsystem, category: "Auth")
    static let data    = Logger(subsystem: subsystem, category: "Data")
}
