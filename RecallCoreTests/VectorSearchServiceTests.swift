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
}
