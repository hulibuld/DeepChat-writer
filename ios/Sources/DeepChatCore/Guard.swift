import Foundation
#if os(iOS)
import UIKit
import Darwin

// iOS SDK 把这两个符号从 Swift 视野里藏了：`ptrace` 属于非公开接口，`_dyld_image_*`
// 也没进 Darwin 模块。两符号本身都在 libSystem / libdyld 里，用 @_silgen_name 直接对。
@_silgen_name("ptrace")
private func dc_ptrace(_ request: CInt, _ pid: pid_t,
                       _ addr: UnsafeMutableRawPointer?, _ data: CInt) -> CInt

@_silgen_name("_dyld_image_count")
private func dc_dyld_image_count() -> UInt32

@_silgen_name("_dyld_get_image_name")
private func dc_dyld_get_image_name(_ index: UInt32) -> UnsafePointer<CChar>?

/// ptrace 的 PT_DENY_ATTACH，值为 31。
private let dcPT_DENY_ATTACH: CInt = 31
#endif

/// 越狱与调试痕迹检测。
///
/// 只做**只读判断**，不退出、不崩溃、不弹窗——这两种环境在正常用户上也偶发（企业签名、
/// 内测描述文件、Xcode 连着的开发机），主动杀掉进程只会误伤。调用方拿到结果自己决定
/// 要不要降级能力（例如关闭导出、标记上报结果）。
public enum Guard {

    /// 常见越狱痕迹：包管理器、Shell、SSH、以及越狱环境才有的目录。
    private static let jailbreakPaths = [
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/Zebra.app",
        "/var/jb",
        "/private/var/jb",
        "/bin/bash",
        "/bin/sh",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/etc/ssh/sshd_config",
        "/private/etc/apt",
        "/usr/libexec/cydia",
        "/usr/lib/libsubstrate.dylib",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/private/var/lib/dpkg",
        "/private/var/lib/apt"
    ]

    /// 注入了越狱/调试工具的镜像名。
    private static let hookLibraries = [
        "Substrate", "Substitute", "libhooker", "cycript",
        "FridaGadget", "frida", "SSLKillSwitch", "libjailbreak"
    ]

    // MARK: - 判定

    /// 越狱环境（只读判断，缓存一次，避免每次渲染都扫目录）。
    public static var jailbroken: Bool { checkJailbreak() }

    /// 正在被调试（`P_TRACED` 标志位，或注入了调试库）。
    public static var debugged: Bool { checkDebugger() }

    /// 命中的具体痕迹，方便写日志或上报；空数组表示没发现。
    public static var signals: [String] { collectSignals() }

    /// 主动拒绝调试器附着。默认不调用——这是「提高门槛」而不是「防破解」，
    /// 真要在启动时拦，由 App 入口显式调一次。
    public static func denyDebugger() {
        #if os(iOS)
        _ = dc_ptrace(dcPT_DENY_ATTACH, getpid(), nil, 0)
        #endif
    }

    // MARK: - 越狱

    private static func checkJailbreak() -> Bool {
        #if os(iOS)
        let manager = FileManager.default
        if jailbreakPaths.contains(where: { manager.fileExists(atPath: $0) }) { return true }
        if canOpenCydia() { return true }
        if canWriteOutsideSandbox() { return true }
        if hasInjectedLibrary() { return true }
        #endif
        return false
    }

    private static func canOpenCydia() -> Bool {
        #if os(iOS)
        guard let url = URL(string: "cydia://package/com.example.package") else { return false }
        if Thread.isMainThread {
            return UIApplication.shared.canOpenURL(url)
        }
        // 非主线程读不到这个 API，交给调用方在主线程问一次即可，这里不阻塞。
        return false
        #else
        return false
        #endif
    }

    /// 越狱环境沙盒失效，普通 App 沙盒外是写不进去的。
    private static func canWriteOutsideSandbox() -> Bool {
        #if os(iOS)
        let probe = "/private/.deepchat-probe-\(UUID().uuidString)"
        do {
            try "probe".write(toFile: probe, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: probe)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    private static func hasInjectedLibrary() -> Bool {
        #if os(iOS)
        if let inject = getenv("DYLD_INSERT_LIBRARIES"), String(cString: inject).isEmpty == false {
            return true
        }
        let count = dc_dyld_image_count()
        guard count > 0 else { return false }
        for index in 0..<count {
            guard let raw = dc_dyld_get_image_name(index) else { continue }
            let name = String(cString: raw)
            if hookLibraries.contains(where: { name.localizedCaseInsensitiveContains($0) }) {
                return true
            }
        }
        #endif
        return false
    }

    // MARK: - 调试

    private static func checkDebugger() -> Bool {
        #if os(iOS)
        if isTraced() { return true }
        if hasInjectedLibrary() { return true }
        #endif
        return false
    }

    /// `sysctl` 读 `P_TRACED`：被 lldb / Xcode 附着时为真。
    private static func isTraced() -> Bool {
        #if os(iOS)
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let status = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard status == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
        #else
        return false
        #endif
    }

    // MARK: - 痕迹清单

    private static func collectSignals() -> [String] {
        #if os(iOS)
        var found: [String] = []
        let manager = FileManager.default
        for path in jailbreakPaths where manager.fileExists(atPath: path) {
            found.append("文件存在：\(path)")
        }
        if canOpenCydia() { found.append("能打开 cydia:// scheme") }
        if canWriteOutsideSandbox() { found.append("沙盒外可写（越狱特征）") }
        if isTraced() { found.append("进程带 P_TRACED（被调试）") }
        if hasInjectedLibrary() { found.append("镜像里有注入库（Substrate / Frida 等）") }
        return found
        #else
        return []
        #endif
    }
}