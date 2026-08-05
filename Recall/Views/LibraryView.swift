import SwiftUI
import SwiftData
import RecallCore

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]
    @State private var showingAddMemory = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(memories, id: \.id) { memory in
                    NavigationLink {
                        MemoryDetailView(memoryID: memory.id)
                    } label: {
                        MemoryRowView(snapshot: memory.snapshot(), score: nil)
                    }
                }
                .onDelete(perform: deleteMemories)
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddMemory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add memory")
                }
            }
            .sheet(isPresented: $showingAddMemory) {
                AddMemoryView()
            }
            .overlay {
                if memories.isEmpty {
                    ContentUnavailableView {
                        Label("No memories yet", systemImage: "tray")
                    } description: {
                        Text("Tap + to add a note, or use Share from another app.")
                    } actions: {
                        Button("Add memory") {
                            showingAddMemory = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func deleteMemories(at offsets: IndexSet) {
        for index in offsets {
            let memory = memories[index]
            try? MemoryDeletion.delete(memory, modelContext: modelContext)
        }
    }
}
