import XCTest
@testable import Dialup

final class TabListTests: XCTestCase {
    private final class Item: CustomStringConvertible {
        let name: String
        init(_ name: String) { self.name = name }
        var description: String { name }
    }

    private func names(_ list: TabList<Item>) -> [String] { list.elements.map(\.name) }

    private func list(_ names: String..., active: Int = 0) -> TabList<Item> {
        var list = TabList<Item>()
        for name in names { list.insert(Item(name), at: .end) }
        list.select(active)
        return list
    }

    func testEmpty() {
        let list = TabList<Item>()
        XCTAssertTrue(list.isEmpty)
        XCTAssertNil(list.active)
        XCTAssertEqual(list.activeIndex, 0)
    }

    func testSessionRestoreAppendsInOrderWithoutChangingTheActiveTab() {
        var list = TabList<Item>()
        for name in ["a", "b", "c"] { list.insert(Item(name), at: .end) }
        XCTAssertEqual(names(list), ["a", "b", "c"])
        XCTAssertEqual(list.active?.name, "a")
        XCTAssertTrue(list.select(2))
        XCTAssertEqual(list.active?.name, "c")
    }

    func testAfterActiveInsertsNextToTheActiveTab() {
        var list = list("a", "b", "c", active: 0)
        let index = list.insert(Item("x"), at: .afterActive)
        XCTAssertEqual(index, 1)
        XCTAssertEqual(names(list), ["a", "x", "b", "c"])
        XCTAssertEqual(list.active?.name, "a", "inserting doesn't switch tabs")
        XCTAssertEqual(list.insert(Item("y"), at: .end), 4)
    }

    func testFirstInsertGoesToIndexZero() {
        var list = TabList<Item>()
        XCTAssertEqual(list.insert(Item("a"), at: .afterActive), 0)
    }

    func testSelectRejectsInvalidIndices() {
        var list = list("a", "b", active: 1)
        XCTAssertFalse(list.select(2))
        XCTAssertFalse(list.select(-1))
        XCTAssertEqual(list.activeIndex, 1)
    }

    func testClosingTheActiveTabActivatesItsRightNeighbour() {
        var list = list("a", "b", "c", active: 1)
        XCTAssertEqual(list.remove(at: 1)?.name, "b")
        XCTAssertEqual(list.active?.name, "c")
    }

    func testClosingTheLastActiveTabActivatesItsLeftNeighbour() {
        var list = list("a", "b", "c", active: 2)
        list.remove(at: 2)
        XCTAssertEqual(list.active?.name, "b")
    }

    func testClosingAnotherTabKeepsTheActiveOne() {
        var left = list("a", "b", "c", active: 1)
        left.remove(at: 0)
        XCTAssertEqual(left.active?.name, "b")
        var right = list("a", "b", "c", active: 1)
        right.remove(at: 2)
        XCTAssertEqual(right.active?.name, "b")
    }

    func testRemovingTheOnlyTabAndInvalidIndices() {
        var list = list("a")
        XCTAssertNil(list.remove(at: 3))
        list.remove(at: 0)
        XCTAssertTrue(list.isEmpty)
        XCTAssertNil(list.active)
    }

    func testNextAndPreviousWrapAround() {
        let list = list("a", "b", "c", active: 2)
        XCTAssertEqual(list.nextIndex, 0)
        XCTAssertEqual(list.previousIndex, 1)
        XCTAssertEqual(self.list("a", "b", active: 0).previousIndex, 1)
    }

    func testLookupIsByIdentity() {
        let shared = Item("same")
        var list = TabList<Item>()
        list.insert(Item("same"), at: .end)
        list.insert(shared, at: .end)
        XCTAssertEqual(list.index(of: shared), 1)
        XCTAssertFalse(list.contains(Item("same")))
    }
}
