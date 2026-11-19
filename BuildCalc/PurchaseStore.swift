import Foundation
import Combine
import Security
import StoreKit

private actor TrialVault {
    private let key: [String: String] = [kSecClass as String: kSecClassGenericPassword as String,
                                         kSecAttrService as String: "com.hgsldswk.buildcalc.entitlement",
                                         kSecAttrAccount as String: "v1"]

    func load(started: Date, now: Date, verifiedTrial: Date?, free: Bool) throws -> Entitlement {
        var query: [String: Any] = key
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var entry: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &entry)
        var value: Entitlement
        if status == errSecSuccess, let data = entry as? Data {
            value = try JSONDecoder().decode(Entitlement.self, from: data)
        } else if status == errSecItemNotFound {
            value = Entitlement(firstOpen: started)
        } else { throw VaultError.unavailable }
        if !free, value.proStartedAt == nil { value.proStartedAt = min(started, now) }
        if let verifiedTrial { value.trialClaimedAt = min(value.trialClaimedAt ?? verifiedTrial, verifiedTrial) }
        value.purchasedPro = false
        value.observe(now)
        let data = try JSONEncoder().encode(value)
        let attributes = [kSecValueData as String: data]
        if status == errSecItemNotFound {
            var addition: [String: Any] = key
            addition[kSecValueData as String] = data
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else { throw VaultError.unavailable }
        } else {
            guard SecItemUpdate(key as CFDictionary, attributes as CFDictionary) == errSecSuccess else { throw VaultError.unavailable }
        }
        return value
    }

    private enum VaultError: Error { case unavailable }
}

@MainActor
final class PurchaseStore: ObservableObject {
    @Published private(set) var entitlement: Entitlement? = {
        guard Launch.testing else { return nil }
        let start = Date().addingTimeInterval(Launch.expired ? -31 * 86_400 : 0)
        return Entitlement(firstOpen: start, proStartedAt: start, purchasedPro: Launch.arguments.contains("-purchased"))
    }()
    @Published private(set) var products: [Product] = []
    @Published private(set) var busy = false
    @Published private(set) var status: String?
    private let vault = TrialVault()
    private let launched = Date()
    private var observedTime = Date.distantPast
    private var listener: Task<Void, Never>?
    private var refreshGeneration = 0
    static let proID = "com.hgsldswk.buildcalc.pro"
    static let trialID = "com.hgsldswk.buildcalc.trial"

    var hasPro: Bool {
        if Launch.isFree { return true }
        guard var value = entitlement else { return false }
        value.observe(observedTime)
        return value.hasPro(at: Date())
    }
    var pro: Product? { products.first { $0.id == Self.proID } }
    var trial: Product? { products.first { $0.id == Self.trialID } }

    deinit { listener?.cancel() }

    func checkAccess() -> Bool {
        let now = Date()
        let allowed = hasPro
        observedTime = max(observedTime, now)
        if !allowed, entitlement != nil, !Launch.testing, !Launch.isFree {
            Task { await refresh() }
        }
        return allowed
    }

    func start() async {
        guard !Launch.testing else { return }
        if !Launch.isFree, listener == nil {
            listener = Task { [weak self] in
                for await update in StoreKit.Transaction.updates {
                    guard let self, case let .verified(transaction) = update,
                          [Self.proID, Self.trialID].contains(transaction.productID) else { continue }
                    await self.refresh()
                    await transaction.finish()
                }
            }
        }
        await refresh()
    }

    func refresh() async {
        guard !Launch.testing else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        var bought = false
        var claimed: Date?
        if !Launch.isFree {
            for await check in StoreKit.Transaction.currentEntitlements {
                guard case let .verified(transaction) = check, transaction.revocationDate == nil else { continue }
                if transaction.productID == Self.proID { bought = true }
                if transaction.productID == Self.trialID { claimed = transaction.originalPurchaseDate }
            }
        }
        guard generation == refreshGeneration else { return }
        observedTime = max(Date(), observedTime)
        var value = try? await vault.load(started: launched, now: observedTime, verifiedTrial: claimed, free: Launch.isFree)
        guard generation == refreshGeneration else { return }
        if bought, value == nil { value = Entitlement(firstOpen: launched) }
        value?.purchasedPro = bought
        entitlement = value
    }

    func loadProducts() async {
        guard !Launch.testing, !Launch.isFree, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            products = try await Product.products(for: [Self.proID, Self.trialID]).filter { $0.type == .nonConsumable }
            status = products.contains { $0.id == Self.proID } ? nil : "store.unavailable"
        } catch { status = "store.unavailable" }
    }

    func purchase(_ product: Product) async {
        guard !busy, !Launch.isFree, !Launch.testing else { return }
        status = nil
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { status = "store.failed"; return }
                await refresh()
                await transaction.finish()
                status = product.id == Self.trialID ? "store.trialSaved" : "store.unlocked"
            case .pending: status = "store.pending"
            case .userCancelled: break
            @unknown default: status = "store.failed"
            }
        } catch { status = "store.failed" }
    }

    func restore() async {
        guard !busy, !Launch.isFree, !Launch.testing else { return }
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refresh()
            status = entitlement?.purchasedPro == true || entitlement?.trialClaimedAt != nil ? "store.restored" : "store.nothing"
        } catch { status = "store.failed" }
    }
}
