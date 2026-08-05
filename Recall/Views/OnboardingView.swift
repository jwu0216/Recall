import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("Recall")
                .font(.largeTitle.bold())

            Text("Save it. Ask for it later.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                onboardingRow(
                    icon: "square.and.arrow.up",
                    title: "Share from any app",
                    detail: "Links, images, PDFs, and text — Safari, Mail, Notes, and more."
                )
                onboardingRow(
                    icon: "sparkle.magnifyingglass",
                    title: "Ask in plain English",
                    detail: "“chicken wings recipe”, “tax thing”, “blue jacket I saved”."
                )
                onboardingRow(
                    icon: "key",
                    title: "Add your OpenAI key",
                    detail: "For now you’ll paste your own API key in Settings (dev mode)."
                )
            }
            .padding(.horizontal)

            Spacer()

            Button("Get started") {
                hasCompletedOnboarding = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 32)
        }
        .padding()
    }

    private func onboardingRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
