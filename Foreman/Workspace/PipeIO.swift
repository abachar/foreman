import Dispatch
import Foundation
import Synchronization

/// The pipes of a child process, read and written without parking a thread (coding rules,
/// concurrency): `DispatchIO` hands its buffers back on a queue, so nothing blocks while the
/// child is slow to speak or slow to listen.
///
/// **Never `FileHandle.bytes` here.** Foundation runs every `AsyncBytes` iteration on one shared
/// serial queue (`com.apple.Foundation.AsyncBytesIOActorQueue`): reading a process's stdout and
/// stderr at the same time makes them take turns, and a pipe with nothing to give holds the queue
/// in a blocking `read(2)` while the other fills up. `/bin/cat` and 260 KB of text deadlocked
/// exactly there (verified 2026-08-30, macOS 27).
nonisolated enum PipeIO {
    /// Everything the handle has until EOF; whatever was read when a watchdog closes it early.
    static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            let queue = DispatchQueue.global()
            let collected = Mutex(Data())
            let channel = DispatchIO(
                type: .stream, fileDescriptor: handle.fileDescriptor, queue: queue,
                cleanupHandler: { _ in
                    try? handle.close()
                    continuation.resume(returning: collected.withLock { $0 })
                })
            channel.read(offset: 0, length: .max, queue: queue) { done, data, _ in
                if let data, !data.isEmpty {
                    collected.withLock { $0.append(contentsOf: data) }
                }
                if done {
                    channel.close()
                }
            }
        }
    }

    /// Writes everything, then closes the handle — that close is the child's EOF on `stdin`.
    ///
    /// A child that exits before reading gives `EPIPE`, which arrives as a completed write like
    /// any other: the caller reads the story in the status and `stderr`, not here.
    static func writeAndClose(_ data: Data, to handle: FileHandle) async {
        guard !data.isEmpty else {
            try? handle.close()
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let queue = DispatchQueue.global()
            let channel = DispatchIO(
                type: .stream, fileDescriptor: handle.fileDescriptor, queue: queue,
                cleanupHandler: { _ in
                    try? handle.close()
                    continuation.resume()
                })
            channel.write(offset: 0, data: data.withUnsafeBytes { DispatchData(bytes: $0) }, queue: queue) {
                done, _, _ in
                if done {
                    channel.close()
                }
            }
        }
    }
}
