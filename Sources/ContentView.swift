import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var s: AppState
    @State private var openMenu: String?
    @State private var pathText: String = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Color.clear.frame(height: Metrics.menuHeight)

                if s.showToolbar {
                    ToolbarBar(s: s, pathText: $pathText)
                }

                HStack(spacing: 0) {
                    if s.showTree {
                        TreePanel(s: s)
                            .frame(width: s.treeWidth)
                        SplitterHandle(width: $s.treeWidth)
                    }
                    FilePanel(s: s)
                }

                StatusBarView(s: s)
            }

            MenuStrip(s: s, open: $openMenu)

            overlayLayer
        }
        .coordinateSpace(name: "root")
        .background(WC.bg)
        .background(WindowTitleSetter(title: "7-Zip File Manager"))
        .onAppear { pathText = s.displayPath }
        .onChange(of: s.displayPath) { _, newValue in pathText = newValue }
    }

    @ViewBuilder
    private var overlayLayer: some View {
        ZStack {
            if let dialog = s.dialog {
                Color.black.opacity(0.12)
                    .onTapGesture { }
                dialogView(dialog)
            } else if let run = s.run {
                Color.black.opacity(0.10)
                ProgressDialogView(s: s, run: run)
            } else if let error = s.errorText {
                Color.black.opacity(0.12)
                ErrorDialogView(s: s, message: error)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(80)
    }

    @ViewBuilder
    private func dialogView(_ dialog: Dialog) -> some View {
        switch dialog {
        case .add:
            AddDialogView(state: s)
        case .extract:
            ExtractDialogView(state: s)
        case .info:
            InfoDialogView(s: s)
        case .about:
            AboutDialogView(s: s)
        case .password(let archive, let thenExtract):
            PasswordDialogView(s: s, archivePath: archive, thenExtract: thenExtract)
        case .newFolder:
            TextPromptDialog(s: s, title: "新建文件夹", label: "名称:", initial: "新建文件夹") { name in
                s.createFolder(named: name)
            }
        case .rename(_, let current):
            TextPromptDialog(s: s, title: "重命名", label: "新名称:", initial: current) { name in
                s.renameSelected(to: name)
            }
        case .options:
            OptionsDialogView(s: s)
        }
    }
}

struct SplitterHandle: View {
    @Binding var width: CGFloat
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? WC.hoverBorder : WC.border)
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        width = min(460, max(140, width + value.translation.width / 3))
                    }
            )
    }
}

struct WindowTitleSetter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { v.window?.title = title }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.title = title }
    }
}
