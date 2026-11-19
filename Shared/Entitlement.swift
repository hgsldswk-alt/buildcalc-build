import Foundation

struct Entitlement: Codable, Equatable, Sendable {
    var firstOpen: Date
    var proStartedAt: Date?
    var trialClaimedAt: Date?
    var latestSeen: Date?
    var purchasedPro = false

    var trialStart: Date {
        let local = proStartedAt ?? firstOpen
        return trialClaimedAt.map { min($0, local) } ?? local
    }

    var trialEnd: Date { trialStart.addingTimeInterval(30 * 86_400) }

    func hasPro(at now: Date, free: Bool = Launch.isFree) -> Bool {
        if free || purchasedPro { return true }
        let checkpoint = latestSeen ?? trialStart
        guard now >= trialStart, now >= checkpoint.addingTimeInterval(-600) else { return false }
        return max(now, checkpoint) < trialEnd
    }

    mutating func observe(_ now: Date) { latestSeen = max(now, latestSeen ?? now) }
}
