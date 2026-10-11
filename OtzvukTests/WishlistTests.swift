import XCTest
@testable import Otzvuk

@MainActor
final class WishlistTests: XCTestCase {
    func testTextLibraryIsConsistent() {
        let all = TextLibrary.categories.flatMap(\.items)
        XCTAssertEqual(all.count, 178)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "номера не должны повторяться")
        XCTAssertTrue(all.allSatisfy { !$0.text.isEmpty })
        XCTAssertEqual(TextLibrary.item(id: 102)?.text, "Ты утверждаешь для себя новую, позитивную реальность.")
    }

    func testToggleAddsOnceRemovesOnSecondTapAndPersists() {
        let store = TestSupport.tempStore()
        let wishlist = Wishlist(store: store)
        let text = TextLibrary.categories[0].items[0]
        wishlist.toggle(text)
        XCTAssertTrue(wishlist.contains(sourceID: text.id))
        XCTAssertEqual(Wishlist(store: store).items.map(\.text), [text.text])
        wishlist.toggle(text)
        XCTAssertTrue(wishlist.items.isEmpty)
        XCTAssertTrue(Wishlist(store: store).items.isEmpty)
    }

    func testSavingRecordingFromWishRemovesItFromList() throws {
        let store = TestSupport.tempStore()
        let model = AppModel(store: store, defaults: UserDefaults(suiteName: "otzvuk-tests-\(UUID().uuidString)")!)
        model.wishlist.toggle(TextLibrary.categories[0].items[0])
        let wish = model.wishlist.items[0]
        // Имитируем готовую запись, минуя микрофон.
        let id = UUID()
        let name = "\(id.uuidString).m4a"
        try TestSupport.writeTone(to: store.recordingURL(name), seconds: 1)
        model.library.add(id: id, title: wish.suggestedTitle, fileName: name, duration: 1)
        model.wishlist.remove(id: wish.id)
        XCTAssertTrue(model.wishlist.items.isEmpty)
        XCTAssertEqual(model.library.affirmations.count, 1)
    }

    func testAddAllAddsOnlyMissingAndRemoveAllClears() {
        let store = TestSupport.tempStore()
        let wishlist = Wishlist(store: store)
        let items = TextLibrary.categories[0].items
        wishlist.toggle(items[0])
        wishlist.addAll(items)
        XCTAssertEqual(wishlist.items.map(\.sourceID), items.map(\.id), "без дублей, порядок сохранён")
        XCTAssertEqual(Wishlist(store: store).items.count, items.count)
        wishlist.addAll(items)
        XCTAssertEqual(wishlist.items.count, items.count)
        wishlist.removeAll(items)
        XCTAssertTrue(wishlist.items.isEmpty)
    }

    func testSuggestedTitleIsShortened() {
        let long = WishItem(id: UUID(), text: String(repeating: "слово ", count: 30), sourceID: nil)
        XCTAssertLessThanOrEqual(long.suggestedTitle.count, 61)
        XCTAssertTrue(long.suggestedTitle.hasSuffix("…"))
        XCTAssertEqual(WishItem(id: UUID(), text: "Коротко.", sourceID: nil).suggestedTitle, "Коротко.")
    }
}
