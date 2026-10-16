/// The newest `capacity` values appended, oldest first.
public struct History<Element> {
    public private(set) var capacity: Int
    public private(set) var elements: [Element] = []

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
    }

    public mutating func append(_ element: Element) {
        guard capacity > 0 else { return }
        elements.append(element)
        trim()
    }

    /// Shrinking drops the oldest values.
    public mutating func resize(_ capacity: Int) {
        self.capacity = max(0, capacity)
        trim()
    }

    private mutating func trim() {
        if elements.count > capacity { elements.removeFirst(elements.count - capacity) }
    }
}
