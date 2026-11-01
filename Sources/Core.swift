import Foundation
import AppKit
import Combine

// MARK: - Entry model

struct Entry: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String            // absolute path on disk, or path inside archive
    var isDir: Bool
    var size: Int64?
    var packed: Int64?
    var modified: Date?
    var attrs: String = ""
    var crc: String = ""
    var encrypted: Bool = false
    var isArchive: Bool = false

    var displayAttrs: String {
        if isDir { return "D...." }
        return "....A"
    }
}

enum Col: String, CaseIterable, Identifiable {
    case name, size, packed, modified, attrs, crc
    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "名称"
        case .size: return "大小"
        case .packed: return "压缩后大小"
        case .modified: return "修改日期"
        case .attrs: return "属性"
        case .crc: return "CRC"
        }
    }

    var width: CGFloat {
        switch self {
        case .name: return 260
        case .size: return 86
        case .packed: return 92
        case .modified: return 124
        case .attrs: return 84
        case .crc: return 90
        }
    }

    var trailing: Bool {
        switch self {
        case .size, .packed: return true
        default: return false
        }
    }
}

enum ArchiveFormats {
    static let ext: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz",
        "zst", "tzst", "lzma", "cab", "iso", "jar", "war", "apk", "xar", "cpio",
        "rpm", "deb", "lzh", "lha", "arj", "wim", "chm", "msi", "z", "ar", "dmg",
        "pkg", "lz", "zstd", "7zip", "zipx"
    ]

    static func isArchive(_ url: URL) -> Bool {
        ext.contains(url.pathExtension.lowercased())
    }

    static func isArchiveName(_ name: String) -> Bool {
        ext.contains((name as NSString).pathExtension.lowercased())
    }
}

// MARK: - 7-Zip engine

final class TaskHandle {
    let process = Process()
    private(set) var isCancelled = false
    func cancel() {
        isCancelled = true
        if process.isRunning { process.terminate() }
    }
}

final class Engine {
    static let shared = Engine()

    let binary: URL?
    private(set) var versionText: String = ""

