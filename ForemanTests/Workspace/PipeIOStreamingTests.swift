import Foundation
import Testing

@testable import Foreman

/// The long-lived half of `PipeIO`, exercised against a real child (editor R36).
///
/// The child is `/bin/cat`, which echoes what it is given — enough to prove the two things that
/// matter and that nothing else covers: data arrives **before** EOF, and the writer can be used
/// again after the first answer.
struct PipeIOStreamingTests {
    private func cat() throws -> (process: Process, input: Pipe, output: Pipe) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/cat")
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        return (process, input, output)
    }

    /// The regression this file exists for: `DispatchIO`'s low-water mark defaults to the whole
    /// requested length, so a read of "everything" only calls back at EOF. `readToEnd` never
    /// noticed — it wants EOF — but a language server would have delivered its first byte only
    /// once it died (found 2026-08-31, task 18.1).
    @Test func deliversAChunkBeforeTheChildExits() async throws {
        let child = try cat()
        defer { child.process.terminate() }
        let writer = PipeIO.Writer(child.input.fileHandleForWriting)
        var chunks = PipeIO.chunks(child.output.fileHandleForReading).makeAsyncIterator()
        await writer.write(Data("first\n".utf8))
        let received = await chunks.next()
        #expect(received.map { String(decoding: $0, as: UTF8.self) } == "first\n")
        // The child is still alive: what arrived did not arrive because the pipe closed.
        #expect(child.process.isRunning)
    }

    /// One writer, several messages: a request must be sendable while the previous answer is
    /// still being read, which `writeAndClose` cannot do.
    @Test func writesAgainAfterAnAnswer() async throws {
        let child = try cat()
        defer { child.process.terminate() }
        let writer = PipeIO.Writer(child.input.fileHandleForWriting)
        var chunks = PipeIO.chunks(child.output.fileHandleForReading).makeAsyncIterator()
        await writer.write(Data("one\n".utf8))
        #expect(await chunks.next().map { String(decoding: $0, as: UTF8.self) } == "one\n")
        await writer.write(Data("two\n".utf8))
        #expect(await chunks.next().map { String(decoding: $0, as: UTF8.self) } == "two\n")
    }

    /// Closing the writer is the child's EOF: `cat` then leaves and the stream ends.
    @Test func closingTheWriterEndsTheStream() async throws {
        let child = try cat()
        defer { child.process.terminate() }
        let writer = PipeIO.Writer(child.input.fileHandleForWriting)
        let output = PipeIO.chunks(child.output.fileHandleForReading)
        await writer.write(Data("bye\n".utf8))
        writer.close()
        var seen = ""
        for await chunk in output {
            seen += String(decoding: chunk, as: UTF8.self)
        }
        // The stream ending is itself the proof: `cat` closed its `stdout`, which it only does
        // once its `stdin` reached EOF.
        #expect(seen == "bye\n")
    }
}
