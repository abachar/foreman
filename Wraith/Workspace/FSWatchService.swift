import CoreServices
import Foundation

/// One FSEvents stream per workspace, multiplexed to its subscribers (architecture: shared services).
///
/// Subscribers ask for the changes under a folder or on a file and receive batches of URLs: the
/// stream coalesces events for ~300 ms before emitting, so a burst of writes costs one batch. The
/// FSEvents stream is created on the first subscriber and released with the service.
actor FSWatchService {
    private let roots: [URL]
    private let debounce: Duration
    private var stream: FSEventStreamRef?
    private var subscribers: [UUID: Subscriber] = [:]
    private var pending: Set<URL> = []
    private var flush: Task<Void, Never>?

    /// `roots` are the folders the stream observes; `debounce` is how long a burst is coalesced.
    init(roots: [URL], debounce: Duration = .milliseconds(300)) {
        self.roots = roots
        self.debounce = debounce
    }

    isolated deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    /// Changes at `location` or below it, as batches of canonical URLs.
    func changes(under location: URL) -> AsyncStream<[URL]> {
        let id = UUID()
        let prefix = Self.normalized(location)
        let (stream, continuation) = AsyncStream<[URL]>.makeStream()
        subscribers[id] = Subscriber(prefix: prefix, continuation: continuation)
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
        guard stream == nil else { return }
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let paths = roots.map { $0.path(percentEncoded: false) } as CFArray
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        guard
            let created = FSEventStreamCreate(
                nil, fsEventsCallback, &context, paths, UInt64(kFSEventStreamEventIdSinceNow), 0.1, flags)
        else { return }
        FSEventStreamSetDispatchQueue(created, DispatchQueue(label: "dev.crafters.wraith.fswatch"))
        FSEventStreamStart(created)
        stream = created
    }

    /// Called from the FSEvents queue with the paths of one callback.
    fileprivate func record(_ paths: [String]) {
        for path in paths {
            pending.insert(URL(filePath: Self.normalized(URL(filePath: path))))
        }
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

/// C callback: hands the paths to the actor, whose reference travels in `info`.
nonisolated private let fsEventsCallback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
    // kFSEventStreamCreateFlagUseCFTypes: `eventPaths` is a CFArray of CFString, not a `char **`.
    guard let info, let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String]
    else { return }
    let service = Unmanaged<FSWatchService>.fromOpaque(info).takeUnretainedValue()
    let batch = Array(paths.prefix(count))
    Task { await service.record(batch) }
}
