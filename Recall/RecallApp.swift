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
            fatalError("Failed to create Recall model container. Check the App Group entitlement.")
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
            .tint(RecallTheme.ink)
            .preferredColorScheme(.light)
            .modelContainer(container)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Share extension writes happen in another process; Ask's `.task` does not
            // re-run when returning from Safari, so process here and nudge the UI.
            Task {
                await processPendingJobsFromShare()
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: RecallConstants.storeNeedsRefreshNotification,
                        object: nil
                    )
                }
            }
        }
    }

    private func processPendingJobsFromShare() async {
        let context = ModelContext(container)
        let pendingRaw = ProcessingStatus.pending.rawValue
        let descriptor = FetchDescriptor<ProcessingJob>(
            predicate: #Predicate { $0.statusRaw == pendingRaw }
        )
        let pendingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard pendingCount > 0 else { return }

        guard let apiKey = APIKeyStore.load(), !apiKey.isEmpty else { return }
        let service = OpenAIService(configuration: OpenAIConfiguration(apiKey: apiKey))
        await MemoryProcessor(aiService: service).processPendingJobs(modelContext: context)
    }
}
