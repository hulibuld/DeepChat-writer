import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 两套色板 + 四档字号。颜色用动态色，跟随视图环境的 `colorScheme` 自动切换；
/// `Theme.size(_:)` 只缩放文字，不动图标、圆角与间距。
public enum Theme {

    // MARK: - 字号

    /// 四档：小 / 标准 / 大 / 特大。
    public static let fontScales: [CGFloat] = [0.85, 1.0, 1.15, 1.3]
    public static let fontScaleLabels = ["小", "标准", "大", "特大"]
    public static let fontScaleKey = "font_scale"

    /// 当前缩放系数。默认从 UserDefaults 读，切换时由 `setFontScale(_:)` 写入。
    public static var fontScale: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: fontScaleKey)
        return stored > 0 ? CGFloat(stored) : 1.0
    }()

    /// 只用于文字：基准磅值 × 当前档位，取到 0.5 的整数倍。
    public static func size(_ base: CGFloat) -> CGFloat {
        ((base * fontScale) * 2).rounded() / 2
    }

    public static func setFontScale(_ scale: CGFloat) {
        fontScale = scale
        UserDefaults.standard.set(Double(scale), forKey: fontScaleKey)
    }

    // MARK: - 色板

    // 深色沿用 1.2.0 的配色，一个字没改；浅色是新加的一套。
    // 对比度（WCAG 2.1）：深色 ink/bg 16.33、dim/bg 7.53、faint/bg 4.19；
    // 浅色 ink/bg 16.45、dim/bg 7.25、faint/bg 4.41。
    public static let bg = adaptive(light: 0xF6F7F9, dark: 0x0B0F16)
    public static let surface = adaptive(light: 0xFFFFFF, dark: 0x161C26)
    public static let surface2 = adaptive(light: 0xE9EDF3, dark: 0x1C2430)
    public static let ink = adaptive(light: 0x15191F, dark: 0xE9EDF3)
    public static let dim = adaptive(light: 0x4A5361, dark: 0x99A3B3)
    public static let faint = adaptive(light: 0x6B7482, dark: 0x6D7685)
    public static let accent = adaptive(light: 0x1D63D2, dark: 0x5A9BFC)
    public static let accentInk = adaptive(light: 0xFFFFFF, dark: 0x0B0F16)
    public static let danger = adaptive(light: 0xB3261E, dark: 0xEF7373)
    public static let ok = adaptive(light: 0x17663F, dark: 0x3ECF8E)

    #if canImport(UIKit)
    public static let line = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.07)
            : UIColor(white: 0, alpha: 0.08)
    })
    #else
    public static let line = Color.white.opacity(0.07)
    #endif

    public static let radius: CGFloat = 14
}

// MARK: - 动态色

#if canImport(UIKit)
private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

private func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
    })
}
#else
/// 宿主侧（`swift build` 到 macOS）没有 UIKit，固定给深色值，只为编译通过。
private func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(
        red: Double((dark >> 16) & 0xFF) / 255,
        green: Double((dark >> 8) & 0xFF) / 255,
        blue: Double(dark & 0xFF) / 255
    )
}
#endif

// MARK: - 外观

/// 深色 / 浅色 / 跟随系统。
public enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    /// 交给 `preferredColorScheme`：`nil` 就是跟随系统。
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    public static let storageKey = "appearance"
}

public struct Surface<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

public struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.size(15), weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.accent)
                .foregroundStyle(Theme.accentInk)
                .clipShape(RoundedRectangle(cornerRadius: 99, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

public struct GhostButton: View {
    let title: String
    let action: () -> Void
    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.size(14), weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.surface2)
                .foregroundStyle(Theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 99, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}