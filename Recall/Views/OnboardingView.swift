import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool

    var body: some View {
        ZStack {
            PastelMeshBackground()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 12) {
                    Text("Recall")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(RecallTheme.ink)

                    Text("Save it. Find it later.")
                        .font(.title3)
                        .foregroundStyle(RecallTheme.inkMuted)
                }

                VStack(alignment: .leading, spacing: 14) {
                    onboardingRow(
                        icon: "plus.circle",
                        title: "Add it yourself",
                        detail: "Type a note, paste a link, or attach a photo/PDF."
                    )
                    onboardingRow(
                        icon: "square.and.arrow.up",
                        title: "Or share from any app",
                        detail: "Safari, Mail, Notes — tap Share → Recall."
                    )
                    onboardingRow(
                        icon: "magnifyingglass",
                        title: "Ask in plain English",
                        detail: "“chicken wings recipe”, “tax thing”, “blue jacket”."
                    )
                    onboardingRow(
                        icon: "key",
                        title: "Add your OpenAI key",
                        detail: "Paste your own API key in Settings (dev mode)."
                    )
                }
                .glassCard()
                .padding(.horizontal, 20)

                Spacer()

                Button("Get started") {
                    hasCompletedOnboarding = true
                }
                .buttonStyle(RecallPrimaryButtonStyle())
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            }
        }
    }

    private func onboardingRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 32)
                .foregroundStyle(RecallTheme.ink)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(RecallTheme.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(RecallTheme.inkMuted)
            }
        }
    }
}
