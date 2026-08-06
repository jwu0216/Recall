import SwiftUI

struct TagEditorSection: View {
    @Binding var tags: [String]
    var onChange: ([String]) -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Tags")

            if tags.isEmpty {
                Text("No tags yet. Add a few so you can find this note later.")
                    .font(.subheadline)
                    .foregroundStyle(RecallTheme.inkMuted)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Button {
                                remove(tag)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(RecallTheme.inkSoft)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(tag)")
                        }
                        .foregroundStyle(RecallTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RecallTheme.accent.opacity(0.18), in: Capsule())
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Add tag", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: RecallTheme.controlRadius, style: .continuous)
                            .fill(Color.white.opacity(0.7))
                    )
                    .onSubmit(addFromDraft)

                Button("Add", action: addFromDraft)
                    .buttonStyle(RecallSecondaryButtonStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func addFromDraft() {
        let parts = draft
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return }

        var next = tags
        for part in parts where !next.contains(part) {
            next.append(part)
        }
        draft = ""
        commit(next)
    }

    private func remove(_ tag: String) {
        commit(tags.filter { $0 != tag })
    }

    private func commit(_ next: [String]) {
        tags = next
        onChange(next)
    }

    private func normalize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

/// Wrapping row layout that never asks for more width than the parent proposes.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        let arrangement = arrange(subviews: subviews, maxWidth: maxWidth)
        let width = proposal.width ?? arrangement.size.width
        return CGSize(width: width, height: arrangement.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews: subviews, maxWidth: bounds.width)
        for (index, frame) in arrangement.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> (size: CGSize, frames: [CGRect]) {
        guard maxWidth > 0 else {
            return (.zero, Array(repeating: .zero, count: subviews.count))
        }

        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let width = min(ideal.width, maxWidth)
            let height = subview
                .sizeThatFits(ProposedViewSize(width: width, height: nil))
                .height
            let size = CGSize(width: width, height: height)

            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        let height = frames.isEmpty ? 0 : y + rowHeight
        return (CGSize(width: maxWidth, height: height), frames)
    }
}
