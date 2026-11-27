import Foundation

enum Launch {
    static let freePeriod = true
    static var arguments: [String] { ProcessInfo.processInfo.arguments }
    static var testing: Bool {
        #if DEBUG
        arguments.contains("-ui-testing")
        #else
        false
        #endif
    }
    static var environment: [String: String] { testing ? ProcessInfo.processInfo.environment : [:] }
}
