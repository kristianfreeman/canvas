import CanvasCore
import Foundation
import Testing
import TestSupport

/// One CLI run against a `RecordingServer`.
struct CLICall {
    let result: ProcessResult
    let connections: [RecordingServer.Connection]

    /// The first connection's request line, as sent.
    var raw: String { connections.first?.request ?? "" }
    var request: [String: Any] { connections.first?.json ?? [:] }
}

let rendered = #"{"event":"rendered"}"#

/// Runs `canvas ARGS` against a recording server playing `replies`, one
/// script per connection.
func canvas(
    _ args: [String], replies: [[RecordingServer.Step]] = [[.send(rendered)]], stdin: Data? = nil
) throws -> CLICall {
    let cli = Repo.cli
    try #require(
        FileManager.default.isExecutableFile(atPath: cli.path),
        "no CLI at \(cli.path); scripts/test.sh builds it with cli/build.sh")
    let server = try RecordingServer(replies)
    defer { server.stop() }
    let result = try ChildProcess.run(cli, args, environment: server.environment, stdin: stdin)
    #expect(!result.timedOut, "canvas \(args.joined(separator: " ")) hung")
    return CLICall(result: result, connections: server.connections())
}

/// The request's members except `source`, `path` and `title`, which depend
/// on the fixture files.
func options(_ request: [String: Any]) -> String {
    canonical(request.filter { !["source", "path", "title"].contains($0.key) })
}
