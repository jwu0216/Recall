import RecallCore
import XCTest

final class VectorSearchServiceTests: XCTestCase {
    func testCosineSimilarityIdenticalVectors() {
        let vector: [Float] = [1, 0, 0]
        let score = VectorSearchService.cosineSimilarity(vector, vector)
        XCTAssertEqual(score, 1.0, accuracy: 0.0001)
    }

    func testKeywordFallbackFindsMatchingMemory() {
        let item = MemoryItem(
            source: .manual,
            contentType: .text,
            title: "Chicken wings recipe",
            summary: "Crispy baked wings",
            extractedText: "ingredients and steps",
            tags: ["food", "recipe"],
            processingStatus: .ready
        )

        let results = VectorSearchService.keywordFallback(query: "chicken wings", in: [item])
        XCTAssertEqual(results.first?.item.title, "Chicken wings recipe")
    }

    func testKeywordFallbackIgnoresUnrelatedQuery() {
        let item = MemoryItem(
            source: .manual,
            contentType: .text,
            title: "Tony's Pizza",
            summary: "Neighborhood pizza restaurant",
            extractedText: "Great pepperoni slices",
            tags: ["food", "pizza"],
            processingStatus: .ready
        )

        let results = VectorSearchService.keywordFallback(query: "Computer", in: [item])
        XCTAssertTrue(results.isEmpty)
    }

    func testVectorSearchDropsWeakMatches() {
        let item = MemoryItem(
            source: .manual,
            contentType: .text,
            title: "Tony's Pizza",
            summary: "Neighborhood pizza restaurant",
            processingStatus: .ready
        )
        // Nearly orthogonal to a one-hot query embedding → weak similarity.
        item.embedding = [0.05, 0.9, 0.1]

        let results = VectorSearchService.search(
            queryEmbedding: [1, 0, 0],
            in: [item],
            minimumScore: VectorSearchService.minimumVectorScore
        )
        XCTAssertTrue(results.isEmpty)
    }

    func testRelevantMatchesKeepsKeywordHitWithoutStrongVectorScore() {
        let item = MemoryItem(
            source: .manual,
            contentType: .text,
            title: "Tony's Pizza",
            summary: "Neighborhood pizza restaurant",
            extractedText: "Best pizza nearby",
            tags: ["pizza"],
            processingStatus: .ready
        )
        item.embedding = [0.05, 0.9, 0.1]

        let results = VectorSearchService.relevantMatches(
            query: "pizza",
            queryEmbedding: [1, 0, 0],
            in: [item]
        )
        XCTAssertEqual(results.first?.item.title, "Tony's Pizza")
    }

    func testKeywordFallbackFindsRestaurantNameDespiteApostrophe() {
        let item = MemoryItem(
            source: .manual,
            contentType: .text,
            title: "Favorite slice spot",
            summary: "Great neighborhood pizza",
            extractedText: "Joe's Pizza on Carmine",
            tags: ["pizza"],
            processingStatus: .ready
        )

        let byName = VectorSearchService.keywordFallback(query: "Joe's Pizza", in: [item])
        XCTAssertEqual(byName.first?.item.extractedText, "Joe's Pizza on Carmine")

        let byPossessive = VectorSearchService.keywordFallback(query: "Joes", in: [item])
        XCTAssertFalse(byPossessive.isEmpty)
    }

    func testNormalizeStripsPunctuationForNames() {
        XCTAssertEqual(
            VectorSearchService.normalize("Joe's Pizza"),
            "joes pizza"
        )
    }

    func testKeywordFallbackFoodQueryMatchesRestaurantTaggedMemory() {
        let item = MemoryItem(
            source: .share,
            contentType: .link,
            title: "Sole Uptown",
            summary: "Italian restaurant on Broadway",
            extractedText: "https://www.yelp.com/biz/sole-uptown",
            tags: ["restaurant", "italian", "dining"],
            sourceURL: URL(string: "https://www.yelp.com/biz/sole-uptown"),
            processingStatus: .ready
        )

        let results = VectorSearchService.keywordFallback(query: "food", in: [item])
        XCTAssertEqual(results.first?.item.title, "Sole Uptown")
    }

    func testKeywordFallbackCategoryGroupsWorkAcrossGenres() {
        let makeup = MemoryItem(
            source: .manual,
            contentType: .text,
            title: "Winter foundation",
            tags: ["foundation", "sephora"],
            processingStatus: .ready
        )
        let hotel = MemoryItem(
            source: .share,
            contentType: .link,
            title: "Kyoto stay",
            tags: ["hotel", "kyoto"],
            processingStatus: .ready
        )
        let jacket = MemoryItem(
            source: .manual,
            contentType: .image,
            title: "Blue jacket",
            tags: ["jacket", "uniqlo"],
            processingStatus: .ready
        )

        XCTAssertEqual(
            VectorSearchService.keywordFallback(query: "makeup", in: [makeup]).first?.item.title,
            "Winter foundation"
        )
        XCTAssertEqual(
            VectorSearchService.keywordFallback(query: "travel", in: [hotel]).first?.item.title,
            "Kyoto stay"
        )
        XCTAssertEqual(
            VectorSearchService.keywordFallback(query: "fashion", in: [jacket]).first?.item.title,
            "Blue jacket"
        )
    }
}