    private init() {
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("7zz"))
            candidates.append(res.appendingPathComponent("bin/7zz"))
        }
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/7zz"),
            URL(fileURLWithPath: "/usr/local/bin/7zz"),
            URL(fileURLWithPath: "/opt/homebrew/bin/7z"),
            URL(fileURLWithPath: "/usr/local/bin/7z"),
            URL(fileURLWithPath: "/usr/bin/7zz")
        ])
        binary = candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        if binary != nil {
            let r = run([], handle: nil, onProgress: nil)
            versionText = r.output
                .split(separator: "\n")
                .first(where: { $0.contains("7-Zip") })
                .map(String.init) ?? ""
        }
    }

    var isAvailable: Bool { binary != nil }

    /// Runs 7zz synchronously on the calling thread. Call from a background queue.
    @discardableResult
    func run(_ args: [String],
             workingDirectory: URL? = nil,
             handle: TaskHandle? = nil,
             onProgress: ((Double, String) -> Void)? = nil) -> (status: Int32, output: String) {
        guard let binary else { return (-1, "7zz 未找到") }
        let p = handle?.process ?? Process()
        p.executableURL = binary
        p.arguments = args
        if let wd = workingDirectory { p.currentDirectoryURL = wd }
        p.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        do { try p.run() } catch { return (-1, "无法启动 7zz: \(error.localizedDescription)") }

        let fh = pipe.fileHandleForReading
        var raw = Data()
        var pending = ""
        var lastLine = ""
        var lastPercent: Double?

        while true {
            let chunk = fh.availableData
            if chunk.isEmpty { break }
            raw.append(chunk)
            if let s = String(data: chunk, encoding: .utf8) {
                pending += s
                var lines: [String] = []
                var cur = ""
                for ch in pending {
                    if ch == "\n" || ch == "\r" {
                        lines.append(cur); cur = ""
                    } else if ch == "\u{8}" {
                        // backspace: 7-Zip rewrites percentages in place
                        if !cur.isEmpty { cur.removeLast() }
                    } else {
                        cur.append(ch)
                    }
                }
                pending = cur
                for line in lines {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { continue }
                    lastLine = t
                    if let pct = Self.percent(in: t) {
                        lastPercent = pct
                        onProgress?(pct / 100.0, lastLine)
                    } else if onProgress != nil {
                        onProgress?(lastPercent.map { $0 / 100.0 } ?? 0, t)
                    }
                }
            }
        }
        p.waitUntilExit()
        let output = String(data: raw, encoding: .utf8) ?? ""
        return (p.terminationStatus, output)
    }

    static func percent(in line: String) -> Double? {
        guard line.contains("%") else { return nil }
        var digits = ""
        for ch in line {
            if ch.isNumber { digits.append(ch) }
            else if ch == "%" { break }
            else { digits = "" }
        }
        if digits.isEmpty { return nil }
        return Double(digits)
    }

    // MARK: Listing

    struct ParsedArchive {
        var summary: [(String, String)] = []
        var entries: [Entry] = []
    }

    func listArchive(path: URL, password: String?) -> (ParsedArchive?, Int32, String) {
        var args = ["l", "-slt", path.path]
        if let password, !password.isEmpty { args.append("-p\(password)") }
        let r = run(args)
        let parsed = Self.parseListing(r.output)
        return (parsed, r.status, r.output)
    }

    static func parseListing(_ output: String) -> ParsedArchive {
        var result = ParsedArchive()
        let blocks = output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            var kv: [(String, String)] = []
            for line in lines {
                guard let range = line.range(of: " = ") else { continue }
                let key = String(line[line.startIndex..<range.lowerBound])
                let value = String(line[range.upperBound...])
                kv.append((key, value))
            }
            guard !kv.isEmpty else { continue }

            func value(_ key: String) -> String? {
                kv.first(where: { $0.0 == key })?.1
            }

            if value("Type") != nil && value("Attributes") == nil {
                // archive summary block
                result.summary = kv.filter { !$0.1.isEmpty }
                continue
            }

            guard let p = value("Path"), !p.isEmpty else { continue }
            let path = p.hasSuffix("/") ? String(p.dropLast()) : p
            if path.isEmpty { continue }

            let isFolder = (value("Folder") == "+") || (value("Attributes")?.hasPrefix("D") ?? false)
            let name = (path as NSString).lastPathComponent
            var modified: Date?
            if let m = value("Modified"), m.count >= 19 {
                let stamp = String(m.prefix(19))
                modified = Fmt.stampParser.date(from: stamp)
            }
            let entry = Entry(
                name: name,
                path: path,
                isDir: isFolder,
                size: isFolder ? nil : value("Size").flatMap { Int64($0) },
                packed: value("Packed Size").flatMap { Int64($0) },
                modified: modified,
                attrs: isFolder ? "D...." : "....A",
                crc: value("CRC") ?? "",
                encrypted: value("Encrypted") == "+",
                isArchive: !isFolder && ArchiveFormats.isArchiveName(name)
            )
            result.entries.append(entry)
        }
        result.entries = synthesizeFolders(result.entries)
        return result
    }

    /// Archives made by some tools have files without their parent folder entries.
    static func synthesizeFolders(_ entries: [Entry]) -> [Entry] {
        let known = Set(entries.filter { $0.isDir }.map { $0.path })
        var existing = known
        var synthesized: [Entry] = []
        for e in entries where !e.isDir {
            var parent = (e.path as NSString).deletingLastPathComponent
            var chain: [String] = []
            while !parent.isEmpty && parent != "." && !existing.contains(parent) {
                chain.append(parent)
                existing.insert(parent)
                let up = (parent as NSString).deletingLastPathComponent
                if up == parent { break }
                parent = up
            }
            for dir in chain.reversed() {
                synthesized.append(Entry(name: (dir as NSString).lastPathComponent,
                                         path: dir, isDir: true))
            }
        }
        return entries + synthesized
    }

    // MARK: Commands

    func extract(archive: URL, to dest: URL, entries: [String], password: String?,
                 overwrite: OverwriteMode, keepStructure: Bool = true, handle: TaskHandle,
                 onProgress: @escaping (Double, String) -> Void) -> (Int32, String) {
        var args = [keepStructure ? "x" : "e", archive.path, "-o\(dest.path)", "-y", "-bsp1", "-bb1"]
        switch overwrite {
        case .overwrite: break
        case .skip: args.append("-aos")
        case .rename: args.append("-aou")
        }
        if let password, !password.isEmpty { args.append("-p\(password)") }
        args.append(contentsOf: entries)
        return run(args, handle: handle, onProgress: onProgress)
    }

    func add(archive: URL, sourceDir: URL, files: [String], type: String, level: Int,
             password: String?, encryptNames: Bool, updateMode: UpdateMode,
             volumeMB: Int?, handle: TaskHandle,
             onProgress: @escaping (Double, String) -> Void) -> (Int32, String) {
        var args = ["a", archive.path, "-t\(type)", "-mx=\(level)", "-bsp1", "-bb1", "-y"]
        switch updateMode {
        case .addReplace: break
        case .addOnly: args.append("-up0q0r2x1y2z1w2")
        case .sync: args.append("-u-")
        }
        if let password, !password.isEmpty {
            args.append("-p\(password)")
            if encryptNames { args.append("-mhe=on") }
        }
        if let v = volumeMB, v > 0 { args.append("-v\(v)m") }
        args.append(contentsOf: files)
        return run(args, workingDirectory: sourceDir, handle: handle, onProgress: onProgress)
    }

    func test(archive: URL, password: String?, handle: TaskHandle,
              onProgress: @escaping (Double, String) -> Void) -> (Int32, String) {
        var args = ["t", archive.path, "-bsp1", "-bb1"]
        if let password, !password.isEmpty { args.append("-p\(password)") }
        return run(args, handle: handle, onProgress: onProgress)
    }
}

