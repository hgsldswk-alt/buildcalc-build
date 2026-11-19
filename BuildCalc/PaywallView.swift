import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PlanMark().stroke(Palette.green, lineWidth: 1.8).frame(width: 64, height: 50).accessibilityHidden(true)
                    Text(L.t("store.title")).font(.largeTitle.bold()).accessibilityIdentifier("paywall.title")
                    Text(L.t("store.body"))
                    Text(L.t("store.kept")).modifier(PanelStyle())
                    if purchases.entitlement?.purchasedPro == true {
                        Text(L.t("store.unlocked")).font(.headline)
                    } else if let product = purchases.pro {
                        Button(L.f("store.buyPrice", product.displayPrice)) { Task { await purchases.purchase(product) } }
                            .buttonStyle(PrimaryStyle()).disabled(purchases.busy).accessibilityIdentifier("paywall.buy")
                    } else if Launch.testing {
                        Button(L.f("store.buyPrice", L.t("store.fixturePrice"))) {}.buttonStyle(PrimaryStyle())
                            .accessibilityIdentifier("paywall.buy")
                    } else {
                        Button(L.t("store.retry")) { Task { await purchases.loadProducts() } }
                            .buttonStyle(PrimaryStyle()).disabled(purchases.busy).accessibilityIdentifier("paywall.reload")
                    }
                    if purchases.hasPro, purchases.entitlement?.purchasedPro != true, purchases.entitlement?.trialClaimedAt == nil {
                        if let trial = purchases.trial {
                            Button(L.t("store.trialReceipt")) { Task { await purchases.purchase(trial) } }
                                .buttonStyle(PrimaryStyle(muted: true)).disabled(purchases.busy).accessibilityIdentifier("paywall.trial")
                        } else if Launch.testing && Launch.opensPaywall {
                            Button(L.t("store.trialReceipt")) {}.buttonStyle(PrimaryStyle(muted: true)).accessibilityIdentifier("paywall.trial")
                        }
                    }
                    Button(L.t("store.restore")) { Task { await purchases.restore() } }
                        .buttonStyle(PrimaryStyle(muted: true)).disabled(purchases.busy).accessibilityIdentifier("paywall.restore")
                    if purchases.busy { ProgressView().accessibilityLabel(L.t("store.loading")) }
                    if let status = purchases.status { Text(L.t(status)).font(.footnote) }
                }.padding(20)
            }
            .background(Palette.paper.ignoresSafeArea()).foregroundStyle(Palette.ink)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L.t("action.done")) { dismiss() }.accessibilityIdentifier("paywall.done") } }
        }
        .tint(Palette.green)
        .task { await purchases.loadProducts() }
    }
}
