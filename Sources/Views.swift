import SwiftUI
import AppKit

// MARK: - In-window menu bar (Windows style)

struct MItem: Identifiable {
    let id = UUID()
    var title: String = ""
    var shortcut: String = ""
    var isSeparator: Bool = false
    var checked: Bool? = nil
    var enabled: Bool = true
    var action: () -> Void = {}
}

struct MenuStrip: View {
    @ObservedObject var s: AppState
    @Binding var open: String?
    @State private var frames: [String: CGRect] = [:]

    private var titles: [String] { ["文件", "编辑", "查看", "工具", "帮助"] }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(titles, id: \.self) { t in
                    Text(t)
                        .font(WFont.base)
                        .foregroundColor(WC.text)
                        .padding(.horizontal, 9)
                        .frame(height: Metrics.menuHeight - 1)
                        .background(open == t ? WC.hover : Color.clear)
                        .contentShape(Rectangle())
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(key: MenuFrameKey.self,
                                                       value: [t: g.frame(in: .named("root"))])
                            }
                        )
                        .onTapGesture {
                            open = (open == t) ? nil : t
                        }
                        .onHover { inside in
                            if inside && open != nil && open != t { open = t }
                        }
                }
                Spacer()
            }
            .frame(height: Metrics.menuHeight)
            .background(WC.bg)
            .overlay(alignment: .bottom) {
                Rectangle().fill(WC.border).frame(height: 1)
            }

            if let o = open, let f = frames[o] {
                MenuDropdown(items: menuItems(for: o)) {
                    open = nil
                }
                .offset(x: f.minX, y: Metrics.menuHeight)
                .zIndex(50)
            }
        }
        .frame(height: Metrics.menuHeight)
        .onPreferenceChange(MenuFrameKey.self) { frames = $0 }
        .zIndex(30)
    }

    private func menuItems(for menu: String) -> [MItem] {
        switch menu {
        case "文件":
            return [
                MItem(title: "打开压缩包…", shortcut: "⌘O") { openPanel() },
                MItem(title: "添加到压缩包…", shortcut: "⌘N", enabled: s.mode == .filesystem && !s.selection.isEmpty) { s.dialog = .add },
                MItem(isSeparator: true),
                MItem(title: "提取…", shortcut: "⌘E", enabled: s.mode == .archive) { s.dialog = .extract },
                MItem(title: "测试压缩包", shortcut: "⌘T", enabled: s.mode == .archive) { s.performTest(password: "") },
                MItem(title: "信息…", shortcut: "⌘I", enabled: s.mode == .archive || !s.selection.isEmpty) { s.dialog = .info },
                MItem(isSeparator: true),
                MItem(title: "新建文件夹", shortcut: "⇧⌘N", enabled: s.mode == .filesystem) { s.dialog = .newFolder },
                MItem(title: "重命名", shortcut: "F2", enabled: s.mode == .filesystem && s.selection.count == 1) {
                    if let e = s.selectedEntries.first { s.dialog = .rename(path: e.path, current: e.name) }
                },
                MItem(title: "删除", shortcut: "⌘⌫", enabled: s.mode == .filesystem && !s.selection.isEmpty) { s.deleteSelected() },
                MItem(isSeparator: true),
                MItem(title: "关闭压缩包", enabled: s.mode == .archive) { s.closeArchive() },
                MItem(title: "退出", shortcut: "⌘Q") { NSApp.terminate(nil) }
            ]
        case "编辑":
            return [
                MItem(title: "全选", shortcut: "⌘A") { s.selectAll() },
                MItem(title: "全不选") { s.selection = []; s.refresh() },
                MItem(isSeparator: true),
                MItem(title: "复制到文件夹…", enabled: s.mode == .filesystem && !s.selection.isEmpty) { s.copyOrMove(move: false) },
                MItem(title: "移动到文件夹…", enabled: s.mode == .filesystem && !s.selection.isEmpty) { s.copyOrMove(move: true) }
            ]
        case "查看":
            return [
                MItem(title: "工具栏", checked: s.showToolbar) { s.showToolbar.toggle() },
                MItem(title: "文件夹树", checked: s.showTree) { s.showTree.toggle() },
                MItem(isSeparator: true),
                MItem(title: "显示隐藏文件", checked: s.showHidden) {
                    s.showHidden.toggle()
                    UserDefaults.standard.set(s.showHidden, forKey: "showHidden")
                    s.refresh()
                },
                MItem(title: "刷新", shortcut: "⌘R") { s.refresh() },
                MItem(isSeparator: true),
                MItem(title: "按名称排序", checked: s.sortCol == .name) { s.toggleSort(.name) },
                MItem(title: "按大小排序", checked: s.sortCol == .size) { s.toggleSort(.size) },
                MItem(title: "按修改日期排序", checked: s.sortCol == .modified) { s.toggleSort(.modified) }
            ]
        case "工具":
            return [
                MItem(title: "选项…") { s.dialog = .options },
                MItem(isSeparator: true),
                MItem(title: "打开配置文件目录") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/7zfm"))
                },
                MItem(title: "7-Zip 引擎信息") { s.dialog = .about }
            ]
        default:
            return [
                MItem(title: "关于 7-Zip File Manager") { s.dialog = .about }
            ]
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "打开"
        panel.message = "选择要打开的压缩包"
        if panel.runModal() == .OK, let url = panel.url {
            s.openArchive(url, password: nil)
        }
    }
}

