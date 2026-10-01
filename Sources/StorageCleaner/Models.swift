import Foundation

struct FileEntry: Identifiable, Hashable {
    let id: String
    let url: URL
    let size: Int64

    init(url: URL, size: Int64) {
        self.url = url
        self.size = size
        self.id = url.path
    }

    var name: String { url.lastPathComponent }
    var path: String { url.path }
}

struct ClutterCategory: Identifiable {
    let id: String
    let title: String
    let detail: String
    var files: [FileEntry]

    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
    var count: Int { files.count }
}

func formatBytes(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0
    while value >= 1024, unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }
    if unitIndex == 0 {
        return "\(Int(value)) \(units[unitIndex])"
    }
    return String(format: "%.2f %@", value, units[unitIndex])
}
