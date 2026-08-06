import SwiftUI
import SwiftData
import RecallCore

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]
    @State private var showingAddMemory = false

    var body: some View {
        NavigationStack {
            ZStack {
                PastelMeshBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "Library")
                            Text("All Notes")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(RecallTheme.ink)

                            Text("\(memories.count) saved")
                                .font(.subheadline)
                                .foregroundStyle(RecallTheme.inkMuted)
                        }
                        .padding(.top, 8)

                        if memories.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(memories, id: \.id) { memory in
                                    NavigationLink {
                                        MemoryDetailView(memoryID: memory.id)
                                    } label: {
                                        MemoryRowView(snapshot: memory.snapshot(), score: nil)
                                            .glassCard(padding: 18)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Delete", role: .destructive) {
                                            delete(memory)
                                        }
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                }

                VStack {
                    Spacer()
                    HStack {
                        FloatingAddButton { showingAddMemory = true }
                            .padding(.leading, 22)
                            .padding(.bottom, 12)
                        Spacer()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAddMemory) {
                AddMemoryView()
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No notes yet")
                .font(.title2.weight(.bold))
                .foregroundStyle(RecallTheme.ink)
            Text("Tap + to add a note, or use Share from another app.")
                .font(.subheadline)
                .foregroundStyle(RecallTheme.inkMuted)
            Button("Add note") {
                showingAddMemory = true
            }
            .buttonStyle(RecallSecondaryButtonStyle())
        }
        .glassCard()
    }

    private func delete(_ memory: MemoryItem) {
        try? MemoryDeletion.delete(memory, modelContext: modelContext)
    }
}
