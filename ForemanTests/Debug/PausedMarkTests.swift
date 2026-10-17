import Foundation
import Testing

@testable import Foreman

/// What a `stopped` event opens (debug R5, R12) and when the paused line goes.
struct PausedMarkTests {
    private func source(_ path: String?) -> DAPSource {
        DAPSource(name: nil, path: path, sourceReference: nil)
    }

    @Test func aPathUnderTheRootOrOutsideItIsAFile() {
        #expect(
            StoppedTarget.resolve(source("/ws/Foreman/EditorFeature.swift"))
                == .file(URL(filePath: "/ws/Foreman/EditorFeature.swift")))
        // Outside the root: opened as is (read-only, editor R64).
        #expect(
            StoppedTarget.resolve(source("/Applications/Xcode.app/Foo.swiftinterface"))
                == .file(URL(filePath: "/Applications/Xcode.app/Foo.swiftinterface")))
        #expect(StoppedTarget.resolve(source("file:///ws/A.java")) == .file(URL(filePath: "/ws/A.java")))
    }

    @Test func aJdtURIIsALibrarySource() {
        let uri = "jdt://contents/spring-web-6.1.jar/org.springframework.web/RestTemplate.class?=ccoe"
        #expect(StoppedTarget.resolve(source(uri)) == .library(uri: uri))
    }

    @Test func noSourceOrAnUnknownSchemeOpensNothing() {
        for source in [source(nil), source(""), source("relative/A.swift"), source("http://evil/A.java")] {
            guard case .unavailable = StoppedTarget.resolve(source) else {
                Issue.record("\(String(describing: source)) should not open")
                continue
            }
        }
        // A source known only by `sourceReference` needs the `source` request: not in v1.
        guard case .unavailable = StoppedTarget.resolve(DAPSource(name: "x", path: nil, sourceReference: 4)) else {
            Issue.record("a sourceReference alone should not open")
            return
        }
    }

    /// `continued`, `terminated` and `exited` clear the mark; `output` and the others do not.
    @Test func eachEndingEventClearsTheMark() {
        let location = PausedMark.Location(url: URL(filePath: "/ws/A.swift"), line: 12)
        for event in ["continued", "terminated", "exited"] {
            var mark = PausedMark()
            mark.stopped(at: location)
            #expect(mark.line(in: URL(filePath: "/ws/A.swift")) == 12)
            mark.handle(event: event)
            #expect(mark.location == nil, "\(event)")
        }
        var mark = PausedMark()
        mark.stopped(at: location)
        mark.handle(event: "output")
        mark.handle(event: "breakpoint")
        #expect(mark.location == location)
        mark.clear()
        #expect(mark.location == nil)
    }

    @Test func theMarkIsForOneFileAndTheNewStopReplacesTheOld() {
        var mark = PausedMark()
        mark.stopped(at: .init(url: URL(filePath: "/ws/A.swift"), line: 3))
        #expect(mark.line(in: URL(filePath: "/ws/B.swift")) == nil)
        mark.stopped(at: .init(url: URL(filePath: "/ws/B.swift"), line: 9))
        #expect(mark.line(in: URL(filePath: "/ws/A.swift")) == nil)
        #expect(mark.line(in: URL(filePath: "/ws/./B.swift")) == 9)
    }

    /// debug R11: the adapter's own words, else what happened and the last line of `stderr`.
    @Test func theBannerCarriesTheAdaptersMessage() {
        #expect(
            DebugFeature.banner(
                for: DAPSession.Failure.rejected(command: "attach", message: "Connection refused"),
                standardError: "ignored") == "Connection refused")
        #expect(
            DebugFeature.banner(for: DAPSession.Failure.timeout("initialize"), standardError: "boom")
                == "no answer to initialize \u{2014} boom")
        #expect(
            DebugFeature.banner(for: DAPSession.Failure.closed, standardError: nil)
                == "the adapter closed the connection")
    }
}
