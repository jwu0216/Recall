import SwiftUI
import RecallCore

struct MemoryRowView: View {
    let snapshot: MemoryItemSnapshot
    let score: Double?
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dateLabel)
                    .font(.caption)
                    .foregroundStyle(RecallTheme.inkSoft)

                Spacer(minLength: 0)

                if let score {
                    Text(String(format: "%.0f%%", score * 100))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(RecallTheme.inkMuted)
                }
            }

            Text(snapshot.title ?? "Untitled memory")
                .font(compact ? .headline.weight(.semibold) : .title3.weight(.bold))
                .foregroundStyle(RecallTheme.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(compact ? 2 : 3)

            if let summary = snapshot.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(RecallTheme.inkMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: 8) {
                metaPill(snapshot.contentType.rawValue.capitalized)
                metaPill(snapshot.source.rawValue.capitalized)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var dateLabel: String {
        snapshot.createdAt.formatted(date: .abbreviated, time: .omitted)
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(RecallTheme.inkMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.04), in: Capsule())
    }
}
