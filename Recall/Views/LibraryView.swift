import SwiftUI
import SwiftData
import RecallCore

struct LibraryView: View {
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]

    var body: some View {
        NavigationStack {
            List(memories, id: \.id) { memory in
                NavigationLink {
                    MemoryDetailView(memoryID: memory.id)
                } label: {
                    MemoryRowView(snapshot: memory.snapshot(), score: nil)
                }
            }
            .navigationTitle("Library")
            .overlay {
                if memories.isEmpty {
                    ContentUnavailableView(
                        "No memories yet",
                        systemImage: "tray",
                        description: Text("Use Share to save something into Recall.")
                    )
                }
            }
        }
    }
}
