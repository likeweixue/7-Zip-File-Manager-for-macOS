import AppKit
import SwiftUI

/// 主窗口。内嵌的 NSHostingView 会按自身 fittingSize 反过来压缩窗口，
/// 所以这里同时拦截 setFrame / setContentSize，任何小于最小尺寸的请求都退回首选尺寸。
final class MainWindow: NSWindow {
    var preferredFrame: NSRect = .zero

    private func clamped(_ rect: NSRect) -> NSRect {
        let minW: CGFloat = 860, minH: CGFloat = 520
        guard rect.width < minW || rect.height < minH else { return rect }
        let base = preferredFrame == .zero ? rect : preferredFrame
        return NSRect(x: base.minX, y: base.minY,
                      width: max(base.width, minW), height: max(base.height, minH))
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(clamped(frameRect), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate: Bool) {
        super.setFrame(clamped(frameRect), display: flag, animate: animate)
    }

    override func setContentSize(_ size: NSSize) {
        let rect = clamped(NSRect(origin: frame.origin, size: size))
        super.setContentSize(rect.size)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let hosting = NSHostingView(rootView: ContentView(s: state))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        // 用普通 NSView 当容器，避免 NSHostingView 直接把窗口压成拟合尺寸
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1120, height: 740))
        container.autoresizingMask = [.width, .height]
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        let rect = NSRect(x: 0, y: 0, width: 1120, height: 740)
        let win = MainWindow(contentRect: rect,
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered,
                             defer: false)
        win.preferredFrame = windowFrame()
        window = win
        window.title = "7-Zip File Manager"
        window.contentView = container
        window.minSize = NSSize(width: 860, height: 520)
        window.contentMinSize = NSSize(width: 860, height: 520)
        window.isRestorable = false
        window.restorationClass = nil
        window.tabbingMode = .disallowed
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.94, alpha: 1)
        let target = windowFrame()
        window.setFrame(target, display: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        finishedLaunching = true
        if let url = pendingOpenURLs.first {
            pendingOpenURLs = []
            open(url)
        }
        installKeyMonitor()
    }

    private func windowFrame() -> NSRect {
        let size = NSSize(width: 1120, height: 740)
        guard let screen = NSScreen.main else { return NSRect(origin: .zero, size: size) }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.midY - size.height / 2)
        return NSRect(origin: origin, size: size)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private var pendingOpenURLs: [URL] = []
    private var finishedLaunching = false

    func application(_ application: NSApplication, open urls: [URL]) {
        guard finishedLaunching else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        open(urls.first)
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        if ArchiveFormats.isArchive(url) {
            state.openArchive(url, password: nil)
        } else {
            state.navigate(to: url.deletingLastPathComponent().path)
        }
    }

    // MARK: Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(item("关于 7-Zip File Manager", #selector(showAbout)))
        appMenu.addItem(.separator())
        let hide = appMenu.addItem(withTitle: "隐藏 7-Zip File Manager",
                                   action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "退出 7-Zip File Manager",
                                   action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appItem.submenu = appMenu

        // File
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(item("打开压缩包…", #selector(openArchivePanel), "o"))
        fileMenu.addItem(item("添加到压缩包…", #selector(addToArchive), "n"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("提取…", #selector(extractNow), "e"))
        fileMenu.addItem(item("测试压缩包", #selector(testArchive), "t"))
        fileMenu.addItem(item("信息…", #selector(showInfo), "i"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("新建文件夹", #selector(newFolder), "n", [.command, .shift]))
        fileMenu.addItem(item("重命名", #selector(renameItem), ""))
        fileMenu.addItem(item("删除", #selector(deleteItems), "\u{8}"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("关闭压缩包", #selector(closeArchive), "w"))
        fileItem.submenu = fileMenu

        // Edit
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(item("全选", #selector(selectAllItems), "a"))
        editMenu.addItem(.separator())
        editMenu.addItem(item("复制到文件夹…", #selector(copyItems)))
        editMenu.addItem(item("移动到文件夹…", #selector(moveItems)))
        editItem.submenu = editMenu

        // View
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "查看")
        viewMenu.addItem(item("刷新", #selector(refreshList), "r"))
        viewMenu.addItem(item("向上", #selector(goUp), "\u{2191}"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item("工具栏", #selector(toggleToolbar)))
        viewMenu.addItem(item("文件夹树", #selector(toggleTree)))
        viewMenu.addItem(item("显示隐藏文件", #selector(toggleHidden)))
        viewItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { mi.keyEquivalentModifierMask = mods }
        mi.target = self
        return mi
    }

    // MARK: Actions

    @objc private func showAbout() { state.dialog = .about }

    @objc private func openArchivePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "打开"
        if panel.runModal() == .OK, let url = panel.url {
            state.openArchive(url, password: nil)
        }
    }

    @objc private func addToArchive() { state.dialog = .add }
    @objc private func extractNow() { state.dialog = .extract }
    @objc private func testArchive() { state.performTest(password: "") }
    @objc private func showInfo() { state.dialog = .info }
    @objc private func newFolder() { state.dialog = .newFolder }
    @objc private func closeArchive() { state.closeArchive() }
    @objc private func selectAllItems() { state.selectAll() }
    @objc private func refreshList() { state.refresh() }
    @objc private func goUp() { state.goUp() }
    @objc private func copyItems() { state.copyOrMove(move: false) }
    @objc private func moveItems() { state.copyOrMove(move: true) }
    @objc private func deleteItems() { state.deleteSelected() }
    @objc private func toggleToolbar() { state.showToolbar.toggle() }
    @objc private func toggleTree() { state.showTree.toggle() }

    @objc private func toggleHidden() {
        state.showHidden.toggle()
        UserDefaults.standard.set(state.showHidden, forKey: "showHidden")
        state.refresh()
    }

    @objc private func renameItem() {
        if let e = state.selectedEntries.first {
            state.dialog = .rename(path: e.path, current: e.name)
        }
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let win = self.window, win == NSApp.keyWindow else { return event }
            if win.firstResponder is NSTextView { return event }
            if self.state.dialog != nil || self.state.run != nil || self.state.errorText != nil {
                return event
            }
            if event.modifierFlags.contains(.command) { return event }

            switch event.keyCode {
            case 126: // ↑
                self.state.moveSelection(by: -1)
                return nil
            case 125: // ↓
                self.state.moveSelection(by: 1)
                return nil
            case 36, 76: // return
                if let e = self.state.selectedEntries.first { self.state.open(e) }
                return nil
            case 51, 117: // delete
                self.state.deleteSelected()
                return nil
            case 53: // esc
                self.state.selection = []
                self.state.refresh()
                return nil
            default:
                return event
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