enum OverwriteMode: String, CaseIterable, Identifiable {
    case overwrite, skip, rename
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overwrite: return "覆盖所有文件"
        case .skip: return "跳过已存在文件"
        case .rename: return "自动重命名"
        }
    }
}

enum UpdateMode: String, CaseIterable, Identifiable {
    case addReplace, addOnly, sync
    var id: String { rawValue }
    var title: String {
        switch self {
        case .addReplace: return "添加并替换文件"
        case .addOnly: return "仅添加新文件"
        case .sync: return "同步文件"
        }
    }
}

// MARK: - Dialogs

enum Dialog: Equatable {
    case add
    case extract
    case info
    case about
    case password(archive: String, thenExtract: Bool)
    case newFolder
    case rename(path: String, current: String)
    case options
}

struct RunState {
    var title: String
    var detail: String = ""
    var progress: Double? = nil
    var handle: TaskHandle
}

// MARK: - Tree rows

struct TreeRow: Identifiable {
    var id: String { "\(kind)-\(path)" }
    enum Kind { case volume, folder, archive, archiveFolder }
    var kind: Kind
    var name: String
    var path: String
    var depth: Int
    var hasChildren: Bool
    var expanded: Bool
    var isCurrent: Bool
}

// MARK: - App state

final class AppState: ObservableObject {
    @Published var mode: Mode = .filesystem
    @Published var fsPath: String = NSHomeDirectory()
    @Published var archiveURL: URL?
    @Published var archivePath: String = ""      // internal folder ("" = root)
    @Published var entries: [Entry] = []
    @Published var selection: Set<String> = []
    @Published var statusLeft: String = ""
    @Published var statusRight: String = ""
    @Published var dialog: Dialog?
    @Published var run: RunState?
    @Published var showHidden: Bool = false
    @Published var sortCol: Col = .name
    @Published var sortAsc: Bool = true
    @Published var treeRows: [TreeRow] = []
    @Published var treeWidth: CGFloat = Metrics.treeWidth
    @Published var errorText: String?
    @Published var password: String = ""
    @Published var lastExtractDir: String = NSHomeDirectory()
    @Published var columnWidths: [String: CGFloat] = [:]
    @Published var showToolbar = true
    @Published var showTree = true

    private var allArchiveEntries: [Entry] = []
    private var archiveSummary: [(String, String)] = []
    private var expanded: Set<String> = []
    private var childCache: [String: [TreeRow]] = [:]
    var anchorIndex: Int?

    enum Mode: Equatable { case filesystem, archive }

