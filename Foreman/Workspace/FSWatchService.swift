import AsyncFileMonitor
import Foundation

/// One FSEvents stream per workspace, multiplexed to its subscribers (architecture: shared services).
///
/// Using AsyncFileMonitor because it owns the `FSEventStream` (creation, callback, lifecycle) and
/// multicasts it as `AsyncStream`s; what is left here is Foreman's contract: a subscriber asks for
/// the changes under a location and receives batches of canonical URLs, coalesced for ~300 ms so a
/// burst of writes costs one batch.
actor FSWatchService {
    private let monitor: FolderContentMonitor
    private let debounce: Duration
    private var source: Task<Void, Never>?
    private var subscribers: [UUID: Subscriber] = [:]
    private var pending: Set<URL> = []
    private var flush: Task<Void, Never>?

    /// `roots` are the folders observed; `debounce` is how long a burst is coalesced.
    init(roots: [URL], debounce: Duration = .milliseconds(300)) {
        monitor = FolderContentMonitor(paths: roots.map { $0.path(percentEncoded: false) }, latency: 0.1)
        self.debounce = debounce
    }

    isolated deinit {
        source?.cancel()
        flush?.cancel()
    }

    /// Changes at `location` or below it, as batches of canonical URLs.
    func changes(under location: URL) -> AsyncStream<[URL]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<[URL]>.makeStream()
        subscribers[id] = Subscriber(prefix: Self.normalized(location), continuation: continuation)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(id) }
        }
        startIfNeeded()
        return stream
    }

    private func remove(_ id: UUID) {
        subscribers[id] = nil
    }

    private func startIfNeeded() {
        guard source == nil else { return }
        let events = monitor.makeStream()
        source = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.record(event.eventPath)
            }
        }
    }

    private func record(_ path: String) {
        pending.insert(URL(filePath: Self.normalized(URL(filePath: path))))
        flush?.cancel()
        flush = Task { [debounce] in
            guard (try? await Task.sleep(for: debounce)) != nil else { return }
            emit()
        }
    }

    /// Foundation resolves `/var` to `/var` and FSEvents reports `/private/var`: both sides go
    /// through the same normalization so prefixes compare.
    private static func normalized(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private func emit() {
        let urls = pending.sorted { $0.path() < $1.path() }
        pending = []
        for subscriber in subscribers.values {
            let matching = urls.filter { subscriber.matches($0.path(percentEncoded: false)) }
            if !matching.isEmpty {
                subscriber.continuation.yield(matching)
            }
        }
    }
}

nonisolated private struct Subscriber {
    let prefix: String
    let continuation: AsyncStream<[URL]>.Continuation

    /// The location itself or anything below it; `/code` never matches `/codex`.
    func matches(_ path: String) -> Bool {
        path == prefix || path.hasPrefix(prefix + "/")
    }
}
