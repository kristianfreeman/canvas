import Foundation

public enum TextAlign: String, Equatable {
    case left, center, right
}

/// One highlighted token: text and an optional highlight scope.
public struct CodeToken: Equatable {
    public let text: String
    public let scope: String?

    public init(_ text: String, scope: String? = nil) {
        self.text = text
        self.scope = scope
    }

    /// `[[{s, c?}]]`, as `CodeBlock.lines` and Markdown `code.lines` send it.
    public static func lines(_ value: JSONValue?) -> [[Self]] {
        (value?.array ?? []).map { line in
            (line.array ?? []).compactMap { token in
                token["s"]?.string.map { Self($0, scope: token["c"]?.string) }
            }
        }
    }
}

public struct TextMarks: OptionSet, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold = Self(rawValue: 1)
    public static let italic = Self(rawValue: 2)
    public static let strike = Self(rawValue: 4)
}

public indirect enum MarkdownInline: Equatable {
    case text(String, TextMarks)
    case code(String)
    case link(href: String, [Self])
    case lineBreak
    case footnoteRef(id: String, number: Int)
}

public struct MarkdownListItem: Equatable {
    /// A task item has a checkbox.
    public let task: Bool
    public let checked: Bool
    public let blocks: [MarkdownBlock]

    public init(task: Bool, checked: Bool, blocks: [MarkdownBlock]) {
        self.task = task
        self.checked = checked
        self.blocks = blocks
    }
}

public struct MarkdownList: Equatable {
    public let ordered: Bool
    public let start: Int
    public let items: [MarkdownListItem]

    public init(ordered: Bool, start: Int, items: [MarkdownListItem]) {
        self.ordered = ordered
        self.start = start
        self.items = items
    }
}

public struct MarkdownTable: Equatable {
    public let align: [TextAlign?]
    public let head: [[MarkdownInline]]
    public let rows: [[[MarkdownInline]]]

    public init(align: [TextAlign?], head: [[MarkdownInline]], rows: [[[MarkdownInline]]]) {
        self.align = align
        self.head = head
        self.rows = rows
    }

    public var columnCount: Int { max(head.count, rows.map(\.count).max() ?? 0) }
}

public struct MarkdownFootnote: Equatable {
    public let id: String
    public let blocks: [MarkdownBlock]

    public init(id: String, blocks: [MarkdownBlock]) {
        self.id = id
        self.blocks = blocks
    }
}

/// The block tree `Markdown.blocks` carries (docs/native.md).
public indirect enum MarkdownBlock: Equatable {
    case heading(level: Int, [MarkdownInline])
    case paragraph([MarkdownInline])
    case quote([Self])
    case list(MarkdownList)
    case code(lang: String?, lines: [[CodeToken]])
    case table(MarkdownTable)
    case rule
    case footnotes([MarkdownFootnote])
}

/// Decodes `Markdown.blocks`. Entries that aren't objects or have an
/// unknown `t` are skipped, and missing fields take empty defaults, so a
/// malformed block never hides the rest of the document.
public enum MarkdownBlocks {
    public static func decode(_ value: JSONValue?) -> [MarkdownBlock] {
        (value?.array ?? []).compactMap(block)
    }

    static func block(_ value: JSONValue) -> MarkdownBlock? {
        switch value["t"]?.string {
        case "h": .heading(level: min(max(int(value["level"], 1), 1), 6), inlines(value["inl"]))
        case "p": .paragraph(inlines(value["inl"]))
        case "quote": .quote(decode(value["blocks"]))
        case "list": .list(list(value))
        case "code": .code(lang: value["lang"]?.string.flatMap { $0.isEmpty ? nil : $0 },
                           lines: CodeToken.lines(value["lines"]))
        default: leaf(value)
        }
    }

    private static func leaf(_ value: JSONValue) -> MarkdownBlock? {
        switch value["t"]?.string {
        case "table": .table(table(value))
        case "hr": .rule
        case "footnotes": .footnotes((value["items"]?.array ?? []).map {
            MarkdownFootnote(id: identifier($0["id"]), blocks: decode($0["blocks"]))
        })
        default: nil
        }
    }

    private static func list(_ value: JSONValue) -> MarkdownList {
        let items = (value["items"]?.array ?? []).map { item in
            MarkdownListItem(task: item["task"]?.isTrue == true, checked: item["checked"]?.isTrue == true,
                             blocks: decode(item["blocks"]))
        }
        return MarkdownList(ordered: value["ordered"]?.isTrue == true,
                            start: int(value["start"], 1), items: items)
    }

    private static func table(_ value: JSONValue) -> MarkdownTable {
        MarkdownTable(
            align: (value["align"]?.array ?? []).map { $0.string.flatMap(TextAlign.init) },
            head: (value["head"]?.array ?? []).map(inlines),
            rows: (value["rows"]?.array ?? []).map { ($0.array ?? []).map(inlines) })
    }

    public static func inlines(_ value: JSONValue?) -> [MarkdownInline] {
        (value?.array ?? []).compactMap(inline)
    }

    static func inline(_ value: JSONValue) -> MarkdownInline? {
        switch value["t"]?.string {
        case "text": value["s"]?.string.map { .text($0, marks(value)) }
        case "code": value["s"]?.string.map(MarkdownInline.code)
        case "link": .link(href: value["href"]?.string ?? "", inlines(value["inl"]))
        case "br": .lineBreak
        case "fnref": .footnoteRef(id: identifier(value["id"]), number: int(value["n"], 0))
        default: nil
        }
    }

    private static func marks(_ value: JSONValue) -> TextMarks {
        var marks: TextMarks = []
        if value["b"]?.isTrue == true { marks.insert(.bold) }
        if value["i"]?.isTrue == true { marks.insert(.italic) }
        if value["del"]?.isTrue == true { marks.insert(.strike) }
        return marks
    }

    /// A whole number, or `fallback` for anything missing, fractional or out of range.
    static func int(_ value: JSONValue?, _ fallback: Int) -> Int {
        guard let number = value?.number, number.isFinite, abs(number) < 1e9 else { return fallback }
        return Int(number)
    }

    private static func identifier(_ value: JSONValue?) -> String {
        switch value {
        case .string(let text): text
        case .number: String(int(value, 0))
        default: ""
        }
    }
}
