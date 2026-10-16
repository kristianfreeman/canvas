import Foundation

public struct ProcessResult {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public var summary: String {
        "exit \(status)\(timedOut ? " (timed out)" : "")\nstdout: \(stdout)\nstderr: \(stderr)"
    }
}

/// A child process with captured output. Output is read on background
/// threads so a chatty child never blocks on a full pipe.
public final class ChildProcess {
    private let process = Process()
    private let output = Pipe()
    private let errors = Pipe()
    private let reads = DispatchGroup()
    private let exited = DispatchSemaphore(value: 0)
    private var stdoutData = Data()
    private var stderrData = Data()

    /// The child gets exactly `environment` plus `PATH` and `HOME`, so the
    /// caller's CANVAS_* variables never leak in.
    public init(_ executable: URL, _ arguments: [String], environment: [String: String], stdin: Data? = nil) throws {
        Darwin.signal(SIGPIPE, SIG_IGN)
        process.executableURL = executable
        process.arguments = arguments
        var env = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory()]
        env.merge(environment) { $1 }
        process.environment = env
        process.standardOutput = output
        process.standardError = errors
        let input = stdin.map { _ in Pipe() }
        process.standardInput = input ?? FileHandle.nullDevice
        process.terminationHandler = { [exited] _ in exited.signal() }
        collect(output.fileHandleForReading) { [weak self] in self?.stdoutData = $0 }
        collect(errors.fileHandleForReading) { [weak self] in self?.stderrData = $0 }
        try process.run()
        if let input, let stdin { feed(input.fileHandleForWriting, stdin) }
    }

    public var pid: Int32 { process.processIdentifier }

    private func collect(_ handle: FileHandle, into store: @escaping (Data) -> Void) {
        reads.enter()
        DispatchQueue.global().async { [reads] in
            store(handle.readDataToEndOfFile())
            reads.leave()
        }
    }

    private func feed(_ handle: FileHandle, _ data: Data) {
        DispatchQueue.global().async {
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }

    public func signal(_ number: Int32) {
        kill(process.processIdentifier, number)
    }

    /// Waits for the exit; past `timeout` the child is killed and the result
    /// says so.
    public func wait(timeout: TimeInterval = 10) -> ProcessResult {
        let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            kill(process.processIdentifier, SIGKILL)
            exited.wait()
        }
        reads.wait()
        return ProcessResult(
            status: timedOut ? -1 : process.terminationStatus,
            stdout: stdoutData.text,
            stderr: stderrData.text,
            timedOut: timedOut)
    }

    public static func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String],
        stdin: Data? = nil,
        timeout: TimeInterval = 10
    ) throws -> ProcessResult {
        try ChildProcess(executable, arguments, environment: environment, stdin: stdin).wait(timeout: timeout)
    }
}
