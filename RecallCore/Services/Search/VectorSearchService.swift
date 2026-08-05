import Foundation

public enum VectorSearchService {
    /// Cosine similarity floor for text-embedding-3-small.
    /// High enough to drop unrelated queries; low enough for category→item matches (e.g. "makeup" → foundation).
    public static let minimumVectorScore: Double = 0.28

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
        limit: Int = 10,
        minimumScore: Double = minimumVectorScore
    ) -> [MemorySearchResult] {
        let scored = items.compactMap { item -> MemorySearchResult? in
            guard let embedding = item.embedding else { return nil }
            let score = cosineSimilarity(queryEmbedding, embedding)
            guard score >= minimumScore else { return nil }
            return MemorySearchResult(item: item.snapshot(), score: score)
        }

        return Array(
            scored
                .sorted { $0.score > $1.score }
                .prefix(limit)
        )
    }

    public static func keywordFallback(
        query: String,
        in items: [MemoryItem],
        limit: Int = 10
    ) -> [MemorySearchResult] {
        let normalizedQuery = normalize(query)
        let terms = tokenize(normalizedQuery)
        guard !normalizedQuery.isEmpty else { return [] }

        let scored = items.compactMap { item -> MemorySearchResult? in
            let haystack = normalize(item.snapshot().searchableText)
            guard !haystack.isEmpty else { return nil }

            // Prefer exact/phrase match for proper names like restaurant titles.
            if normalizedQuery.count >= 2, haystack.contains(normalizedQuery) {
                return MemorySearchResult(item: item.snapshot(), score: 1.5)
            }

            guard !terms.isEmpty else { return nil }

            let hits = terms.filter { haystack.contains($0) }
            // For multi-word names, require at least one strong token (3+ chars)
            // or all tokens if they're all short.
            let strongHits = hits.filter { $0.count >= 3 }
            let isMatch: Bool
            if terms.contains(where: { $0.count >= 3 }) {
                isMatch = !strongHits.isEmpty
            } else {
                isMatch = hits.count == terms.count
            }
            guard isMatch else { return nil }

            let density = Double(hits.count) / Double(max(terms.count, 1))
            return MemorySearchResult(
                item: item.snapshot(),
                score: density + Double(strongHits.count) * 0.15
            )
        }

        return Array(
            scored
                .sorted { $0.score > $1.score }
                .prefix(limit)
        )
    }

    /// Prefer semantic hits; fill gaps with keyword hits for exact names/words.
    public static func relevantMatches(
        query: String,
        queryEmbedding: [Float],
        in items: [MemoryItem],
        limit: Int = 8
    ) -> [MemorySearchResult] {
        let vectorHits = search(queryEmbedding: queryEmbedding, in: items, limit: limit)
        let keywordHits = keywordFallback(query: query, in: items, limit: limit)

        var merged: [UUID: MemorySearchResult] = [:]

        for hit in vectorHits {
            merged[hit.id] = hit
        }

        for hit in keywordHits {
            if let existing = merged[hit.id] {
                merged[hit.id] = MemorySearchResult(
                    item: existing.item,
                    score: max(existing.score, 0.55 + min(hit.score, 0.4))
                )
            } else {
                // Keyword-only hits are still relevant (e.g. exact restaurant name).
                merged[hit.id] = MemorySearchResult(
                    item: hit.item,
                    score: 0.55 + min(hit.score, 0.4)
                )
            }
        }

        return Array(
            merged.values
                .sorted { $0.score > $1.score }
                .prefix(limit)
        )
    }

    /// Lowercase, strip diacritics/punctuation so "Joe's" matches "Joes" / "joe s".
    public static func normalize(_ text: String) -> String {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        var scalars: [Character] = []
        scalars.reserveCapacity(folded.count)
        for character in folded {
            if character.isLetter || character.isNumber {
                scalars.append(character)
            } else if character == "'" || character == "’" || character == "`" {
                continue
            } else {
                scalars.append(" ")
            }
        }

        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func tokenize(_ normalizedQuery: String) -> [String] {
        normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.count >= 2 }
    }
}
