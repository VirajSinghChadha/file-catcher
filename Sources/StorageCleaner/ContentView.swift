import SwiftUI
import AppKit

enum ScanMode: String, CaseIterable, Identifiable {
    case bigFiles = "Big Files"
    case clutter = "Small File Clutter"
    var id: String { rawValue }
}

@MainActor
final class CleanerModel: ObservableObject {
    @Published var rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var mode: ScanMode = .bigFiles
    @Published var isScanning = false
    @Published var progressText = ""

    @Published var bigFiles: [FileEntry] = []
    @Published var clutterCategories: [ClutterCategory] = []

    @Published var selectedBigFiles: Set<String> = []
    @Published var selectedClutterFiles: Set<String> = []

    @Published var statusMessage = ""

    var totalSelectedSize: Int64 {
        switch mode {
        case .bigFiles:
            return bigFiles.filter { selectedBigFiles.contains($0.id) }.reduce(0) { $0 + $1.size }
        case .clutter:
            return clutterCategories.flatMap { $0.files }
                .filter { selectedClutterFiles.contains($0.id) }
                .reduce(0) { $0 + $1.size }
        }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = rootURL
        if panel.runModal() == .OK, let url = panel.url {
            rootURL = url
        }
    }

    func startScan() {
        isScanning = true
        statusMessage = ""
        switch mode {
        case .bigFiles:
            selectedBigFiles.removeAll()
            bigFiles.removeAll()
            let root = rootURL
            Task.detached(priority: .userInitiated) {
                let results = Scanner.scanAllFiles(root: root) { count in
                    Task { @MainActor in self.progressText = "Scanned \(count) files…" }
                }
                let top = results.sorted { $0.size > $1.size }.prefix(300)
                await MainActor.run {
                    self.bigFiles = Array(top)
                    self.isScanning = false
                    self.progressText = ""
                }
            }
        case .clutter:
            selectedClutterFiles.removeAll()
            clutterCategories.removeAll()
            Task.detached(priority: .userInitiated) {
                let categories = Scanner.scanClutterCategories { label in
                    Task { @MainActor in self.progressText = "Checking \(label)…" }
                }
                await MainActor.run {
                    self.clutterCategories = categories
                    self.isScanning = false
                    self.progressText = ""
                }
            }
        }
    }

    func deleteSelected() {
        switch mode {
        case .bigFiles:
            let toDelete = bigFiles.filter { selectedBigFiles.contains($0.id) }
            let (succeeded, failed) = Scanner.moveToTrash(toDelete)
            let succeededIDs = Set(succeeded.map { $0.id })
            bigFiles.removeAll { succeededIDs.contains($0.id) }
            selectedBigFiles.subtract(succeededIDs)
            statusMessage = summary(succeeded: succeeded.count, freed: succeeded.reduce(0) { $0 + $1.size }, failed: failed.count)
        case .clutter:
            let allSelected = clutterCategories.flatMap { $0.files }.filter { selectedClutterFiles.contains($0.id) }
            let (succeeded, failed) = Scanner.moveToTrash(allSelected)
            let succeededIDs = Set(succeeded.map { $0.id })
            for i in clutterCategories.indices {
                clutterCategories[i].files.removeAll { succeededIDs.contains($0.id) }
            }
            clutterCategories.removeAll { $0.files.isEmpty }
            selectedClutterFiles.subtract(succeededIDs)
            statusMessage = summary(succeeded: succeeded.count, freed: succeeded.reduce(0) { $0 + $1.size }, failed: failed.count)
        }
    }

    private func summary(succeeded: Int, freed: Int64, failed: Int) -> String {
        var text = "Moved \(succeeded) item(s) to Trash, freeing \(formatBytes(freed))."
        if failed > 0 { text += " \(failed) item(s) failed." }
        return text
    }
}

struct ContentView: View {
    @StateObject private var model = CleanerModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch model.mode {
            case .bigFiles:
                BigFilesView(model: model)
            case .clutter:
                ClutterView(model: model)
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("", selection: $model.mode) {
                    ForEach(ScanMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Spacer()

                Button("Choose Folder…") { model.pickFolder() }
                Text(model.rootURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260)

                Button {
                    model.startScan()
                } label: {
                    if model.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Scan")
                    }
                }
                .disabled(model.isScanning)
            }
            if !model.progressText.isEmpty {
                Text(model.progressText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            if !model.statusMessage.isEmpty {
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Selected: \(formatBytes(model.totalSelectedSize))")
                .font(.callout.bold())
            Button(role: .destructive) {
                model.deleteSelected()
            } label: {
                Text("Move to Trash")
            }
            .disabled(model.totalSelectedSize == 0)
        }
        .padding()
    }
}

struct BigFilesView: View {
    @ObservedObject var model: CleanerModel

    var body: some View {
        if model.bigFiles.isEmpty {
            ContentUnavailableView(
                "No scan results yet",
                systemImage: "externaldrive",
                description: Text("Choose a folder and click Scan to find the largest files.")
            )
        } else {
            List(model.bigFiles) { entry in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { model.selectedBigFiles.contains(entry.id) },
                        set: { isOn in
                            if isOn { model.selectedBigFiles.insert(entry.id) }
                            else { model.selectedBigFiles.remove(entry.id) }
                        }
                    ))
                    .labelsHidden()

                    VStack(alignment: .leading) {
                        Text(entry.name).font(.body)
                        Text(entry.path).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(formatBytes(entry.size)).font(.callout.monospacedDigit())
                }
            }
        }
    }
}

struct ClutterView: View {
    @ObservedObject var model: CleanerModel

    var body: some View {
        if model.clutterCategories.isEmpty {
            ContentUnavailableView(
                "No scan results yet",
                systemImage: "sparkles",
                description: Text("Click Scan to find caches, logs, and small files adding up.")
            )
        } else {
            List {
                ForEach(model.clutterCategories) { category in
                    Section {
                        ForEach(category.files.sorted { $0.size > $1.size }.prefix(200)) { entry in
                            HStack {
                                Toggle("", isOn: Binding(
                                    get: { model.selectedClutterFiles.contains(entry.id) },
                                    set: { isOn in
                                        if isOn { model.selectedClutterFiles.insert(entry.id) }
                                        else { model.selectedClutterFiles.remove(entry.id) }
                                    }
                                ))
                                .labelsHidden()
                                Text(entry.path).font(.caption).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(formatBytes(entry.size)).font(.caption.monospacedDigit())
                            }
                        }
                    } header: {
                        HStack {
                            Button {
                                let ids = Set(category.files.map { $0.id })
                                let allSelected = ids.isSubset(of: model.selectedClutterFiles)
                                if allSelected {
                                    model.selectedClutterFiles.subtract(ids)
                                } else {
                                    model.selectedClutterFiles.formUnion(ids)
                                }
                            } label: {
                                Text(category.title).font(.headline)
                            }
                            .buttonStyle(.plain)
                            Text("(\(category.count) files)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(formatBytes(category.totalSize)).font(.subheadline.bold())
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}
