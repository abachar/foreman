import Dispatch
import Foundation

/// The long-lived half of `PipeIO`: a child that is spoken to and listened to for as long as it
/// runs, instead of being filled once and read to the end (editor R36, the language servers).
///
/// Same reason as the rest of `PipeIO` — `DispatchIO` and never `FileHandle.bytes` — and one more:
/// a request must be writable while the answer to the previous one is still arriving, which a
/// one-shot `writeAndClose` cannot do.
/// `nonisolated`: every closure here runs on a `DispatchIO` queue, never on the main actor —
/// without this the file's default isolation makes them `@MainActor` and the first callback traps
/// in `swift_task_checkIsolated` (crash on the first server started, 2026-08-31).
nonisolated extension PipeIO {
    /// Every chunk the handle gives until EOF, in order.
    ///
    /// Chunks are what the pipe delivers, not messages: framing is the caller's business.
    static func chunks(_ handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            let queue = DispatchQueue.global()
            let channel = DispatchIO(
                type: .stream, fileDescriptor: handle.fileDescriptor, queue: queue,
                cleanupHandler: { _ in
                    try? handle.close()
                    continuation.finish()
                })
            // Without this the handler is only called at EOF: `DispatchIO`'s low-water mark
            // defaults to the whole requested length, and the length here is "everything".
            // `readToEnd` never noticed — it wants EOF — and a stream would have waited for the
            // child to die before delivering its first byte (found 2026-08-31, task 18.1).
            channel.setLimit(lowWater: 1)
            continuation.onTermination = { _ in channel.close(flags: .stop) }
            channel.read(offset: 0, length: .max, queue: queue) { done, data, _ in
                if let data, !data.isEmpty {
                    continuation.yield(Data(data))
                }
                if done {
                    channel.close()
                }
            }
        }
    }

    /// A handle written to many times and closed once.
    ///
    /// `@unchecked Sendable`: the only stored state is the `DispatchIO` channel, which serialises
    /// every write on the queue it was created with; `close` is idempotent by the same route.
    final class Writer: @unchecked Sendable {
        private let channel: DispatchIO
        private let queue = DispatchQueue.global()

        init(_ handle: FileHandle) {
            channel = DispatchIO(
                type: .stream, fileDescriptor: handle.fileDescriptor, queue: queue,
                cleanupHandler: { _ in try? handle.close() })
        }

        /// Queues `data`; returns when the channel has taken all of it.
        ///
        /// A child that died gives `EPIPE`, which arrives as a completed write like any other —
        /// the caller learns it from the process's exit, not from here.
        func write(_ data: Data) async {
            guard !data.isEmpty else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                channel.write(offset: 0, data: data.withUnsafeBytes { DispatchData(bytes: $0) }, queue: queue) {
                    done, _, _ in
                    if done {
                        continuation.resume()
                    }
                }
            }
        }

        /// Closes the handle: the child's EOF on `stdin`.
        func close() {
            channel.close()
        }
    }
}
