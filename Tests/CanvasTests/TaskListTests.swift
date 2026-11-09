import CanvasCore
import Foundation
import Testing

@Suite struct TaskListTests {
    @Test func checksAndUnchecksTheNamedLine() {
        let source = "# Today\n\n- [ ] one\n- [x] two\n"
        #expect(TaskList.setChecked(true, line: 2, in: source) == "# Today\n\n- [x] one\n- [x] two\n")
        #expect(TaskList.setChecked(false, line: 3, in: source) == "# Today\n\n- [ ] one\n- [ ] two\n")
    }

    @Test func alreadyInThatStateLeavesTheSource() {
        let source = "- [X] shouted\n- [ ] quiet\n"
        #expect(TaskList.setChecked(true, line: 0, in: source) == source)
        #expect(TaskList.setChecked(false, line: 1, in: source) == source)
    }

    @Test(arguments: [
        ("  - [ ] nested", true), ("* [ ] star", true), ("+ [ ] plus", true), ("12. [ ] ordered", true),
        ("3) [ ] paren", true), ("> - [ ] quoted", true), (">> 1. [ ] deep", true), ("-\t[ ] tab", true),
        ("- [ ]\u{a0}nbsp", true), ("- [ ]", false), ("- [] empty", false), ("-[ ] no gap", false),
        ("[ ] bare", false), ("- [y] other", false), ("1234567890. [ ] too long", false), ("text", false),
        ("- item [ ] later", false)
    ])
    func recognizesTaskLines(line: String, isTask: Bool) {
        #expect((TaskList.setChecked(true, line: 0, in: line) != nil) == isTask, "\(line)")
    }

    @Test func linesEndAtCRLFCROrLF() {
        let source = "a\r\n- [ ] b\r- [ ] c\n- [ ] d"
        #expect(TaskList.setChecked(true, line: 1, in: source) == "a\r\n- [x] b\r- [ ] c\n- [ ] d")
        #expect(TaskList.setChecked(true, line: 2, in: source) == "a\r\n- [ ] b\r- [x] c\n- [ ] d")
        #expect(TaskList.setChecked(true, line: 3, in: source) == "a\r\n- [ ] b\r- [ ] c\n- [x] d")
    }

    @Test func linesOutOfRangeAreNil() {
        #expect(TaskList.setChecked(true, line: 1, in: "- [ ] only") == nil)
        #expect(TaskList.setChecked(true, line: -1, in: "- [ ] only") == nil)
        #expect(TaskList.setChecked(true, line: 0, in: "") == nil)
    }

    @Test func stateReadsTheMarker() {
        let source = "- [ ] a\n- [x] b\nplain"
        #expect(TaskList.state(line: 0, in: source) == .open)
        #expect(TaskList.state(line: 1, in: source) == .done)
        #expect(TaskList.state(line: 2, in: source) == nil)
    }

    /// Random documents of task, plain and blank lines with mixed endings.
    /// Checking a task line changes exactly that line's marker and nothing
    /// else, and checking it back restores the document.
    @Test(arguments: 0..<300)
    func onlyTheNamedMarkerChanges(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let prefixes = ["- ", "  * ", "1. ", "> + ", "10) "]
        let bodies = ["[ ] todo", "[x] done", "[X] DONE", "plain", "[ ]", "a [ ] b", ""]
        let endings = ["\n", "\r\n", "\r"]
        let count = Int.random(in: 1...12, using: &rng)
        let lines = (0..<count).map { _ in
            (prefixes.randomElement(using: &rng) ?? "") + (bodies.randomElement(using: &rng) ?? "")
        }
        var source = ""
        for (index, line) in lines.enumerated() {
            source += line
            if index < count - 1 { source += endings.randomElement(using: &rng) ?? "\n" }
        }
        for index in 0..<count {
            let checked = Bool.random(using: &rng)
            guard let next = TaskList.setChecked(checked, line: index, in: source) else {
                #expect(TaskList.state(line: index, in: source) == nil, "seed \(seed) line \(index)")
                continue
            }
            #expect(TaskList.state(line: index, in: next) == (checked ? .done : .open), "seed \(seed) line \(index)")
            let changed = zip(Array(source), Array(next)).filter { $0 != $1 }.count
            #expect(next.count == source.count && changed <= 1, "seed \(seed) line \(index)")
            for other in 0..<count where other != index {
                #expect(TaskList.state(line: other, in: next) == TaskList.state(line: other, in: source),
                        "seed \(seed) line \(index) touched \(other)")
            }
            // `[X]` comes back as `[x]`.
            let was = TaskList.state(line: index, in: source) == .done
            #expect(TaskList.setChecked(was, line: index, in: next) == source || lines[index].contains("[X]"),
                    "seed \(seed) line \(index) does not restore")
        }
    }
}