struct MenuFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct MenuDropdown: View {
    let items: [MItem]
    let dismiss: () -> Void
    @State private var hover: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                if item.isSeparator {
                    Rectangle().fill(WC.border).frame(height: 1).padding(.vertical, 3)
                } else {
                    HStack(spacing: 8) {
                        ZStack {
                            if let checked = item.checked, checked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(WC.text)
                            }
                        }.frame(width: 12)
                        Text(item.title)
                            .font(WFont.base)
                            .foregroundColor(item.enabled ? WC.text : WC.textDisabled)
                        Spacer(minLength: 24)
                        Text(item.shortcut)
                            .font(WFont.small)
                            .foregroundColor(WC.textDim)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(hover == idx ? WC.hover : Color.clear)
                    .contentShape(Rectangle())
                    .onHover { inside in hover = inside ? idx : (hover == idx ? nil : hover) }
                    .onTapGesture {
                        guard item.enabled else { return }
                        dismiss()
                        item.action()
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .frame(width: 236, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xF7F7F7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3).stroke(WC.borderDark, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 6, x: 2, y: 3)
    }
}

// MARK: - Toolbar

struct ToolbarBar: View {
    @ObservedObject var s: AppState
    @Binding var pathText: String

    var body: some View {
        HStack(spacing: 1) {
            ToolButton(symbol: "plus.square", title: "添加", color: Color(hex: 0x2E7D32),
                       enabled: s.mode == .filesystem && !s.selection.isEmpty) {
                s.dialog = .add
            }
            ToolButton(symbol: "square.and.arrow.up", title: "提取", color: Color(hex: 0x1565C0),
                       enabled: s.mode == .archive) {
                s.dialog = .extract
            }
            ToolButton(symbol: "doc.text.magnifyingglass", title: "测试", color: Color(hex: 0xEF6C00),
                       enabled: s.mode == .archive) {
                s.performTest(password: "")
            }
            ToolButton(symbol: "doc.on.doc", title: "复制", color: Color(hex: 0x455A64),
                       enabled: s.mode == .filesystem && !s.selection.isEmpty) {
                s.copyOrMove(move: false)
            }
            ToolButton(symbol: "arrow.right.square", title: "移动", color: Color(hex: 0x455A64),
                       enabled: s.mode == .filesystem && !s.selection.isEmpty) {
                s.copyOrMove(move: true)
            }
            ToolButton(symbol: "xmark.square", title: "删除", color: Color(hex: 0xC62828),
                       enabled: s.mode == .filesystem && !s.selection.isEmpty) {
                s.deleteSelected()
            }
            ToolButton(symbol: "info.circle", title: "信息", color: Color(hex: 0x1565C0),
                       enabled: s.mode == .archive || !s.selection.isEmpty) {
                s.dialog = .info
            }

            WinVDiv().frame(height: 36).padding(.horizontal, 5)

            ToolButton(symbol: "arrow.up", title: "向上",
                       color: Color(hex: 0x37474F),
                       enabled: s.mode == .archive || s.fsPath != "/") {
                s.goUp()
            }

            HStack(spacing: 6) {
                Text("地址")
                    .font(WFont.small)
                    .foregroundColor(WC.textDim)
                WinField(text: $pathText,
                         placeholder: "",
                         enabled: s.mode == .filesystem,
                         monospaced: false) {
                    if s.mode == .filesystem { s.navigate(to: (pathText as NSString).expandingTildeInPath) }
                }
                .frame(minWidth: 160)
                Button {
                    pickFolder()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundColor(WC.textDim)
                }
                .buttonStyle(.plain)
                .help("浏览文件夹")
            }
            .padding(.leading, 4)
            .padding(.trailing, 6)
        }
        .padding(.horizontal, 6)
        .frame(height: Metrics.toolbarHeight)
        .frame(maxWidth: .infinity)
        .background(WC.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(WC.border).frame(height: 1) }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "转到"
        if panel.runModal() == .OK, let url = panel.url {
            s.navigate(to: url.path)
        }
    }
}

struct ToolButton: View {
    let symbol: String
    let title: String
    var color: Color = WC.text
    var enabled: Bool = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(enabled ? color : WC.textDisabled.opacity(0.6))
                    .frame(height: 20)
                Text(title)
                    .font(WFont.tiny)
                    .foregroundColor(enabled ? WC.text : WC.textDisabled)
            }
            .frame(width: 52, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(hovering && enabled ? WC.hover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(hovering && enabled ? WC.hoverBorder : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

// MARK: - Folder tree

struct TreePanel: View {
    @ObservedObject var s: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(s.mode == .archive ? "压缩包" : "文件夹")
                    .font(WFont.small)
                    .foregroundColor(WC.textDim)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(WC.headerBottom)
            .overlay(alignment: .bottom) { Rectangle().fill(WC.border).frame(height: 1) }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(s.treeRows) { row in
                        TreeRowView(s: s, row: row)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color.white)
        }
        .background(Color.white)
    }
}

struct TreeRowView: View {
    @ObservedObject var s: AppState
    let row: TreeRow
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 3) {
            Spacer().frame(width: CGFloat(row.depth) * 14 + 3)
            Button {
                if s.mode == .archive {
                    s.toggleArchiveTree(row)
                } else {
                    s.toggleTree(row)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(WC.textDim)
                    .rotationEffect(.degrees(row.expanded ? 90 : 0))
                    .frame(width: 10, height: 10)
                    .opacity(row.hasChildren ? 1 : 0)
            }
            .buttonStyle(.plain)

            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundColor(iconColor)
                .frame(width: 14)

            Text(row.name)
                .font(WFont.base)
                .foregroundColor(WC.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 4)
        .frame(height: Metrics.treeRowHeight)
        .background(row.isCurrent ? WC.sel : (hovering ? Color(hex: 0xF2F8FD) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            s.navigate(to: row.path)
        }
    }

    private var iconName: String {
        switch row.kind {
        case .volume: return "internaldrive"
        case .folder: return row.expanded ? "folder.fill" : "folder"
        case .archive: return "archivebox.fill"
        case .archiveFolder: return "folder.fill"
        }
    }

    private var iconColor: Color {
        switch row.kind {
        case .volume: return Color(hex: 0x7C8B99)
        case .archive: return WC.archive
        default: return WC.folder
        }
    }
}

// MARK: - File list

struct FilePanel: View {
    @ObservedObject var s: AppState

    var body: some View {
        GeometryReader { geo in
            let others = Col.allCases.filter { $0 != .name }.reduce(CGFloat(0)) {
                $0 + (s.columnWidths[$1.rawValue] ?? $1.width)
            }
            let nameW = max(140, geo.size.width - others - 1)
            VStack(spacing: 0) {
                header(nameWidth: nameW)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(s.entries.enumerated()), id: \.element.id) { idx, entry in
                            FileRowView(s: s, entry: entry, index: idx, nameWidth: nameW)
                        }
                        if s.entries.isEmpty {
                            emptyView
                        }
                        Spacer(minLength: 0)
                    }
                }
                .background(Color.white)
            }
        }
        .background(Color.white)
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 22))
                .foregroundColor(Color(hex: 0xC8CDD3))
            Text(s.mode == .archive ? "此文件夹为空" : "此文件夹为空")
                .font(WFont.base)
                .foregroundColor(WC.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func header(nameWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HeaderCell(s: s, col: .name, width: nameWidth, canResize: false)
            ForEach(Col.allCases.filter { $0 != .name }) { col in
                HeaderCell(s: s, col: col,
                           width: s.columnWidths[col.rawValue] ?? col.width,
                           canResize: true)
            }
            Spacer(minLength: 0)
        }
        .frame(height: Metrics.headerHeight)
        .background(
            LinearGradient(colors: [WC.headerTop, WC.headerBottom],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) { Rectangle().fill(WC.border).frame(height: 1) }
    }
}

