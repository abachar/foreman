import Foundation

/// editor R5: tab titles of one group; a name shared by two tabs gets its parent folder.
nonisolated enum EditorTitles {
    static func titles(for paths: [String]) -> [String] {
        let names = paths.map { ($0 as NSString).lastPathComponent }
        var counts: [String: Int] = [:]
        for name in names {
            counts[name, default: 0] += 1
        }
        return zip(paths, names).map { path, name in
            guard counts[name, default: 0] > 1 else { return name }
            let parent = (path as NSString).deletingLastPathComponent
            guard let folder = parent.split(separator: "/").last else { return name }
            return "\(folder)/\(name)"
        }
    }
}
