import Foundation

public enum VectorSearchService {
    /// Cosine similarity floor for text-embedding-3-small.
    /// High enough to drop unrelated queries; low enough for category→item matches (e.g. "makeup" → foundation).
    public static let minimumVectorScore: Double = 0.28

    /// Synonym groups for plain-English Ask. Any term in a group expands to the whole group
    /// so "food"↔"restaurant", "makeup"↔"foundation", "travel"↔"hotel", etc.
    private static let categoryGroups: [[String]] = [
        // Food & drink
        [
            "food", "restaurant", "dining", "cafe", "coffee", "pizza", "recipe",
            "meal", "eat", "eatery", "bakery", "brunch", "lunch", "dinner",
            "menu", "kitchen", "bar", "bistro", "sushi", "ramen", "taco",
            "burger", "cooking", "bake", "ingredients", "yelp", "resy", "opentable"
        ],
        // Beauty
        [
            "makeup", "cosmetics", "beauty", "foundation", "lipstick", "skincare",
            "concealer", "blush", "mascara", "serum", "moisturizer"
        ],
        // Fashion
        [
            "fashion", "clothing", "clothes", "outfit", "style", "jacket", "dress",
            "shoes", "sneakers", "apparel", "wardrobe"
        ],
        // Travel
        [
            "travel", "trip", "flight", "hotel", "airbnb", "vacation", "itinerary",
            "booking", "airport", "passport", "luggage"
        ],
        // Home
        [
            "home", "apartment", "furniture", "decor", "house", "kitchenware",
            "cleaning", "ikea"
        ],
        // Work / productivity
        [
            "work", "job", "office", "meeting", "career", "resume", "interview",
            "slack", "notion", "productivity"
        ],
        // Health & fitness
        [
            "health", "fitness", "gym", "workout", "exercise", "doctor", "medical",
            "pharmacy", "wellness", "running"
        ],
        // Entertainment
        [
            "movie", "film", "tv", "show", "netflix", "music", "spotify", "concert",
            "podcast", "book", "reading", "game", "gaming"
        ],
        // Shopping
        [
            "shopping", "store", "shop", "buy", "purchase", "amazon", "order",
            "gift", "wishlist"
        ],
        // Tech
        [
            "tech", "software", "app", "gadget", "phone", "laptop", "computer",
            "github", "code", "ai"
        ],
        // Finance
        [
            "finance", "money", "budget", "bank", "tax", "invoice", "receipt",
            "investing", "salary"
        ],
        // People / social
        [
            "people", "friend", "family", "contact", "birthday", "party", "wedding",
            "social"
        ],
        // Places / local
        [
            "place", "location", "map", "address", "neighborhood", "city", "park"
        ]
    ]

    private static let categoryExpansions: [String: [String]] = {
        var index: [String: [String]] = [:]
        for group in categoryGroups {
            let normalized = group.map { normalize($0) }
            for term in normalized {
                var merged = Set(index[term] ?? [])
                merged.formUnion(normalized)
                index[term] = Array(merged)
            }
        }
        return index
    }()

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
        let matchTerms = expandedMatchTerms(for: normalizedQuery, terms: terms)
        guard !normalizedQuery.isEmpty, !matchTerms.isEmpty else { return [] }

        let scored = items.compactMap { item -> MemorySearchResult? in
            let haystack = normalize(item.snapshot().searchableText)
            guard !haystack.isEmpty else { return nil }

            // Prefer exact/phrase match for proper names like restaurant titles.
            if normalizedQuery.count >= 2, haystack.contains(normalizedQuery) {
                return MemorySearchResult(item: item.snapshot(), score: 1.5)
            }

            let hits = matchTerms.filter { haystack.contains($0) }
            let strongHits = hits.filter { $0.count >= 3 }
            let isCategoryQuery = categoryExpansions[normalizedQuery] != nil

            let isMatch: Bool
            if isCategoryQuery {
                // "food" should match memories tagged restaurant/dining/etc.
                isMatch = !strongHits.isEmpty || !hits.isEmpty
            } else if terms.contains(where: { $0.count >= 3 }) {
                isMatch = !strongHits.isEmpty
            } else {
                isMatch = hits.count == terms.count
            }
            guard isMatch else { return nil }

            let density = Double(hits.count) / Double(max(matchTerms.count, 1))
            let categoryBonus = isCategoryQuery && !hits.isEmpty ? 0.35 : 0
            return MemorySearchResult(
                item: item.snapshot(),
                score: density + Double(strongHits.count) * 0.15 + categoryBonus
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

    private static func expandedMatchTerms(for normalizedQuery: String, terms: [String]) -> [String] {
        var expanded = Set(terms)
        if let aliases = categoryExpansions[normalizedQuery] {
            expanded.formUnion(aliases.map { normalize($0) })
        }
        for term in terms {
            if let aliases = categoryExpansions[term] {
                expanded.formUnion(aliases.map { normalize($0) })
            }
        }
        return Array(expanded)
    }
}
