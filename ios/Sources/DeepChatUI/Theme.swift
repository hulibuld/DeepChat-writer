import SwiftUI

/// 深色一套：底、面、字、次要字、强调色。数量按用途定死，不新增第六种。
public enum Theme {
    public static let bg = Color(red: 0.043, green: 0.059, blue: 0.086)      // #0B0F16
    public static let surface = Color(red: 0.086, green: 0.110, blue: 0.149) // #161C26
    public static let surface2 = Color(red: 0.110, green: 0.141, blue: 0.188)
    public static let line = Color.white.opacity(0.07)
    public static let ink = Color(red: 0.914, green: 0.929, blue: 0.953)
    public static let dim = Color(red: 0.600, green: 0.639, blue: 0.702)
    public static let faint = Color(red: 0.427, green: 0.463, blue: 0.522)
    public static let accent = Color(red: 0.353, green: 0.608, blue: 0.988)  // #5A9BFC
    public static let accentInk = Color(red: 0.043, green: 0.059, blue: 0.086)
    public static let danger = Color(red: 0.937, green: 0.451, blue: 0.451)
    public static let ok = Color(red: 0.243, green: 0.812, blue: 0.557)

    public static let radius: CGFloat = 14
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
                .font(.system(size: 15, weight: .semibold))
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
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.surface2)
                .foregroundStyle(Theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 99, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}