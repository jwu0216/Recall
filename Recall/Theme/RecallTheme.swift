import SwiftUI

enum RecallTheme {
    // MARK: - Palette (soft, light — not “AI neon”)

    static let ink = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let inkMuted = Color(red: 0.42, green: 0.42, blue: 0.46)
    static let inkSoft = Color(red: 0.58, green: 0.58, blue: 0.62)

    static let surface = Color.white.opacity(0.72)
    static let surfaceSolid = Color(red: 0.99, green: 0.99, blue: 0.985)
    static let surfaceSelected = Color(red: 0.16, green: 0.16, blue: 0.18)

    static let accent = Color(red: 0.62, green: 0.55, blue: 0.92) // soft lavender
    static let accentWarm = Color(red: 0.98, green: 0.78, blue: 0.70) // peach
    static let accentCool = Color(red: 0.78, green: 0.86, blue: 0.96) // mist blue
    static let accentRose = Color(red: 0.94, green: 0.82, blue: 0.88)

    static let danger = Color(red: 0.86, green: 0.32, blue: 0.32)

    static let cardRadius: CGFloat = 28
    static let chipRadius: CGFloat = 22
    static let controlRadius: CGFloat = 16
}

// MARK: - Background

struct PastelMeshBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.95)

            // Soft peach wash (top-left)
            Circle()
                .fill(RecallTheme.accentWarm.opacity(0.55))
                .frame(width: 340, height: 340)
                .blur(radius: 70)
                .offset(x: -120, y: -220)

            // Lavender wash (mid-right)
            Circle()
                .fill(RecallTheme.accent.opacity(0.35))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 140, y: 40)

            // Cool mist (bottom)
            Circle()
                .fill(RecallTheme.accentCool.opacity(0.55))
                .frame(width: 360, height: 360)
                .blur(radius: 75)
                .offset(x: -40, y: 420)

            // Soft rose highlight
            Circle()
                .fill(RecallTheme.accentRose.opacity(0.35))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 100, y: -40)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Surfaces

struct GlassCardModifier: ViewModifier {
    var padding: CGFloat = 18
    var selected: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: RecallTheme.cardRadius, style: .continuous)
                    .fill(selected ? RecallTheme.surfaceSelected : RecallTheme.surface)
                    .background {
                        RoundedRectangle(cornerRadius: RecallTheme.cardRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    .shadow(color: Color.black.opacity(selected ? 0.18 : 0.06), radius: selected ? 18 : 14, x: 0, y: selected ? 10 : 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: RecallTheme.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.08 : 0.55), lineWidth: 1)
            }
    }
}

extension View {
    func glassCard(padding: CGFloat = 18, selected: Bool = false) -> some View {
        modifier(GlassCardModifier(padding: padding, selected: selected))
    }
}

// MARK: - Buttons

struct RecallPrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                Capsule(style: .continuous)
                    .fill(RecallTheme.ink.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.35))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct RecallSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(RecallTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.55 : 0.85))
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : RecallTheme.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? RecallTheme.ink : Color.white.opacity(0.65))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(isSelected ? 0 : 0.7), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0.04), radius: isSelected ? 10 : 6, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct FloatingAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.22, green: 0.22, blue: 0.26),
                                    Color(red: 0.10, green: 0.10, blue: 0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.black.opacity(0.25), radius: 16, y: 8)
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add memory")
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(RecallTheme.inkSoft)
    }
}
