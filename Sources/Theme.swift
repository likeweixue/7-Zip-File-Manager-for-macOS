import SwiftUI
import AppKit

// MARK: - Colors

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: 1.0)
    }
}

/// Classic Windows / 7-Zip File Manager palette
enum WC {
    static let bg           = Color(hex: 0xF0F0F0)
    static let bgDeep       = Color(hex: 0xE8E8E8)
    static let border       = Color(hex: 0xDCDCDC)
    static let borderDark   = Color(hex: 0xB8B8B8)
    static let sunk         = Color(hex: 0x8C8C8C)
    static let listBg       = Color(hex: 0xFFFFFF)
    static let altRow       = Color(hex: 0xF9FAFB)
    static let text         = Color(hex: 0x1A1A1A)
    static let textDim      = Color(hex: 0x6D6D6D)
    static let textDisabled = Color(hex: 0xAEAEAE)
    static let sel          = Color(hex: 0xCCE8FF)
    static let selInactive  = Color(hex: 0xEDEDED)
    static let selBorder    = Color(hex: 0x99D1FF)
    static let accent       = Color(hex: 0x0078D7)
    static let hover        = Color(hex: 0xE5F1FB)
    static let hoverBorder  = Color(hex: 0xCCE4F7)
    static let press        = Color(hex: 0xCCE4F7)
    static let headerTop    = Color(hex: 0xFBFBFB)
    static let headerBottom = Color(hex: 0xEDEDED)
    static let titleTop     = Color(hex: 0x3E7CB1)
    static let titleBottom  = Color(hex: 0x1F5C91)
    static let folder       = Color(hex: 0xF0B429)
    static let file         = Color(hex: 0x9EADBB)
    static let archive      = Color(hex: 0xC08A46)
    static let green        = Color(hex: 0x06B025)
}

enum Metrics {
    static let menuHeight: CGFloat = 24
    static let toolbarHeight: CGFloat = 50
    static let statusHeight: CGFloat = 22
    static let rowHeight: CGFloat = 21
    static let headerHeight: CGFloat = 22
    static let treeRowHeight: CGFloat = 20
    static let treeWidth: CGFloat = 208
}

enum WFont {
    static let base    = Font.system(size: 12)
    static let small   = Font.system(size: 11)
    static let tiny    = Font.system(size: 10)
    static let bold    = Font.system(size: 12).weight(.semibold)
    static let title   = Font.system(size: 12).weight(.semibold)
    static let mono    = Font.system(size: 11, design: .monospaced)
}

// MARK: - Formatting

enum Fmt {
    static let sizeFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        return f
    }()

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let stampParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func size(_ v: Int64?) -> String {
        guard let v else { return "" }
        return sizeFormatter.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    static func date(_ d: Date?) -> String {
        guard let d else { return "" }
        return dateFormatter.string(from: d)
    }

    static func human(_ v: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(v)
        var idx = 0
        while value >= 1024 && idx < units.count - 1 { value /= 1024; idx += 1 }
        if idx == 0 { return "\(v) B" }
        return String(format: "%.1f %@", value, units[idx])
    }
}

// MARK: - Reusable Win32-ish widgets

/// Flat bordered push button, like the Win32 dialog buttons.
struct WinButton: View {
    let title: String
    var width: CGFloat? = 76
    var isDefault: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WFont.base)
                .foregroundColor(enabled ? WC.text : WC.textDisabled)
                .frame(minWidth: width ?? 0, minHeight: 24)
                .padding(.horizontal, width == nil ? 12 : 0)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(pressed ? Color(hex: 0xDDEBF7) : (hovering && enabled ? WC.hover : Color(hex: 0xF5F5F5)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(enabled ? (hovering ? WC.hoverBorder : WC.borderDark) : WC.border,
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded { _ in pressed = false })
    }
}

/// Sunken single-line text field (Win32 EDIT control)
struct WinField: View {
    @Binding var text: String
    var placeholder: String = ""
    var enabled: Bool = true
    var monospaced: Bool = false
    var onCommit: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(monospaced ? WFont.mono : WFont.base)
            .foregroundColor(enabled ? WC.text : WC.textDim)
            .focused($focused)
            .padding(.horizontal, 4)
            .frame(height: 21)
            .background(Color.white)
            .overlay(
                Rectangle().stroke(focused ? WC.accent : WC.sunk, lineWidth: 1)
            )
            .disabled(!enabled)
            .onSubmit { onCommit?() }
    }
}

/// Win32 sunken group box
struct WinGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .stroke(WC.borderDark, lineWidth: 1)
                .padding(.top, 7)
            content.padding(.top, 18).padding(.horizontal, 12).padding(.bottom, 10)
            Text(title)
                .font(WFont.small)
                .foregroundColor(WC.textDim)
                .padding(.horizontal, 4)
                .background(WC.bg)
                .offset(x: 10, y: 0)
        }
    }
}

/// Checkbox drawn with a 13x13 box, Win32 style
struct WinCheckbox: View {
    @Binding var on: Bool
    let title: String
    var enabled: Bool = true

    var body: some View {
        Button {
            guard enabled else { return }
            on.toggle()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Rectangle().fill(Color.white)
                    Rectangle().stroke(WC.sunk, lineWidth: 1)
                    if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(WC.text)
                    }
                }
                .frame(width: 13, height: 13)
                Text(title).font(WFont.base).foregroundColor(enabled ? WC.text : WC.textDisabled)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Thin etched horizontal separator
struct WinEtch: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(WC.border).frame(height: 1)
            Rectangle().fill(Color.white).frame(height: 1)
        }
    }
}

/// Vertical divider used in toolbars
struct WinVDiv: View {
    var body: some View {
        Rectangle().fill(WC.borderDark).frame(width: 1).padding(.vertical, 6)
    }
}
