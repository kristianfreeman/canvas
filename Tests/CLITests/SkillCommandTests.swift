import Foundation
import Testing
import TestSupport

/// Every bash block in skills/mac-canvas/SKILL.md, run by bash with `canvas`
/// as the real CLI. Commands that take `--emit` must print their request and
/// exit 0. The rest (`sub`, `pub -`, `pub --every`, `--timeout`, `--stream`)
/// run against no server and must fail with something other than a usage
/// error.
@Suite struct SkillCommandTests {
    static let skill = Repo.root.appendingPathComponent("skills/mac-canvas/SKILL.md")

    static let bashBlocks: [String] = {
        guard let text = try? String(contentsOf: skill, encoding: .utf8) else { return [] }
        var blocks: [String] = []
        var current: [String]?
        for line in text.components(separatedBy: "\n") {
            if current == nil, line == "```bash" {
                current = []
            } else if let lines = current, line == "```" {
                blocks.append(lines.joined(separator: "\n"))
                current = nil
            } else {
                current?.append(line)
            }
        }
        return blocks
    }()

    private static let shim = #"""
        set -eo pipefail
        cd "$BLOCK_DIR"
        canvas() {
          local status=0
          local args=" $* "
          if [[ $1 == sub || $args == *" -- "* || $args == *" --timeout "* || $args == *" --stream "* ||
                ($1 == pub && $args == *" - "*) ]]; then
            "$CANVAS_CLI" "$@" </dev/null >/dev/null 2>"$BLOCK_DIR/.err" || status=$?
            if ((status == 64)); then echo "usage error: canvas $* ($(<"$BLOCK_DIR/.err"))" >&2; exit 64; fi
          else
            "$CANVAS_CLI" "$@" --emit >/dev/null 2>"$BLOCK_DIR/.err" || status=$?
            if ((status != 0)); then echo "exit $status: canvas $* ($(<"$BLOCK_DIR/.err"))" >&2; exit 1; fi
          fi
          return 0
        }

        """#

    @Test func theSkillHasShellBlocksToCheck() {
        #expect(Self.bashBlocks.count >= 4, "found \(Self.bashBlocks.count) bash blocks in \(Self.skill.path)")
    }

    @Test(arguments: bashBlocks)
    func everyCommandInTheBlockIsValid(block: String) throws {
        let cli = Repo.cli
        try #require(FileManager.default.isExecutableFile(atPath: cli.path), "no CLI at \(cli.path)")
        let dir = TempDir()
        let home = TempDir()
        let fixtures = ["md": "# Fixture\n", "tsx": "export default () => null\n", "json": "{}\n"]
        for match in block.matches(of: #/\b[\w-]+\.(md|tsx|json)\b/#) {
            _ = dir.file(String(match.output.0), fixtures[String(match.output.1)] ?? "")
        }
        let result = try ChildProcess.run(
            URL(fileURLWithPath: "/bin/bash"), ["-c", Self.shim + block],
            environment: [
                "CANVAS_CLI": cli.path, "BLOCK_DIR": dir.path,
                "CANVAS_HOME": home.path, "CANVAS_NO_AUTOSTART": "1"
            ])
        #expect(!result.timedOut, "the block hung:\n\(block)")
        #expect(result.status == 0, "\(result.stderr)\n\(block)")
    }
}
