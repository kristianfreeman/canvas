@testable import CanvasApp
import CanvasCore
import Foundation
import TestSupport
import Testing

/// `examples/hello.md` through a real context, read back from the Markdown node's `blocks`.
@MainActor @Suite struct NativeMarkdownTests {
    private static func blocks() async throws -> [JSONValue] {
        let page = try NativeHarness()
        defer { page.close() }
        let source = try String(contentsOf: Repo.examples.appendingPathComponent("hello.md"), encoding: .utf8)
        let result = await page.render(markdown: source)
        #expect(result.ok, "\(result.error ?? "")")
        return try #require(page.node("Markdown")?.props["blocks"]?.array)
    }

    private static func kind(_ block: JSONValue) -> String { block["t"]?.string ?? "?" }

    private static func code(_ blocks: [JSONValue], lang: String) throws -> [[JSONValue]] {
        let block = try #require(blocks.first { kind($0) == "code" && $0["lang"]?.string == lang })
        let lines = try #require(block["lines"]?.array)
        return lines.compactMap(\.array)
    }

    private static func scopes(_ lines: [[JSONValue]]) -> Set<String> {
        Set(lines.joined().compactMap { $0["c"]?.string })
    }

    @Test func helloHasEveryBlockKindInOrder() async throws {
        let kinds = try await Self.blocks().map(Self.kind)
        #expect(kinds == ["h", "p", "quote", "h", "table", "h", "list", "h", "code", "code", "code", "code",
                          "hr", "p", "footnotes"])
    }

    @Test func tableKeepsAlignmentHeadAndRows() async throws {
        let table = try #require(try await Self.blocks().first { Self.kind($0) == "table" })
        #expect(table["align"] == .array([.null, .string("center"), .string("center"), .null]))
        #expect(table["head"]?.array?.first == .array([.object(["t": .string("text"), "s": .string("Feature")])]))
        #expect(table["rows"]?.array?.count == 4)
        let notes = table["rows"]?.array?.first?.array?.last?.array?.first
        #expect(notes?["s"]?.string == "Watches the file, even atomic saves")
    }

    @Test func taskListItemsAreCheckedAndStripped() async throws {
        let list = try #require(try await Self.blocks().first { Self.kind($0) == "list" })
        let items = try #require(list["items"]?.array)
        #expect(items.map { $0["task"] } == Array(repeating: .bool(true), count: 4))
        #expect(items.map { $0["checked"] } == [.bool(true), .bool(true), .bool(false), .bool(false)])
        let first = items.first?["blocks"]?.array?.first?["inl"]?.array?.first?["s"]?.string
        #expect(first == "Build the panel server")
    }

    @Test func footnoteReferenceLinksToItsItem() async throws {
        let blocks = try await Self.blocks()
        let intro = try #require(blocks[1]["inl"]?.array)
        let ref = try #require(intro.first { $0["t"]?.string == "fnref" })
        #expect(ref["n"] == .number(1))
        let notes = try #require(blocks.last?["items"]?.array)
        #expect(notes.map { $0["id"] } == [ref["id"]])
        #expect(intro.contains { $0["t"]?.string == "code" && $0["s"]?.string == "canvas show plan.md" })
    }

    @Test func fencesAreHighlightedIntoContractScopes() async throws {
        let blocks = try await Self.blocks()
        let typescript = try Self.code(blocks, lang: "ts")
        #expect(typescript.count == 9)
        #expect(typescript.first?.first == .object(["s": .string("import"), "c": .string("keyword")]))
        #expect(Self.scopes(typescript).isSuperset(of: ["keyword", "string"]))
        #expect(Self.scopes(try Self.code(blocks, lang: "bash")).contains("comment"))
        #expect(Self.scopes(try Self.code(blocks, lang: "json")).isSuperset(of: ["attr", "string"]))
        let allowed: Set<String> = [
            "keyword", "string", "number", "comment", "title", "type", "attr", "variable", "literal", "built_in",
            "meta", "symbol", "regexp", "addition", "deletion", "punctuation", "property", "tag", "section"
        ]
        let swift = try Self.code(blocks, lang: "swift")
        #expect(Self.scopes(swift).isSubset(of: allowed))
        let firstLine = swift.first?.compactMap { $0["s"]?.string }.joined()
        #expect(firstLine == "let panel = CanvasPanel(contentRect: frame)")
    }

    @Test func linksKeepTheirHref() async throws {
        let blocks = try await Self.blocks()
        let paragraph = try #require(blocks.last { Self.kind($0) == "p" }?["inl"]?.array)
        let link = try #require(paragraph.first { $0["t"]?.string == "link" })
        #expect(link["href"] == .string("https://shiki.style"))
        #expect(link["inl"]?.array?.first?["s"] == .string("shiki.style"))
    }
}
