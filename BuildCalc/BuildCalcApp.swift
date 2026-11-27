import SwiftUI

@main
@MainActor
struct BuildCalcApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Workbench()
                .environmentObject(model)
                .preferredColorScheme(.light)
                .task { await model.start() }
        }
    }
}