    init() {
        fsPath = UserDefaults.standard.string(forKey: "lastPath") ?? NSHomeDirectory()
        showHidden = UserDefaults.standard.bool(forKey: "showHidden")
        if let raw = UserDefaults.standard.string(forKey: "sortCol"), let c = Col(rawValue: raw) {
            sortCol = c
        }
        sortAsc = UserDefaults.standard.object(forKey: "sortAsc") == nil
            ? true : UserDefaults.standard.bool(forKey: "sortAsc")
        lastExtractDir = UserDefaults.standard.string(forKey: "lastExtractDir") ?? NSHomeDirectory()
        if let data = UserDefaults.standard.dictionary(forKey: "columnWidths") {
            for (k, v) in data { if let d = v as? Double { columnWidths[k] = CGFloat(d) } }
        }
        for c in Col.allCases where columnWidths[c.rawValue] == nil {
            columnWidths[c.rawValue] = c.width
        }
        refresh()
        rebuildTree()
    }

    // MARK: Paths

    var displayPath: String {
        switch mode {
        case .filesystem:
            return fsPath
        case .archive:
            let base = archiveURL?.path ?? ""
            if archivePath.isEmpty { return base }
            return base + "/" + archivePath
        }
    }

    var currentTitle: String {
        switch mode {
        case .filesystem: return (fsPath as NSString).lastPathComponent
        case .archive:
            return archivePath.isEmpty
                ? (archiveURL?.lastPathComponent ?? "")
                : (archivePath as NSString).lastPathComponent
        }
    }

    // MARK: Listing

    func refresh() {
        switch mode {
        case .filesystem: loadFileSystem()
        case .archive: loadArchiveFolder()
        }
        recomputeStatus()
        rebuildTree()
    }

