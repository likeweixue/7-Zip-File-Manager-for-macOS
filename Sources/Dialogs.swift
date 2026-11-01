import SwiftUI
import AppKit

// MARK: - Dialog chrome

struct DialogFrame<Content: View, Buttons: View>: View {
    let title: String
    let width: CGFloat
    let onClose: () -> Void
    @ViewBuilder var content: Content
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(spacing: 0) {
            // Win32 title bar
            HStack(spacing: 6) {
                Text(title)
                    .font(WFont.title)
                    .foregroundColor(.white)
                Spacer()
                Button(action: onClose) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: 0xE81123).opacity(0.0))
                            .frame(width: 18, height: 16)
                        Text("✕")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                LinearGradient(colors: [WC.titleTop, WC.titleBottom],
                               startPoint: .top, endPoint: .bottom)
            )

            content
                .padding(14)

            WinEtch()

            HStack(spacing: 8) {
                Spacer()
                buttons
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(WC.bg)
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .background(WC.bg)
        .overlay(Rectangle().stroke(WC.borderDark, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
    }
}

struct FormRow<Content: View>: View {
    let label: String
    var labelWidth: CGFloat = 84
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(WFont.base)
                .foregroundColor(WC.text)
                .frame(width: labelWidth, alignment: .trailing)
            content
        }
        .frame(minHeight: 24)
    }
}

/// A combo box that pops a native menu (Win32 combo look)
struct WinCombo: View {
    let options: [String]
    @Binding var selection: String
    var enabled: Bool = true

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button(opt) { selection = opt }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection)
                    .font(WFont.base)
                    .foregroundColor(enabled ? WC.text : WC.textDisabled)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(WC.textDim)
            }
            .padding(.horizontal, 5)
            .frame(height: 21)
            .background(Color.white)
            .overlay(Rectangle().stroke(WC.sunk, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(!enabled)
    }
}

// MARK: - Add archive

struct AddDialogView: View {
    @ObservedObject var s: AppState
    @State private var name: String = "archive.7z"
    @State private var format: String = "7z"
    @State private var level: String = "正常"
    @State private var updateMode: String = UpdateMode.addReplace.title
    @State private var password: String = ""
    @State private var showPassword = false
    @State private var encryptNames = false
    @State private var volume: String = ""

    private let formats = ["7z", "zip", "tar", "gz", "xz", "bz2"]
    private let levels = ["仅存储", "最快", "快速", "正常", "最大", "极限"]

    init(state: AppState) {
        _s = ObservedObject(wrappedValue: state)
        let first = state.selectedEntries.first
        let base = first?.name ?? "archive"
        let suggested = (base as NSString).deletingPathExtension
        _name = State(initialValue: suggested + ".7z")
    }

