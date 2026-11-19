import Foundation

enum Launch {
    static let freePeriod = false
    static var arguments: [String] { ProcessInfo.processInfo.arguments }
    static var testing: Bool {
        #if DEBUG
        arguments.contains("-ui-testing")
        #else
        false
        #endif
    }
    static var isFree: Bool { freePeriod && !(testing && arguments.contains("-paid-mode")) }
    static var expired: Bool { testing && arguments.contains("-expired") }
    static var opensPaywall: Bool { testing && arguments.contains("-paywall") }
    static var environment: [String: String] { testing ? ProcessInfo.processInfo.environment : [:] }
}
