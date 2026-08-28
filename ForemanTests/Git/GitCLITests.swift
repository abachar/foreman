import Foundation
import Testing

@testable import Foreman

/// The pure parts of `GitCLI` (git R22, R26, R28; edge cases: version, `index.lock`).
struct GitCLITests {
    // MARK: - Environment (git R22, R26)

    @Test func passesOnlyWhatGitNeedsAndImposesTheNonInteractiveVariables() {
        let login = [
            "PATH": "/opt/homebrew/bin:/usr/bin", "HOME": "/Users/me", "SSH_AUTH_SOCK": "/tmp/agent",
            "LC_ALL": "fr_FR.UTF-8", "LANG": "fr_FR.UTF-8", "SSH_ASKPASS": "/usr/bin/askpass",
            "GIT_ASKPASS": "/usr/bin/askpass", "GIT_DIR": "/elsewhere", "GIT_SSH_COMMAND": "ssh -i key",
            "DISPLAY": ":0", "AWS_SECRET": "x",
        ]
        let environment = GitCLI.environment(from: login, forRead: true)
        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/bin")
        #expect(environment["HOME"] == "/Users/me")
        #expect(environment["SSH_AUTH_SOCK"] == "/tmp/agent")
        #expect(environment["GIT_SSH_COMMAND"] == "ssh -i key")
        #expect(environment["LC_ALL"] == "C")
        #expect(environment["GIT_TERMINAL_PROMPT"] == "0")
        #expect(environment["GIT_EDITOR"] == "true")
        #expect(environment["GIT_OPTIONAL_LOCKS"] == "0")
        for dropped in ["SSH_ASKPASS", "GIT_ASKPASS", "GIT_DIR", "DISPLAY", "AWS_SECRET", "LANG"] {
            #expect(environment[dropped] == nil, Comment(rawValue: "\(dropped) must not reach git"))
        }
    }

    @Test func writesDoNotDisableOptionalLocks() {
        #expect(GitCLI.environment(from: [:], forRead: false)["GIT_OPTIONAL_LOCKS"] == nil)
        #expect(GitCLI.environment(from: ["GIT_OPTIONAL_LOCKS": "0"], forRead: false)["GIT_OPTIONAL_LOCKS"] == nil)
    }

    // MARK: - Classifying stderr (git R28)

    @Test func recognisesTheInteractionsGitCouldNotHave() {
        let fixtures = [
            "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
            "git@github.com: Permission denied (publickey).\nfatal: Could not read from remote repository.",
            "fatal: could not read Password for 'https://me@github.com': terminal prompts disabled",
            "Host key verification failed.\nfatal: Could not read from remote repository.",
            "error: gpg failed to sign the data\nfatal: failed to write commit object",
        ]
        for stderr in fixtures {
            #expect(GitError.classify(stderr: stderr) == .needsInteraction, Comment(rawValue: stderr))
        }
    }

    @Test func recognisesNotARepoConflictsAndKeepsTheRestVerbatim() {
        #expect(
            GitError.classify(stderr: "fatal: not a git repository (or any of the parent directories): .git")
                == .notARepo)
        #expect(
            GitError.classify(stderr: "CONFLICT (content): Merge conflict in a.txt\nAutomatic merge failed;")
                == .conflict)
        #expect(GitError.classify(stderr: "error: could not apply 1a2b3c4... subject") == .conflict)
        #expect(
            GitError.classify(stderr: "  error: pathspec 'nope' did not match any file(s) known to git\n")
                == .commandFailed("error: pathspec 'nope' did not match any file(s) known to git"))
    }

    @Test func detectsALockedIndex() {
        #expect(
            GitError.isIndexLocked(
                stderr: "fatal: Unable to create '/repo/.git/index.lock': File exists.\n\nAnother git process seems"))
        #expect(!GitError.isIndexLocked(stderr: "fatal: bad revision"))
    }

    // MARK: - Version (edge cases)

    @Test func parsesTheVersionIncludingTheAppleSuffix() {
        #expect(GitVersion.parse("git version 2.39.5 (Apple Git-154)\n") == GitVersion(major: 2, minor: 39, patch: 5))
        #expect(GitVersion.parse("git version 2.47.1") == GitVersion(major: 2, minor: 47, patch: 1))
        #expect(GitVersion.parse("git version 3.0") == GitVersion(major: 3, minor: 0, patch: 0))
        #expect(GitVersion.parse("usage: git") == nil)
        #expect(GitVersion.parse("") == nil)
    }

    @Test func refusesBelow235() throws {
        #expect(try #require(GitVersion.parse("git version 2.34.1")).isSupported == false)
        #expect(try #require(GitVersion.parse("git version 2.35.0")).isSupported)
        #expect(try #require(GitVersion.parse("git version 2.39.5 (Apple Git-154)")).isSupported)
    }

    // MARK: - Resolving the binary (git R26)

    @Test func findsTheFirstGitOfThePathUnlessTheConfigOverridesIt() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GitCLITests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appending(path: "first")
        let second = root.appending(path: "second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let secondGit = second.appending(path: "git")
        try Data("#!/bin/sh\n".utf8).write(to: secondGit)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: secondGit.path())
        let path = "\(first.path()):\(second.path())"

        #expect(
            GitCLI.resolveExecutable(inPath: path, override: nil)?.standardizedFileURL == secondGit.standardizedFileURL)
        #expect(GitCLI.resolveExecutable(inPath: first.path(), override: nil) == nil)
        #expect(GitCLI.resolveExecutable(inPath: nil, override: nil) == nil)
        #expect(
            GitCLI.resolveExecutable(inPath: path, override: secondGit.path())?.standardizedFileURL
                == secondGit.standardizedFileURL)
        #expect(GitCLI.resolveExecutable(inPath: path, override: first.appending(path: "git").path()) == nil)
    }
}
