import XCTest
@testable import Otzvuk

final class PlaybackQueueTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    func testAdvanceWrapsAround() {
        var q = PlaybackQueue(ids: [a, b, c])
        XCTAssertEqual(q.current, a)
        XCTAssertEqual(q.advance(), b)
        XCTAssertEqual(q.advance(), c)
        XCTAssertEqual(q.advance(), a)
    }

    func testSingleItemRepeats() {
        var q = PlaybackQueue(ids: [a])
        XCTAssertEqual(q.advance(), a)
        XCTAssertEqual(q.advance(), a)
    }

    func testRemoveBeforeCurrentKeepsCurrent() {
        var q = PlaybackQueue(ids: [a, b, c])
        q.advance(); q.advance() // current = c
        XCTAssertEqual(q.remove(a), .other)
        XCTAssertEqual(q.current, c)
    }

    func testRemoveCurrentMovesToNext() {
        var q = PlaybackQueue(ids: [a, b, c])
        q.advance() // b
        XCTAssertEqual(q.remove(b), .current)
        XCTAssertEqual(q.current, c)
    }

    func testRemoveLastCurrentWrapsToFirst() {
        var q = PlaybackQueue(ids: [a, b])
        q.advance() // b
        XCTAssertEqual(q.remove(b), .current)
        XCTAssertEqual(q.current, a)
    }

    func testRemoveAfterCurrentAndUnknown() {
        var q = PlaybackQueue(ids: [a, b, c])
        XCTAssertEqual(q.remove(c), .other)
        XCTAssertEqual(q.remove(UUID()), .notFound)
        XCTAssertEqual(q.current, a)
        XCTAssertEqual(q.count, 2)
    }

    func testRemovingEverythingEmptiesQueue() {
        var q = PlaybackQueue(ids: [a])
        XCTAssertEqual(q.remove(a), .current)
        XCTAssertNil(q.current)
        XCTAssertTrue(q.isEmpty)
        XCTAssertNil(q.advance())
    }
}