    var body: some View {
        DialogFrame(title: "添加到压缩包", width: 470, onClose: close) {
            VStack(alignment: .leading, spacing: 8) {
                FormRow(label: "压缩包:") {
                    WinField(text: $name, placeholder: "压缩包文件名")
                        .frame(width: 300)
                }
                FormRow(label: "格式:") {
                    WinCombo(options: formats, selection: $format)
                        .frame(width: 120)
                        .onChange(of: format) { _, newValue in
                            let ext = (name as NSString).pathExtension
                            if !ext.isEmpty {
                                name = (name as NSString).deletingPathExtension + "." + newValue
                            } else {
                                name += "." + newValue
                            }
                        }
                    Spacer()
                }
                FormRow(label: "压缩等级:") {
                    WinCombo(options: levels, selection: $level)
                        .frame(width: 120)
                    Spacer()
                }
                FormRow(label: "更新模式:") {
                    WinCombo(options: UpdateMode.allCases.map { $0.title }, selection: $updateMode)
                        .frame(width: 180)
                    Spacer()
                }
                FormRow(label: "分卷大小:") {
                    WinField(text: $volume, placeholder: "（留空表示不分卷）")
                        .frame(width: 110)
                    Text("MB").font(WFont.base).foregroundColor(WC.textDim)
                    Spacer()
                }

                WinGroup(title: "加密") {
                    VStack(alignment: .leading, spacing: 6) {
                        FormRow(label: "输入密码:", labelWidth: 84) {
                            Group {
                                if showPassword {
                                    WinField(text: $password, placeholder: "")
                                } else {
                                    SecureField("", text: $password)
                                        .textFieldStyle(.plain)
                                        .font(WFont.base)
                                        .padding(.horizontal, 4)
                                        .frame(height: 21)
                                        .background(Color.white)
                                        .overlay(Rectangle().stroke(WC.sunk, lineWidth: 1))
                                }
                            }
                            .frame(width: 200)
                            Spacer()
                        }
                        HStack(spacing: 16) {
                            Spacer().frame(width: 84)
                            WinCheckbox(on: $showPassword, title: "显示密码")
                            WinCheckbox(on: $encryptNames, title: "加密文件名", enabled: format == "7z")
                        }
                    }
                }

                Text("共 \(s.selection.count) 个对象将被压缩")
                    .font(WFont.small)
                    .foregroundColor(WC.textDim)
            }
        } buttons: {
            WinButton(title: "确定", isDefault: true, enabled: !name.isEmpty) { commit() }
                .keyboardShortcut(.defaultAction)
            WinButton(title: "取消") { close() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func close() { s.dialog = nil }

    private func commit() {
        let levelValue: Int
        switch level {
        case "仅存储": levelValue = 0
        case "最快": levelValue = 1
        case "快速": levelValue = 3
        case "正常": levelValue = 5
        case "最大": levelValue = 7
        default: levelValue = 9
        }
        let mode: UpdateMode
        switch updateMode {
        case UpdateMode.addOnly.title: mode = .addOnly
        case UpdateMode.sync.title: mode = .sync
        default: mode = .addReplace
        }
        let vol = Int(volume)
        s.dialog = nil
        s.performAdd(archivePath: name, type: format, level: levelValue,
                     password: password, encryptNames: encryptNames,
                     updateMode: mode, volumeMB: vol)
    }
}

// MARK: - Extract

struct ExtractDialogView: View {
    @ObservedObject var s: AppState
    @State private var dest: String = ""
    @State private var overwrite: String = OverwriteMode.overwrite.title
    @State private var password: String = ""
    @State private var showPassword = false
    @State private var keepStructure = true

    init(state: AppState) {
        _s = ObservedObject(wrappedValue: state)
        let base = state.archiveURL?.deletingLastPathComponent().path ?? NSHomeDirectory()
        let name = state.archiveURL?.deletingPathExtension().lastPathComponent ?? "解压文件"
        _dest = State(initialValue: (base as NSString).appendingPathComponent(name))
    }

    var body: some View {
        DialogFrame(title: "提取", width: 500, onClose: close) {
            VStack(alignment: .leading, spacing: 10) {
                FormRow(label: "提取到:") {
                    WinField(text: $dest, placeholder: "目标文件夹")
                        .frame(width: 300)
                    WinButton(title: "…", width: 26) { browse() }
                }

                WinGroup(title: "选项") {
                    VStack(alignment: .leading, spacing: 8) {
                        FormRow(label: "覆盖模式:", labelWidth: 84) {
                            WinCombo(options: OverwriteMode.allCases.map { $0.title }, selection: $overwrite)
                                .frame(width: 160)
                            Spacer()
                        }
                        FormRow(label: "密码:", labelWidth: 84) {
                            Group {
                                if showPassword {
                                    WinField(text: $password, placeholder: "（无密码可留空）")
                                } else {
                                    SecureField("", text: $password)
                                        .textFieldStyle(.plain)
                                        .font(WFont.base)
                                        .padding(.horizontal, 4)
                                        .frame(height: 21)
                                        .background(Color.white)
                                        .overlay(Rectangle().stroke(WC.sunk, lineWidth: 1))
                                }
                            }
                            .frame(width: 180)
                            WinCheckbox(on: $showPassword, title: "显示密码")
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            Spacer().frame(width: 84)
                            WinCheckbox(on: $keepStructure, title: "保留完整路径")
                        }
                    }
                }

                Text(s.selection.isEmpty
                     ? "将提取压缩包中的全部内容。"
                     : "将提取选中的 \(s.selection.count) 个对象。")
                    .font(WFont.small)
                    .foregroundColor(WC.textDim)
            }
        } buttons: {
            WinButton(title: "确定", isDefault: true, enabled: !dest.isEmpty) { commit() }
                .keyboardShortcut(.defaultAction)
            WinButton(title: "取消") { close() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.directoryURL = URL(fileURLWithPath: dest)
        if panel.runModal() == .OK, let url = panel.url { dest = url.path }
    }

    private func close() { s.dialog = nil }

    private func commit() {
        let mode: OverwriteMode
        switch overwrite {
        case OverwriteMode.skip.title: mode = .skip
        case OverwriteMode.rename.title: mode = .rename
        default: mode = .overwrite
        }
        s.dialog = nil
        s.performExtract(dest: (dest as NSString).expandingTildeInPath,
                         overwrite: mode, password: password,
                         keepStructure: keepStructure)
    }
}

// MARK: - Info

struct InfoDialogView: View {
    @ObservedObject var s: AppState

    var body: some View {
        let rows = s.entryInfo()
        DialogFrame(title: s.mode == .archive && s.selection.isEmpty ? "压缩包信息" : "信息",
                    width: 520, onClose: { s.dialog = nil }) {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { idx, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text(item.0)
                                    .font(WFont.base)
                                    .foregroundColor(WC.textDim)
                                    .frame(width: 96, alignment: .trailing)
                                Text(item.1)
                                    .font(WFont.base)
                                    .foregroundColor(WC.text)
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 3)
                            .background(idx % 2 == 1 ? Color(hex: 0xF7F7F7) : Color.clear)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        } buttons: {
            WinButton(title: "确定", isDefault: true) { s.dialog = nil }
                .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Password prompt

struct PasswordDialogView: View {
    @ObservedObject var s: AppState
    let archivePath: String
    let thenExtract: Bool
    @State private var password: String = ""
    @State private var show = false

    var body: some View {
        DialogFrame(title: "输入密码", width: 420, onClose: { s.dialog = nil }) {
            VStack(alignment: .leading, spacing: 10) {
                Text((archivePath as NSString).lastPathComponent)
                    .font(WFont.base)
                    .foregroundColor(WC.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("此压缩包已加密，请输入密码。")
                    .font(WFont.small)
                    .foregroundColor(WC.textDim)
                FormRow(label: "密码:") {
                    Group {
                        if show {
                            WinField(text: $password, placeholder: "")
                        } else {
                            SecureField("", text: $password)
                                .textFieldStyle(.plain)
                                .font(WFont.base)
                                .padding(.horizontal, 4)
                                .frame(height: 21)
                                .background(Color.white)
                                .overlay(Rectangle().stroke(WC.sunk, lineWidth: 1))
                        }
                    }
                    .frame(width: 200)
                    WinCheckbox(on: $show, title: "显示密码")
                    Spacer()
                }
            }
        } buttons: {
            WinButton(title: "确定", isDefault: true) {
                let pwd = password
                s.dialog = nil
                if thenExtract {
                    s.performExtract(dest: s.lastExtractDir, overwrite: .overwrite,
                                     password: pwd, keepStructure: true)
                } else {
                    s.openArchive(URL(fileURLWithPath: archivePath), password: pwd)
                }
            }
            .keyboardShortcut(.defaultAction)
            WinButton(title: "取消") { s.dialog = nil }
                .keyboardShortcut(.cancelAction)
        }
    }
}

// MARK: - Small prompt dialogs

struct TextPromptDialog: View {
    @ObservedObject var s: AppState
    let title: String
    let label: String
    var initial: String = ""
    let onOK: (String) -> Void
    @State private var text: String = ""

    var body: some View {
        DialogFrame(title: title, width: 400, onClose: { s.dialog = nil }) {
            FormRow(label: label) {
                WinField(text: $text, placeholder: "")
                    .frame(width: 240)
            }
        } buttons: {
            WinButton(title: "确定", isDefault: true, enabled: !text.isEmpty) {
                let v = text
                s.dialog = nil
                onOK(v)
            }
            .keyboardShortcut(.defaultAction)
            WinButton(title: "取消") { s.dialog = nil }
                .keyboardShortcut(.cancelAction)
        }
        .onAppear { if text.isEmpty { text = initial } }
    }
}

// MARK: - Options

struct OptionsDialogView: View {
    @ObservedObject var s: AppState
    @State private var showHidden = false
    @State private var showToolbar = true
    @State private var showTree = true

    var body: some View {
        DialogFrame(title: "选项", width: 420, onClose: { s.dialog = nil }) {
            VStack(alignment: .leading, spacing: 10) {
                WinGroup(title: "界面") {
                    VStack(alignment: .leading, spacing: 7) {
                        WinCheckbox(on: $showToolbar, title: "显示工具栏")
                        WinCheckbox(on: $showTree, title: "显示文件夹树")
                        WinCheckbox(on: $showHidden, title: "显示隐藏文件")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                WinGroup(title: "引擎") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("7zz: " + (Engine.shared.binary?.path ?? "未找到"))
                            .font(WFont.mono)
                            .foregroundColor(WC.textDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(Engine.shared.versionText)
                            .font(WFont.mono)
                            .foregroundColor(WC.textDim)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } buttons: {
            WinButton(title: "确定", isDefault: true) {
                s.showHidden = showHidden
                s.showToolbar = showToolbar
                s.showTree = showTree
                UserDefaults.standard.set(showHidden, forKey: "showHidden")
                s.dialog = nil
                s.refresh()
            }
            .keyboardShortcut(.defaultAction)
            WinButton(title: "取消") { s.dialog = nil }
                .keyboardShortcut(.cancelAction)
        }
        .onAppear {
            showHidden = s.showHidden
            showToolbar = s.showToolbar
            showTree = s.showTree
        }
    }
}

// MARK: - About

struct AboutDialogView: View {
    @ObservedObject var s: AppState

    var body: some View {
        DialogFrame(title: "关于 7-Zip File Manager", width: 440, onClose: { s.dialog = nil }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [Color(hex: 0x4A90D9), Color(hex: 0x1F5C91)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 48, height: 48)
                        Text("7z")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("7-Zip File Manager for macOS")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(WC.text)
                        Text("版本 \(Self.appVersion)  ·  引擎 7-Zip \(Self.engineVersion)")
                            .font(WFont.small)
                            .foregroundColor(WC.textDim)
                    }
                }
                WinEtch()
                Text("基于 Igor Pavlov 的 7-Zip 命令行引擎（LGPL 2.1+）构建的图形界面。\n压缩 / 解压 / 测试 / 加密 / 分卷，界面参照 Windows 版 7-Zip File Manager。")
                    .font(WFont.small)
                    .foregroundColor(WC.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("界面：WorkBuddy × likeweixue  ·  本项目 MIT，内置 7zz 为其原许可证")
                    .font(WFont.small)
                    .foregroundColor(WC.textDim)
                Text(Engine.shared.versionText)
                    .font(WFont.tiny)
                    .foregroundColor(WC.textDim)
                    .lineLimit(2)
            }
        } buttons: {
            WinButton(title: "第三方许可证") {
                if let url = Bundle.main.url(forResource: "7zip-License", withExtension: "txt") {
                    NSWorkspace.shared.open(url)
                }
            }
            WinButton(title: "确定", isDefault: true) { s.dialog = nil }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// 应用版本，取自 Info.plist（构建脚本根据 tag 注入）
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    /// 内置 7zz 的版本，从 `7zz` 启动横幅里解析出来（形如 "7-Zip (z) 26.05 (arm64) : ..."）
    static var engineVersion: String {
        let text = Engine.shared.versionText
        if let r = text.range(of: #"\d+\.\d+"#, options: .regularExpression) {
            return String(text[r])
        }
        return "26.05"
    }
}

// MARK: - Progress

struct ProgressDialogView: View {
    @ObservedObject var s: AppState
    let run: RunState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(run.title)
                    .font(WFont.title)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(LinearGradient(colors: [WC.titleTop, WC.titleBottom],
                                       startPoint: .top, endPoint: .bottom))

            VStack(alignment: .leading, spacing: 10) {
                Text(run.detail)
                    .font(WFont.small)
                    .foregroundColor(WC.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: 16, alignment: .leading)

                ProgressBar(value: run.progress)

                HStack {
                    Text(run.progress.map { "\(Int($0 * 100))%" } ?? "处理中…")
                        .font(WFont.small)
                        .foregroundColor(WC.textDim)
                    Spacer()
                    WinButton(title: "取消", width: 70) {
                        run.handle.cancel()
                        s.run = nil
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background(WC.bg)
        .overlay(Rectangle().stroke(WC.borderDark, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
    }
}

struct ProgressBar: View {
    let value: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white)
                if let v = value {
                    Rectangle()
                        .fill(WC.green)
                        .frame(width: max(0, min(1, v)) * (geo.size.width - 2))
                        .padding(.leading, 1)
                } else {
                    Rectangle()
                        .fill(WC.green.opacity(0.5))
                        .frame(width: geo.size.width * 0.35)
                        .padding(.leading, 1)
                }
            }
            .overlay(Rectangle().stroke(WC.sunk, lineWidth: 1))
            .frame(height: 16)
        }
        .frame(height: 16)
    }
}

// MARK: - Error

struct ErrorDialogView: View {
    @ObservedObject var s: AppState
    let message: String

    var body: some View {
        DialogFrame(title: "7-Zip File Manager", width: 460, onClose: { s.errorText = nil }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: 0xE0A800))
                Text(message)
                    .font(WFont.base)
                    .foregroundColor(WC.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        } buttons: {
            WinButton(title: "确定", isDefault: true) { s.errorText = nil }
                .keyboardShortcut(.defaultAction)
        }
    }
}
