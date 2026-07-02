import SwiftUI
import SwiftData
import RecallCore

@main
struct RecallApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer

    init() {
        container = (try? RecallModelContainerFactory.makeContainer()) ?? {
            fatalError("Failed to create Recall model container.")
        }()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .modelContainer(container)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            let context = ModelContext(container)
            context.rollback()
        }
    }
}
