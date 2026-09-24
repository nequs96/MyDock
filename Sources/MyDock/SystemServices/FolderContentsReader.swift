import Foundation

struct FolderContentsEntry: Identifiable, Hashable, Sendable {
    var url: URL
    var isDirectory: Bool
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

enum FolderContentsReader {
    static func entries(at folderURL: URL) throws -> [FolderContentsEntry] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return urls.map { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FolderContentsEntry(url: url, isDirectory: isDirectory)
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