struct HeaderCell: View {
    @ObservedObject var s: AppState
    let col: Col
    let width: CGFloat
    let canResize: Bool
    @State private var dragStart: CGFloat?

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 3) {
                if col.trailing { Spacer(minLength: 0) }
                Text(col.title)
                    .font(WFont.small)
                    .foregroundColor(WC.text)
                    .lineLimit(1)
                if s.sortCol == col {
                    Image(systemName: s.sortAsc ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(WC.textDim)
                }
                if !col.trailing { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 7)
            .frame(width: width, height: Metrics.headerHeight)
            .contentShape(Rectangle())
            .onTapGesture { s.toggleSort(col) }

            if canResize {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStart == nil { dragStart = width }
                                let w = (dragStart ?? width) + value.translation.width
                                s.setColumnWidth(col, w)
                            }
                            .onEnded { _ in dragStart = nil }
                    )
                Rectangle()
                    .fill(WC.border)
                    .frame(width: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: canResize ? width + 1 : width, alignment: .leading)
    }
}

struct FileRowView: View {
    @ObservedObject var s: AppState
    let entry: Entry
    let index: Int
    let nameWidth: CGFloat
    @State private var hovering = false

    private var selected: Bool { s.selection.contains(entry.path) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 13))
                    .foregroundColor(iconColor)
                    .frame(width: 16)
                Text(entry.name)
                    .font(WFont.base)
                    .foregroundColor(WC.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            .padding(.trailing, 5)
            .frame(width: nameWidth, height: Metrics.rowHeight, alignment: .leading)

            cell(Fmt.size(entry.size), col: .size)
            cell(Fmt.size(entry.packed), col: .packed)
            cell(Fmt.date(entry.modified), col: .modified)
            cell(entry.displayAttrs, col: .attrs)
            cell(entry.crc, col: .crc)
            Spacer(minLength: 0)
        }
        .frame(height: Metrics.rowHeight)
        .background(background)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) {
            s.open(entry)
        }
        .onTapGesture {
            s.select(entry, modifiers: NSEvent.modifierFlags)
        }
        .gesture(TapGesture().modifiers(.command).onEnded {
            s.select(entry, modifiers: [.command])
        })
        .gesture(TapGesture().modifiers(.shift).onEnded {
            s.select(entry, modifiers: [.shift])
        })
        .contextMenu { contextMenu }
    }

    private var background: Color {
        if selected { return WC.sel }
        if hovering { return Color(hex: 0xF4FAFF) }
        return index % 2 == 1 ? WC.altRow : WC.listBg
    }

    private func cell(_ text: String, col: Col) -> some View {
        Text(text)
            .font(col == .attrs || col == .crc ? WFont.small : WFont.base)
            .foregroundColor(WC.text)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: false)
            .padding(.horizontal, col == .attrs ? 8 : 6)
            .frame(width: s.columnWidths[col.rawValue] ?? col.width,
                   height: Metrics.rowHeight,
                   alignment: col.trailing ? .trailing : .leading)
    }

    private var iconName: String {
        if entry.isDir {
            if entry.path.lowercased().hasSuffix(".app") { return "app.fill" }
            return "folder.fill"
        }
        if entry.isArchive { return "archivebox.fill" }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md", "rtf", "log", "json", "xml", "html", "css", "js", "swift", "php", "py": return "doc.text.fill"
        case "png", "jpg", "jpeg", "gif", "webp", "tiff", "heic", "bmp", "svg": return "photo.fill"
        case "mp4", "mov", "mkv", "avi", "webm": return "film.fill"
        case "mp3", "wav", "aac", "flac", "m4a": return "waveform"
        case "pdf": return "doc.richtext.fill"
        case "dmg", "iso": return "opticaldisc.fill"
        default: return "doc.fill"
        }
    }

    private var iconColor: Color {
        if entry.isDir { return WC.folder }
        if entry.isArchive { return WC.archive }
        switch iconName {
        case "doc.text.fill": return Color(hex: 0x5B87B8)
        case "photo.fill": return Color(hex: 0x4E9A6B)
        case "film.fill": return Color(hex: 0x8E6BB5)
        case "waveform": return Color(hex: 0xB5735B)
        case "doc.richtext.fill": return Color(hex: 0xC0504D)
        default: return WC.file
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("打开") { s.open(entry) }
        if s.mode == .archive {
            Button("提取…") {
                s.selection = [entry.path]
                s.dialog = .extract
            }
            Divider()
            Button("测试压缩包") { s.performTest(password: "") }
            Button("信息") {
                s.selection = [entry.path]
                s.dialog = .info
            }
        } else {
            Divider()
            Button("复制到文件夹…") {
                s.selection = [entry.path]
                s.copyOrMove(move: false)
            }
            Button("移动到文件夹…") {
                s.selection = [entry.path]
                s.copyOrMove(move: true)
            }
            Button("移到废纸篓") {
                s.selection = [entry.path]
                s.deleteSelected()
            }
            Divider()
            Button("显示简介") {
                s.selection = [entry.path]
                s.dialog = .info
            }
        }
    }
}

// MARK: - Status bar

struct StatusBarView: View {
    @ObservedObject var s: AppState

    var body: some View {
        HStack(spacing: 8) {
            Text(s.statusLeft)
            Spacer()
            Text(s.statusRight)
        }
        .font(WFont.small)
        .foregroundColor(WC.text)
        .padding(.horizontal, 8)
        .frame(height: Metrics.statusHeight)
        .background(WC.bg)
        .overlay(alignment: .top) { Rectangle().fill(WC.border).frame(height: 1) }
    }
}
