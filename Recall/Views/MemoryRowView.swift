import SwiftUI
import RecallCore

struct MemoryRowView: View {
    let snapshot: MemoryItemSnapshot
    let score: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(snapshot.title ?? "Untitled memory")
                    .font(.headline)
                Spacer()
                if let score {
                    Text(String(format: "%.2f", score))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let summary = snapshot.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text(snapshot.contentType.rawValue.capitalized)
                Text("•")
                Text(snapshot.source.rawValue.capitalized)
                Spacer()
                Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
