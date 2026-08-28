import AppKit

/// design R23: the per-type icon of a file, an entry of the Material Icon Theme set copied into
/// `Assets.xcassets` under `file-<name>`; a neutral file when nothing matches, one folder icon.
nonisolated enum FileIcon {
    static let assetPrefix = "file-"
    static let pointSize: CGFloat = 16

    /// Exact names first (case-insensitive), then the extension.
    private static let byName: [String: String] = [
        "dockerfile": "docker", ".gitignore": "git", ".gitattributes": "git", ".gitmodules": "git",
        "package.json": "npm", "package-lock.json": "npm", "yarn.lock": "yarn", "pnpm-lock.yaml": "pnpm",
        "bun.lockb": "bun", ".editorconfig": "editorconfig", "makefile": "makefile", "cmakelists.txt": "cmake",
        "pom.xml": "maven", "build.gradle": "gradle", "build.gradle.kts": "gradle", "settings.gradle": "gradle",
        "settings.gradle.kts": "gradle", "gemfile": "gemfile", "gemfile.lock": "gemfile", "nginx.conf": "nginx",
        "chart.yaml": "helm", ".babelrc": "babel", ".vimrc": "vim", "package.swift": "swift", ".env": "settings",
        ".prettierrc": "prettier", ".eslintrc": "eslint", "cargo.toml": "rust", "cargo.lock": "rust",
        "go.mod": "go", "go.sum": "go",
    ]

    private static let byPrefix: [(prefix: String, icon: String)] = [
        ("dockerfile", "docker"), ("readme", "readme"), ("license", "license"), ("tsconfig", "tsconfig"),
        ("vite.config", "vite"), ("webpack.config", "webpack"), ("jest.config", "jest"), (".prettierrc", "prettier"),
        (".eslintrc", "eslint"), ("eslint.config", "eslint"), (".env.", "settings"), ("docker-compose", "docker"),
    ]

    private static let byExtension: [String: String] = [
        "java": "java", "kt": "kotlin", "kts": "kotlin", "ts": "typescript", "mts": "typescript", "cts": "typescript",
        "tsx": "react", "jsx": "react", "js": "javascript", "mjs": "javascript", "cjs": "javascript",
        "json": "json", "jsonc": "json", "yaml": "yaml", "yml": "yaml", "toml": "toml", "md": "markdown",
        "markdown": "markdown", "sh": "console", "bash": "console", "zsh": "console", "swift": "swift",
        "html": "html", "htm": "html", "css": "css", "scss": "css", "sass": "css", "sql": "database",
        "py": "python", "rs": "rust", "go": "go", "xml": "xml", "plist": "xml", "storyboard": "xml", "xib": "xml",
        "svg": "svg", "png": "image", "jpg": "image", "jpeg": "image", "gif": "image", "webp": "image",
        "ico": "image", "icns": "image", "pdf": "pdf", "zip": "zip", "gz": "zip", "tar": "zip", "bz2": "zip",
        "xz": "zip", "7z": "zip", "ttf": "font", "otf": "font", "woff": "font", "woff2": "font", "lock": "lock",
        "log": "log", "txt": "document", "c": "c", "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "h": "h", "hpp": "hpp",
        "cs": "csharp", "rb": "ruby", "php": "php", "lua": "lua", "pl": "perl", "r": "r", "scala": "scala",
        "clj": "clojure", "ex": "elixir", "exs": "elixir", "erl": "erlang", "hs": "haskell", "dart": "dart",
        "vue": "vue", "svelte": "svelte", "graphql": "graphql", "gql": "graphql", "tf": "terraform", "jar": "jar",
        "war": "jar", "pem": "certificate", "crt": "certificate", "cer": "certificate", "key": "key",
        "properties": "settings", "conf": "settings", "ini": "settings", "cfg": "settings", "gradle": "gradle",
        "dockerfile": "docker", "vim": "vim",
    ]

    /// Every icon the mapping can return; the asset catalog holds exactly these.
    static var allIcons: Set<String> {
        Set(byName.values).union(byPrefix.map(\.icon)).union(byExtension.values).union([
            "file", "folder", "folder-open",
        ])
    }

    /// The asset name for `fileName`.
    static func name(for fileName: String) -> String {
        let lowered = fileName.lowercased()
        if let icon = byName[lowered] {
            return assetPrefix + icon
        }
        if let match = byPrefix.first(where: { lowered.hasPrefix($0.prefix) }) {
            return assetPrefix + match.icon
        }
        let ext = (lowered as NSString).pathExtension
        return assetPrefix + (byExtension[ext] ?? "file")
    }

    static func folder(isExpanded: Bool) -> String {
        assetPrefix + (isExpanded ? "folder-open" : "folder")
    }

    /// The colored image at the row size; `nil` for a name that is not a file icon.
    @MainActor
    static func image(named name: String) -> NSImage? {
        guard name.hasPrefix(assetPrefix), let image = NSImage(named: name)?.copy() as? NSImage else { return nil }
        image.isTemplate = false
        image.size = NSSize(width: pointSize, height: pointSize)
        return image
    }
}
