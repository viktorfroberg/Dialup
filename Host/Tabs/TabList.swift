/// A window's tabs in strip order plus which one is active. Pure bookkeeping (no AppKit or
/// WebKit), so the ordering rules are unit-tested; `BrowserWindowController` keeps one of these.
/// Elements are compared by identity.
struct TabList<Element: AnyObject> {
    /// Where a new tab goes.
    enum Position {
        /// Right after the active tab, like a link opened in a new tab.
        case afterActive
        /// At the end of the strip, like ⌘T or a restored session.
        case end
    }

    private(set) var elements: [Element] = []
    /// Index of the active tab; 0 while the list is empty.
    private(set) var activeIndex = 0

    var count: Int { elements.count }
    var isEmpty: Bool { elements.isEmpty }
    var indices: Range<Int> { elements.indices }
    var active: Element? { elements.indices.contains(activeIndex) ? elements[activeIndex] : nil }

    subscript(index: Int) -> Element { elements[index] }

    func index(of element: Element) -> Int? {
        elements.firstIndex { $0 === element }
    }

    func firstIndex(where predicate: (Element) -> Bool) -> Int? {
        elements.firstIndex(where: predicate)
    }

    func contains(_ element: Element) -> Bool { index(of: element) != nil }

    /// Inserts `element` without changing which tab is active; returns its index.
    @discardableResult
    mutating func insert(_ element: Element, at position: Position) -> Int {
        let index = (isEmpty || position == .end) ? count : activeIndex + 1
        elements.insert(element, at: index)
        return index
    }

    /// Makes the tab at `index` active. Returns false (and changes nothing) for an invalid index.
    @discardableResult
    mutating func select(_ index: Int) -> Bool {
        guard elements.indices.contains(index) else { return false }
        activeIndex = index
        return true
    }

    /// Removes the tab at `index`. The active tab stays active if it's another one; closing the
    /// active tab activates its right neighbour, or its left one when it was last.
    @discardableResult
    mutating func remove(at index: Int) -> Element? {
        guard elements.indices.contains(index) else { return nil }
        let removed = elements.remove(at: index)
        if index < activeIndex || activeIndex >= count { activeIndex = max(0, activeIndex - 1) }
        return removed
    }

    /// The next tab's index, wrapping around (⌃⇥).
    var nextIndex: Int { isEmpty ? 0 : (activeIndex + 1) % count }
    /// The previous tab's index, wrapping around (⌃⇧⇥).
    var previousIndex: Int { isEmpty ? 0 : (activeIndex - 1 + count) % count }
}