    private func loadFileSystem() {
        let fm = FileManager.default
        var result: [Entry] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]
        if let names = try? fm.contentsOfDirectory(atPath: fsPath) {
            for name in names {
                if !showHidden && name.hasPrefix(".") { continue }
                let full = (fsPath as NSString).appendingPathComponent(name)
                let url = URL(fileURLWithPath: full)
                let values = try? url.resourceValues(forKeys: Set(keys))
                let isDir = values?.isDirectory ?? false
                var size: Int64? = nil
                if !isDir {
                    if let s = values?.fileSize { size = Int64(s) }
                }
                result.append(Entry(
                    name: name,
                    path: full,
                    isDir: isDir,
                    size: size,
                    packed: nil,
                    modified: values?.contentModificationDate,
                    attrs: isDir ? "D...." : "....A",
                    crc: "",
                    encrypted: false,
                    isArchive: ArchiveFormats.isArchive(url)
                ))
            }
        }
        entries = sort(result)
    }

    private func loadArchiveFolder() {
        let children = allArchiveEntries.filter { parentPath($0.path) == archivePath }
        var result = children
        // add ".." style navigation handled by goUp(); no synthetic entry needed
        if children.isEmpty && !archivePath.isEmpty {
            // some archives are flat-listed; fall back to prefix matching
            let prefix = archivePath + "/"
            result = allArchiveEntries.filter {
                $0.path.hasPrefix(prefix) && !$0.path.dropFirst(prefix.count).contains("/")
            }
        }
        entries = sort(result)
    }

    private func parentPath(_ p: String) -> String {
        let parent = (p as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }

    func sort(_ list: [Entry]) -> [Entry] {
        let asc = sortAsc
        let col = sortCol
        return list.sorted { a, b in
            if a.isDir != b.isDir { return a.isDir && b.isDir } // folders first
            var result: Bool
            switch col {
            case .name:
                result = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size:
                result = (a.size ?? -1) < (b.size ?? -1)
            case .packed:
                result = (a.packed ?? -1) < (b.packed ?? -1)
            case .modified:
                result = (a.modified ?? .distantPast) < (b.modified ?? .distantPast)
            case .attrs:
                result = a.attrs < b.attrs
            case .crc:
                result = a.crc < b.crc
            }
            if (col == .name) { return asc ? result : !result }
            if a.isDir != b.isDir { return a.isDir }
            return asc ? result : !result
        }
    }

    func toggleSort(_ col: Col) {
        if sortCol == col { sortAsc.toggle() } else { sortCol = col; sortAsc = true }
        UserDefaults.standard.set(sortCol.rawValue, forKey: "sortCol")
        UserDefaults.standard.set(sortAsc, forKey: "sortAsc")
        refresh()
    }

    func setColumnWidth(_ col: Col, _ w: CGFloat) {
        columnWidths[col.rawValue] = max(40, w)
        UserDefaults.standard.set(columnWidths.mapValues { Double($0) }, forKey: "columnWidths")
    }

    // MARK: Navigation

    func navigate(to path: String) {
        if mode == .archive {
            archivePath = path
            selection = []
            loadArchiveFolder()
            recomputeStatus()
            rebuildTree()
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
        fsPath = (path as NSString).standardizingPath
        selection = []
        UserDefaults.standard.set(fsPath, forKey: "lastPath")
        loadFileSystem()
        recomputeStatus()
        rebuildTree()
    }

    func goUp() {
        switch mode {
        case .filesystem:
            let parent = (fsPath as NSString).deletingLastPathComponent
            if !parent.isEmpty && parent != fsPath { navigate(to: parent) }
        case .archive:
            if archivePath.isEmpty {
                closeArchive()
            } else {
                navigate(to: parentPath(archivePath))
            }
        }
    }

    func open(_ entry: Entry) {
        if entry.isDir {
            navigate(to: entry.path)
            return
        }
        if mode == .archive {
            if entry.isArchive {
                extractAndOpen(entry)
            } else {
                extractAndOpen(entry)
            }
            return
        }
        let url = URL(fileURLWithPath: entry.path)
        if ArchiveFormats.isArchive(url) {
            openArchive(url, password: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func openArchive(_ url: URL, password: String?) {
        guard Engine.shared.isAvailable else {
            errorText = "找不到 7zz 可执行文件。"
            return
        }
        let result = Engine.shared.listArchive(path: url, password: password)
        if let parsed = result.0, !parsed.entries.isEmpty || result.1 == 0 {
            allArchiveEntries = parsed.entries
            archiveSummary = parsed.summary
            archiveURL = url
            archivePath = ""
            mode = .archive
            selection = []
            loadArchiveFolder()
            recomputeStatus()
            rebuildTree()
            return
        }
        let out = result.2
        if out.contains("Enter password") || out.lowercased().contains("password") {
            self.password = ""
            dialog = .password(archive: url.path, thenExtract: false)
        } else {
            errorText = "无法打开压缩包：\n" + out.split(separator: "\n").suffix(6).joined(separator: "\n")
        }
    }

    func closeArchive() {
        mode = .filesystem
        archiveURL = nil
        archivePath = ""
        allArchiveEntries = []
        archiveSummary = []
        selection = []
        loadFileSystem()
        recomputeStatus()
        rebuildTree()
    }

    // MARK: Selection / status

    func select(_ entry: Entry, modifiers: NSEvent.ModifierFlags) {
        guard let idx = entries.firstIndex(of: entry) else { return }
        if modifiers.contains(.shift), let anchor = anchorIndex, anchor < entries.count {
            let range = anchor <= idx ? anchor...idx : idx...anchor
            selection = Set(entries[range].map { $0.path })
        } else if modifiers.contains(.command) {
            if selection.contains(entry.path) { selection.remove(entry.path) } else { selection.insert(entry.path) }
            anchorIndex = idx
        } else {
            selection = [entry.path]
            anchorIndex = idx
        }
        recomputeStatus()
    }

    func selectAll() {
        selection = Set(entries.map { $0.path })
        recomputeStatus()
    }

    func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        let current = entries.firstIndex { selection.contains($0.path) }
        var next: Int
        if let c = current {
            next = min(max(0, c + delta), entries.count - 1)
        } else {
            next = delta > 0 ? 0 : entries.count - 1
        }
        if delta > 1 { next = min(entries.count - 1, next) }
        selection = [entries[next].path]
        anchorIndex = next
        recomputeStatus()
    }

    var selectedEntries: [Entry] {
        entries.filter { selection.contains($0.path) }
    }

    private func recomputeStatus() {
        let files = entries.filter { !$0.isDir }
        let dirs = entries.filter { $0.isDir }
        let total = files.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        var text = "\(entries.count) 个对象"
        text += "  (\(files.count) 个文件, \(dirs.count) 个文件夹)"
        text += "    \(Fmt.size(total)) 字节"
        statusLeft = text

        let sel = selectedEntries
        if sel.isEmpty {
            statusRight = ""
        } else {
            let size = sel.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
            statusRight = "已选择 \(sel.count) 个对象，共 \(Fmt.size(size)) 字节"
        }
    }

    // MARK: Tree

    func rebuildTree() {
        if mode == .archive {
            treeRows = archiveTreeRows()
            return
        }
        var rows: [TreeRow] = []
        let roots = rootNodes()
        for root in roots {
            appendTree(&rows, node: root, depth: 0)
        }
        treeRows = rows
    }

    private func rootNodes() -> [(String, String)] {
        var nodes: [(String, String)] = []
        let home = NSHomeDirectory()
        nodes.append((home, "主目录"))
        let volumeName = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "Macintosh HD"
        nodes.append(("/", volumeName))
        return nodes
    }

    private func appendTree(_ rows: inout [TreeRow], node: (String, String), depth: Int) {
        let (path, name) = node
        let key = "fs|\(path)"
        let children = subdirectories(of: path)
        let isExpanded = expanded.contains(key)
        rows.append(TreeRow(kind: depth == 0 ? .volume : .folder,
                            name: name,
                            path: path,
                            depth: depth,
                            hasChildren: !children.isEmpty,
                            expanded: isExpanded,
                            isCurrent: mode == .filesystem && fsPath == path))
        if isExpanded {
            for child in children {
                appendTree(&rows, node: (child.path, child.name), depth: depth + 1)
            }
        }
    }

    private func subdirectories(of path: String) -> [(name: String, path: String)] {
        if let cached = childCache["fs|\(path)"] {
            return cached.map { ($0.name, $0.path) }
        }
        var result: [(String, String)] = []
        if let names = try? FileManager.default.contentsOfDirectory(atPath: path) {
            for n in names {
                if n.hasPrefix(".") { continue }
                let full = (path as NSString).appendingPathComponent(n)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                    result.append((n, full))
                }
            }
        }
        result.sort { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
        childCache["fs|\(path)"] = result.map { TreeRow(kind: .folder, name: $0.0, path: $0.1, depth: 0, hasChildren: false, expanded: false, isCurrent: false) }
        return result
    }

    func toggleTree(_ row: TreeRow) {
        let key = "fs|\(row.path)"
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
        rebuildTree()
    }

    func expandTree(to path: String) {
        var p = path
        while p != "/" && !p.isEmpty {
            p = (p as NSString).deletingLastPathComponent
            if !p.isEmpty { expanded.insert("fs|\(p)") }
        }
        rebuildTree()
    }

    private func archiveTreeRows() -> [TreeRow] {
        guard let url = archiveURL else { return [] }
        let rootKey = "ar|"
        var rows: [TreeRow] = []
        let children = archiveSubfolders(of: "")
        rows.append(TreeRow(kind: .archive, name: url.lastPathComponent, path: "",
                            depth: 0, hasChildren: !children.isEmpty,
                            expanded: expanded.contains(rootKey), isCurrent: archivePath.isEmpty))
        if expanded.contains(rootKey) {
            appendArchiveRows(&rows, parent: "", depth: 1)
        }
        return rows
    }

    private func appendArchiveRows(_ rows: inout [TreeRow], parent: String, depth: Int) {
        for dir in archiveSubfolders(of: parent) {
            let key = "ar|\(dir.path)"
            let kids = archiveSubfolders(of: dir.path)
            rows.append(TreeRow(kind: .archiveFolder, name: dir.name, path: dir.path,
                                depth: depth, hasChildren: !kids.isEmpty,
                                expanded: expanded.contains(key),
                                isCurrent: archivePath == dir.path))
            if expanded.contains(key) {
                appendArchiveRows(&rows, parent: dir.path, depth: depth + 1)
            }
        }
    }

    private func archiveSubfolders(of parent: String) -> [Entry] {
        allArchiveEntries
            .filter { $0.isDir && parentPath($0.path) == parent }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func toggleArchiveTree(_ row: TreeRow) {
        let key = "ar|\(row.path)"
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
        rebuildTree()
    }

    // MARK: Operations

    func requestExtract() {
        guard mode == .archive, let url = archiveURL else { return }
        if selection.isEmpty {
            lastExtractDir = defaultExtractDir(for: url)
        }
        dialog = .extract
    }

    private func defaultExtractDir(for url: URL) -> String {
        let base = url.deletingLastPathComponent().path
        let name = url.deletingPathExtension().lastPathComponent
        return (base as NSString).appendingPathComponent(name)
    }

    func performExtract(dest: String, overwrite: OverwriteMode, password: String, keepStructure: Bool) {
        guard let url = archiveURL else { return }
        let items = selection.isEmpty ? [] : selectedEntries.map { $0.path }
        let handle = TaskHandle()
        run = RunState(title: "正在提取", detail: "准备中…", progress: 0, handle: handle)
        lastExtractDir = dest
        UserDefaults.standard.set(dest, forKey: "lastExtractDir")

        DispatchQueue.global().async {
            try? FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
            let r = Engine.shared.extract(archive: url, to: URL(fileURLWithPath: dest),
                                          entries: items, password: password,
                                          overwrite: overwrite, keepStructure: keepStructure,
                                          handle: handle) { pct, line in
                DispatchQueue.main.async {
                    self.run?.progress = pct
                    self.run?.detail = line
                }
            }
            DispatchQueue.main.async {
                self.run = nil
                if handle.isCancelled { return }
                if r.0 != 0 && r.0 != 1 {
                    self.errorText = "提取失败（代码 \(r.0)）\n" + r.1.split(separator: "\n").suffix(8).joined(separator: "\n")
                } else {
                    self.closeArchive()
                    self.navigate(to: dest)
                }
            }
        }
    }

    func performAdd(archivePath: String, type: String, level: Int, password: String,
                    encryptNames: Bool, updateMode: UpdateMode, volumeMB: Int?) {
        let sources = selectedEntries
        guard !sources.isEmpty else { return }
        let first = URL(fileURLWithPath: sources[0].path)
        let baseDir = first.deletingLastPathComponent()
        let files = sources.map { $0.name }
        let target = archivePath.hasPrefix("/")
            ? URL(fileURLWithPath: archivePath)
            : baseDir.appendingPathComponent(archivePath)

        let handle = TaskHandle()
        run = RunState(title: "正在创建压缩包", detail: "准备中…", progress: 0, handle: handle)

        DispatchQueue.global().async {
            let r = Engine.shared.add(archive: target, sourceDir: baseDir, files: files,
                                      type: type, level: level, password: password,
                                      encryptNames: encryptNames, updateMode: updateMode,
                                      volumeMB: volumeMB, handle: handle) { pct, line in
                DispatchQueue.main.async {
                    self.run?.progress = pct
                    self.run?.detail = line
                }
            }
            DispatchQueue.main.async {
                self.run = nil
                if handle.isCancelled { return }
                if r.0 != 0 {
                    self.errorText = "创建压缩包失败（代码 \(r.0)）\n" + r.1.split(separator: "\n").suffix(8).joined(separator: "\n")
                } else {
                    self.refresh()
                }
            }
        }
    }

    func performTest(password: String) {
        guard let url = archiveURL else { return }
        let handle = TaskHandle()
        run = RunState(title: "正在测试压缩包", detail: "准备中…", progress: 0, handle: handle)
        DispatchQueue.global().async {
            let r = Engine.shared.test(archive: url, password: password, handle: handle) { pct, line in
                DispatchQueue.main.async {
                    self.run?.progress = pct
                    self.run?.detail = line
                }
            }
            DispatchQueue.main.async {
                self.run = nil
                if handle.isCancelled { return }
                let ok = r.0 == 0
                let alert = NSAlert()
                alert.messageText = ok ? "测试完成" : "测试失败"
                alert.informativeText = ok
                    ? "压缩包 \(url.lastPathComponent) 无错误。"
                    : r.1.split(separator: "\n").suffix(8).joined(separator: "\n")
                alert.alertStyle = ok ? .informational : .warning
                alert.runModal()
            }
        }
    }

    func extractAndOpen(_ entry: Entry) {
        guard let url = archiveURL else { return }
        let cache = NSHomeDirectory() + "/Library/Caches/7zfm"
        let handle = TaskHandle()
        run = RunState(title: "正在打开", detail: entry.name, progress: nil, handle: handle)
        DispatchQueue.global().async {
            let r = Engine.shared.extract(archive: url, to: URL(fileURLWithPath: cache),
                                          entries: [entry.path], password: "",
                                          overwrite: .overwrite, handle: handle) { _, _ in }
            DispatchQueue.main.async {
                self.run = nil
                if r.0 == 0 || r.0 == 1 {
                    let f = URL(fileURLWithPath: cache).appendingPathComponent(entry.path)
                    NSWorkspace.shared.open(f)
                } else {
                    self.errorText = "无法打开文件：\n" + r.1.split(separator: "\n").suffix(6).joined(separator: "\n")
                }
            }
        }
    }

    func deleteSelected() {
        guard mode == .filesystem, !selection.isEmpty else { return }
        let items = selectedEntries
        let alert = NSAlert()
        alert.messageText = "删除 \(items.count) 个项目？"
        alert.informativeText = "这些项目将被移到废纸篓。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for item in items {
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
        }
        selection = []
        refresh()
    }

    func copyOrMove(move: Bool) {
        guard mode == .filesystem, !selection.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = move ? "移动" : "复制"
        panel.message = move ? "选择移动到的目标文件夹" : "选择复制到的目标文件夹"
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        let items = selectedEntries
        for item in items {
            let target = dest.appendingPathComponent(item.name)
            do {
                if FileManager.default.fileExists(atPath: target.path) {
                    let alert = NSAlert()
                    alert.messageText = "目标已存在：\(item.name)"
                    alert.informativeText = "要替换它吗？"
                    alert.addButton(withTitle: "替换")
                    alert.addButton(withTitle: "跳过")
                    if alert.runModal() != .alertFirstButtonReturn { continue }
                    try FileManager.default.removeItem(at: target)
                }
                if move {
                    try FileManager.default.moveItem(atPath: item.path, toPath: target.path)
                } else {
                    try FileManager.default.copyItem(atPath: item.path, toPath: target.path)
                }
            } catch {
                errorText = "操作失败：\(error.localizedDescription)"
            }
        }
        selection = []
        refresh()
    }

    func createFolder(named name: String) {
        let base = mode == .filesystem ? fsPath : ""
        guard !base.isEmpty else { return }
        let target = (base as NSString).appendingPathComponent(name)
        try? FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: false)
        refresh()
    }

    func renameSelected(to newName: String) {
        guard mode == .filesystem, let first = selectedEntries.first else { return }
        let dir = (first.path as NSString).deletingLastPathComponent
        let target = (dir as NSString).appendingPathComponent(newName)
        try? FileManager.default.moveItem(atPath: first.path, toPath: target)
        selection = [target]
        refresh()
    }

    func addSelectedPath() {
        guard mode == .archive, let url = archiveURL else { return }
        dialog = .add
        _ = url
    }

    private static let summaryNames: [String: String] = [
        "Path": "路径",
        "Type": "类型",
        "Physical Size": "物理大小",
        "Headers Size": "头大小",
        "Method": "压缩方法",
        "Solid": "固实",
        "Blocks": "块数",
        "Created": "创建时间",
        "Modified": "修改时间",
        "Volumes": "分卷数",
        "Total Physical Size": "总物理大小",
        "Comment": "注释",
        "Characteristics": "特性"
    ]

    func summary() -> [(String, String)] {
        guard mode == .archive else { return [] }
        return archiveSummary.map { (Self.summaryNames[$0.0] ?? $0.0, $0.1) }
    }

    func entryInfo() -> [(String, String)] {
        if mode == .filesystem, let e = selectedEntries.first {
            return [
                ("名称", e.name),
                ("路径", e.path),
                ("类型", e.isDir ? "文件夹" : "文件"),
                ("大小", Fmt.size(e.size) + " 字节"),
                ("修改日期", Fmt.date(e.modified))
            ]
        }
        if let e = selectedEntries.first, mode == .archive {
            return [
                ("路径", e.path),
                ("大小", Fmt.size(e.size) + " 字节"),
                ("压缩后大小", Fmt.size(e.packed)),
                ("修改日期", Fmt.date(e.modified)),
                ("CRC", e.crc),
                ("加密", e.encrypted ? "是" : "否")
            ]
        }
        return summary()
    }
}
