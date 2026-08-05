import SwiftUI
import SwiftData
import RecallCore

@main
struct RecallApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let container: ModelContainer

    init() {
        container = (try? RecallModelContainerFactory.makeContainer()) ?? {
            fatalError("Failed to create Recall model container.")
        }()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            }
            .modelContainer(container)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Force a fresh read after Share Extension writes from another process.
            let context = ModelContext(container)
            context.rollback()
        }
    }
}
