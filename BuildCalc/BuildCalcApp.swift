import SwiftUI

@main
@MainActor
struct BuildCalcApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var purchases = PurchaseStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Workbench()
                .environmentObject(model)
                .environmentObject(purchases)
                .preferredColorScheme(.light)
                .task { await model.start() }
                .task { await purchases.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await purchases.refresh() } }
                }
        }
    }
}
