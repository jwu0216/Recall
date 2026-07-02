import Foundation

public enum VectorSearchService {
    public static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }

        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0

        for index in 0..<lhs.count {
            dot += lhs[index] * rhs[index]
            lhsNorm += lhs[index] * lhs[index]
            rhsNorm += rhs[index] * rhs[index]
        }

        let denominator = sqrt(lhsNorm) * sqrt(rhsNorm)
        guard denominator > 0 else { return 0 }
        return Double(dot / denominator)
    }

    public static func search(
        queryEmbedding: [Float],
        in items: [MemoryItem],
        limit: Int = 10
    ) -> [MemorySearchResult] {
        let scored = items.compactMap { item -> MemorySearchResult? in
            guard let embedding = item.embedding else { return nil }
            let score = cosineSimilarity(queryEmbedding, embedding)
            return MemorySearchResult(item: item.snapshot(), score: score)
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    public static func keywordFallback(query: String, in items: [MemoryItem], limit: Int = 10) -> [MemorySearchResult] {
        let terms = query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 }

        guard !terms.isEmpty else { return [] }

        let scored = items.map { item -> MemorySearchResult in
            let haystack = item.snapshot().searchableText.lowercased()
            let hits = terms.filter { haystack.contains($0) }.count
            return MemorySearchResult(item: item.snapshot(), score: Double(hits))
        }

        return scored
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}
