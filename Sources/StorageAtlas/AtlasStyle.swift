import AppKit
import SwiftUI
import StorageCore

/// Shared native tokens for the floating workspace. Color marks data, never permission to remove it.
enum MapStyle {
    static let canvas = Color(hex: 0x101214)
    static let chrome = Color(hex: 0x1B1D1F)
    static let panel = Color(hex: 0x222426)
    static let field = Color(hex: 0x2B2E30)
    static let line = Color(hex: 0x35383B)
    static let text = Color(hex: 0xF4F5F5)
    static let secondary = Color(hex: 0xB5B9BD)
    static let muted = Color(hex: 0x969CA1)
    static let accent = Color(hex: 0x9DD8D1)
    static let warning = Color(hex: 0xE5C280)
    static let floatingRadius: CGFloat = 18
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion")
    }
    static func color(_ category: StorageCategory) -> Color { Color(nsColor: nativeColor(category)) }
    static func nativeColor(_ category: StorageCategory) -> NSColor {
        let hex: UInt32
        switch category {
        case .development: hex = 0x355C66
        case .applications: hex = 0x3B526C
        case .caches: hex = 0x4A5159
        case .archives: hex = 0x6B5A42
        case .media: hex = 0x3E6058
        case .models: hex = 0x47635B
        case .documents: hex = 0x66534E
        case .other: hex = 0x354045
        }
        return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                       green: CGFloat((hex >> 8) & 255) / 255,
                       blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

struct AtlasControlStyle: ButtonStyle {
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        AtlasControlBody(configuration: configuration, active: active)
    }
    private struct AtlasControlBody: View {
        let configuration: ButtonStyleConfiguration
        let active: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active || hovered ? MapStyle.text : MapStyle.secondary)
                .padding(.horizontal, 9).frame(minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active || configuration.isPressed ? MapStyle.field : hovered ? MapStyle.field.opacity(0.65) : .clear))
                .opacity(enabled ? 1 : 0.35)
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onHover { hovered = $0 }
                .animation(MapStyle.reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        }
    }
}

struct AtlasFloatingSurface: ViewModifier {
    var radius: CGFloat = MapStyle.floatingRadius
    func body(content: Content) -> some View {
        content.background(MapStyle.panel, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
    }
}

/// A prominent action for a contextual notice, distinct from quiet toolbar controls.
struct AtlasNoticeActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ActionBody(configuration: configuration)
    }
    private struct ActionBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @State private var hovered = false
        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MapStyle.canvas)
                .padding(.horizontal, 13).frame(minHeight: 34)
                .background(MapStyle.text.opacity(configuration.isPressed ? 0.76 : hovered ? 0.90 : 1),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: 12).stroke(MapStyle.accent, lineWidth: 2).padding(-3)
                    }
                }
                .opacity(enabled ? 1 : 0.4)
                .contentShape(RoundedRectangle(cornerRadius: 9))
                .onHover { hovered = $0 }
                .animation(MapStyle.reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        }
    }
}

struct AtlasMark: View {
    var body: some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 3).fill(MapStyle.accent).frame(width: 10)
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3).fill(MapStyle.text).frame(height: 9)
                RoundedRectangle(cornerRadius: 3).fill(MapStyle.secondary.opacity(0.7))
            }.frame(width: 11)
        }.frame(width: 23, height: 23).accessibilityHidden(true)
    }
}
