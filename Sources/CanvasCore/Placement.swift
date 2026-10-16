import Foundation

/// Where a panel goes and how its window behaves: the placement fields of a
/// `show`, `toggle` or `move` request. Every field has its protocol default;
/// `given` records which ones the request actually set, so a later request
/// can be merged on top and remembered frames apply only when nothing
/// placed the panel explicitly.
public struct Placement: Equatable, Sendable {
    public enum Field: String, CaseIterable, Sendable {
        case position, at, screen, margin, width, height, minHeight, maxHeight
        case resizable, level, spaces, pin, clickThrough, opacity, stack, forget

        /// Fields that move the panel: changing one calls for a new placement.
        /// `forget` drops a remembered frame, so the panel is placed from its
        /// options again.
        public static let positioning: Set<Self> = [.position, .at, .screen, .margin, .stack, .forget]
        /// Fields that only change its size, kept around the growth anchor.
        public static let sizing: Set<Self> = [.width, .height, .minHeight, .maxHeight]
    }

    /// What a merged request asks of an open panel.
    public enum Change: Sendable {
        case none, resize, place
    }

    public static let defaultMargin: CGFloat = 24
    public static let topMargin: CGFloat = 64

    public var position = Position.center
    /// Overrides `position` when set.
    public var at: AtPoint?
    public var screen = ScreenSelector.mouse
    /// Nil keeps the per-preset defaults: 64 from the top for `top`, 24
    /// everywhere else.
    public var margin: CGFloat?
    public var width = Length.points(720)
    /// A fixed height. Nil means the height follows the content.
    public var height: Length?
    public var minHeight = Length.points(80)
    public var maxHeight = Length.percent(85)
    public var resizable = true
    public var level = Level.floating
    public var spaces = Spaces.all
    public var pin = false
    public var clickThrough = false
    public var opacity: CGFloat = 1
    public var stack: String?
    public var forget = false
    public internal(set) var given: Set<Field> = []

    public init() {}

    /// Reads the placement fields of a request; other keys are ignored and
    /// `null` counts as absent. Invalid values throw with a message for the
    /// caller.
    public init(json: [String: Any]) throws(RequestError) {
        for field in Field.allCases {
            guard let value = json[field.rawValue], !(value is NSNull) else { continue }
            try Self.parse(field, value, into: &self)
            given.insert(field)
        }
    }

    /// Whether a remembered frame may stand in for this placement: nothing
    /// positioned the panel, it isn't stacked, and the caller didn't ask to
    /// forget it.
    public var restoresRememberedFrame: Bool {
        given.isDisjoint(with: [.position, .at, .stack]) && !forget
    }

    /// `pin` keeps the panel on all Spaces at floating level or above.
    public var effectiveLevel: Level { pin && level == .normal ? .floating : level }
    public var effectiveSpaces: Spaces { pin ? .all : spaces }
    public var closesOnEscape: Bool { !pin }

    /// The growth anchor of a non-mouse placement. `mouse` returns nil: its
    /// anchor depends on where the panel lands (see `anchor(for:mouse:)`).
    public var presetAnchor: Anchor? {
        guard let at else { return position.anchor }
        return Anchor(at.y.isNegative ? .bottom : .top, at.x.isNegative ? .right : .left)
    }

    /// This placement with `newer`'s given fields on top. Giving `position`
    /// without `at` drops an older `at`, which would otherwise override it.
    public func merging(_ newer: Self) -> Self {
        var merged = self
        merged.take(\.position, .position, from: newer)
        merged.take(\.at, .at, from: newer)
        merged.take(\.screen, .screen, from: newer)
        merged.take(\.margin, .margin, from: newer)
        merged.take(\.width, .width, from: newer)
        merged.take(\.height, .height, from: newer)
        merged.take(\.minHeight, .minHeight, from: newer)
        merged.take(\.maxHeight, .maxHeight, from: newer)
        merged.take(\.resizable, .resizable, from: newer)
        merged.take(\.level, .level, from: newer)
        merged.take(\.spaces, .spaces, from: newer)
        merged.take(\.pin, .pin, from: newer)
        merged.take(\.clickThrough, .clickThrough, from: newer)
        merged.take(\.opacity, .opacity, from: newer)
        merged.take(\.stack, .stack, from: newer)
        merged.take(\.forget, .forget, from: newer)
        if newer.given.contains(.position), !newer.given.contains(.at) {
            merged.at = nil
            merged.given.remove(.at)
        }
        return merged
    }

    /// What an open panel should do after `newer` is merged into it.
    public static func change(for newer: Self) -> Change {
        if !newer.given.isDisjoint(with: Field.positioning) { return .place }
        return newer.given.isDisjoint(with: Field.sizing) ? .none : .resize
    }

    private mutating func take<T>(_ path: WritableKeyPath<Self, T>, _ field: Field, from newer: Self) {
        guard newer.given.contains(field) else { return }
        self[keyPath: path] = newer[keyPath: path]
        given.insert(field)
    }
}
