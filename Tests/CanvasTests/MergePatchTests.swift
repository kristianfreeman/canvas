import CanvasCore
import Testing

struct MergeCase: CustomTestStringConvertible, Sendable {
    let original: String
    let patch: String
    let result: String

    var testDescription: String { "\(original) + \(patch)" }
}

/// RFC 7386, Appendix A, verbatim.
private let appendixA: [MergeCase] = [
    MergeCase(original: #"{"a":"b"}"#, patch: #"{"a":"c"}"#, result: #"{"a":"c"}"#),
    MergeCase(original: #"{"a":"b"}"#, patch: #"{"b":"c"}"#, result: #"{"a":"b","b":"c"}"#),
    MergeCase(original: #"{"a":"b"}"#, patch: #"{"a":null}"#, result: #"{}"#),
    MergeCase(original: #"{"a":"b","b":"c"}"#, patch: #"{"a":null}"#, result: #"{"b":"c"}"#),
    MergeCase(original: #"{"a":["b"]}"#, patch: #"{"a":"c"}"#, result: #"{"a":"c"}"#),
    MergeCase(original: #"{"a":"c"}"#, patch: #"{"a":["b"]}"#, result: #"{"a":["b"]}"#),
    MergeCase(original: #"{"a":{"b":"c"}}"#, patch: #"{"a":{"b":"d","c":null}}"#, result: #"{"a":{"b":"d"}}"#),
    MergeCase(original: #"{"a":[{"b":"c"}]}"#, patch: #"{"a":[1]}"#, result: #"{"a":[1]}"#),
    MergeCase(original: #"["a","b"]"#, patch: #"["c","d"]"#, result: #"["c","d"]"#),
    MergeCase(original: #"{"a":"b"}"#, patch: #"["c"]"#, result: #"["c"]"#),
    MergeCase(original: #"{"a":"foo"}"#, patch: "null", result: "null"),
    MergeCase(original: #"{"a":"foo"}"#, patch: #""bar""#, result: #""bar""#),
    MergeCase(original: #"{"e":null}"#, patch: #"{"a":1}"#, result: #"{"e":null,"a":1}"#),
    MergeCase(original: "[1,2]", patch: #"{"a":"b","c":null}"#, result: #"{"a":"b"}"#),
    MergeCase(original: "{}", patch: #"{"a":{"bb":{"ccc":null}}}"#, result: #"{"a":{"bb":{}}}"#)
]

@Suite struct MergePatchTests {
    @Test(arguments: appendixA)
    func rfcAppendixA(_ test: MergeCase) {
        let merged = MergePatch.apply(json(test.patch), to: json(test.original))
        #expect(canonical(merged) == canonical(json(test.result)))
    }

    /// RFC 7386, section 3.
    @Test func rfcSectionThreeExample() {
        let original = #"""
        {"title": "Goodbye!", "author": {"givenName": "John", "familyName": "Doe"},
         "tags": ["example", "sample"], "content": "This will be unchanged"}
        """#
        let patch = #"""
        {"title": "Hello!", "phoneNumber": "+01-123-456-7890", "author": {"familyName": null},
         "tags": ["example"]}
        """#
        let result = #"""
        {"title": "Hello!", "author": {"givenName": "John"}, "tags": ["example"],
         "content": "This will be unchanged", "phoneNumber": "+01-123-456-7890"}
        """#
        #expect(canonical(MergePatch.apply(json(patch), to: json(original))) == canonical(json(result)))
    }

    @Test func absentTargetIsTreatedAsEmpty() {
        #expect(canonical(MergePatch.apply(json(#"{"a":{"b":null,"c":1}}"#), to: nil)) == #"{"a":{"c":1}}"#)
        #expect(canonical(MergePatch.apply(json("3"), to: nil)) == "3")
    }
}
