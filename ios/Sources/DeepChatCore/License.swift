import Foundation
import CryptoKit

/// 离线激活凭证校验。
///
/// 凭证格式：`YC2.<base64url(payloadJSON)>.<base64url(DER ECDSA-P256-SHA256 签名)>`
/// 签名覆盖 payload 段的 ASCII 字节；客户端只内置公钥，**没有任何签发能力**。
/// payload：`{"v":2,"c":"兑换码","d":"设备号或*","e":过期毫秒,"n":"随机串","o":0|1}`
public enum LicenseVerifier {

    /// 与 Android 端同一把公钥（X.509 SPKI, base64）。
    static let publicKeyBase64 =
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAECdpw"
        + "eTopF/fN1ELhU0rVy7hp7lg3EFLs8ez464OL53VWQrRd"
        + "SCF+0lBkypzHNCuk230eMoRc1o0y1h6ftjRC5g=="

    static let prefix = "YC2."
    static let claimVersion = 2

    public enum Failure: Error, Equatable {
        case notAVoucher
        case malformed
        case badSignature
        case badVersion
        case missingField
        case badExpiry
    }

    /// 纯验签：只回答“这串是不是作者签的、内容有没有被改”。
    public static func verify(_ input: String) throws -> LicenseClaims {
        let cleaned = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard cleaned.hasPrefix(prefix) else { throw Failure.notAVoucher }
        let body = String(cleaned.dropFirst(prefix.count))
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw Failure.malformed }

        let payloadSeg = String(parts[0])
        guard let sigData = base64URLDecode(String(parts[1])) else { throw Failure.malformed }
        guard let payloadData = base64URLDecode(payloadSeg) else { throw Failure.malformed }

        guard let keyData = Data(base64Encoded: publicKeyBase64),
              let pub = try? P256.Signing.PublicKey(derRepresentation: keyData) else {
            throw Failure.badSignature
        }
        guard let sig = try? P256.Signing.ECDSASignature(derRepresentation: sigData) else {
            throw Failure.badSignature
        }
        guard pub.isValidSignature(sig, for: Data(payloadSeg.utf8)) else {
            throw Failure.badSignature
        }

        guard let obj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let version = obj["v"] as? Int else { throw Failure.malformed }
        guard version == claimVersion else { throw Failure.badVersion }

        guard let code = (obj["c"] as? String), !code.isEmpty,
              let device = (obj["d"] as? String), !device.isEmpty else {
            throw Failure.missingField
        }
        let expiresNumber = (obj["e"] as? NSNumber)?.doubleValue ?? 0
        guard expiresNumber > 0 else { throw Failure.badExpiry }

        return LicenseClaims(
            code: code,
            device: device,
            expiresAt: Date(timeIntervalSince1970: expiresNumber / 1000.0),
            nonce: (obj["n"] as? String) ?? "",
            requiresOnline: (obj["o"] as? Int) == 1
        )
    }

    /// 验签 + 绑机 + 未过期，三者齐了才算激活。
    public static func evaluate(_ input: String, currentDevice: String, now: Date = Date()) -> LicenseState {
        do {
            let claims = try verify(input)
            if !claims.matches(device: currentDevice) {
                return .wrongDevice(claims.device)
            }
            if claims.expiresAt <= now {
                return .expired(claims)
            }
            return .active(claims)
        } catch Failure.notAVoucher {
            return .invalid("这不是激活凭证（应以 YC2. 开头）")
        } catch Failure.badSignature {
            return .invalid("凭证签名校验失败：内容被改动，或不是作者签发")
        } catch Failure.badVersion {
            return .invalid("凭证版本过新，请更新应用")
        } catch Failure.badExpiry {
            return .invalid("凭证缺少有效期")
        } catch {
            return .invalid("凭证格式不正确")
        }
    }

    /// 用于向作者换签：本机稳定标识。iOS 不用 IDFV 之外的东西，键值存 Keychain。
    public static func makeDeviceId() -> String {
        UUID().uuidString.lowercased()
    }

    // MARK: - 首激活设备登记

    /// 服务端（Cloudflare Pages Functions）只回答一件事：这枚码是不是第一次用在这台机器上。
    /// 唯一联网点，集中在这里；离线可用不受影响——只在激活/重新粘码时调用。
    public static let bindEndpoint = URL(string: "https://deepchat-writer.pages.dev/bind")!

    public enum BindOutcome: Equatable {
        /// 首次绑定，放行。
        case first
        /// 同一台机器再次绑定，放行。
        case known(count: Int)
        /// 409 DEVICE_MISMATCH：这枚码已经绑在别的机器上，必须拦。
        case mismatch(bound: String)
        /// 400：码或设备号本身不合法（与「没网」分开提示，否则用户会一直重试）。
        case rejected(String)
        /// 网络失败或服务端异常，不保存凭证。
        case offline(String)
    }

    /// POST /bind：`{"code":"…","deviceId":"…"}`，8 秒超时。
    public static func bind(code: String, deviceId: String) async -> BindOutcome {
        var request = URLRequest(url: bindEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: String] = ["code": code, "deviceId": deviceId]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            return .offline("请求构造失败")
        }
        request.httpBody = payload

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .offline("响应异常") }
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            switch http.statusCode {
            case 200, 201:
                guard (obj["ok"] as? Bool) == true else { return .offline("服务端未确认") }
                if (obj["first"] as? Bool) == true { return .first }
                return .known(count: (obj["count"] as? NSNumber)?.intValue ?? 0)
            case 409:
                guard (obj["error"] as? String) == "DEVICE_MISMATCH" else {
                    return .offline("服务端拒绝登记（409）")
                }
                let bound = (obj["bound"] as? String) ?? ""
                return .mismatch(bound: bound.isEmpty ? "未知设备" : bound)
            case 400:
                return .rejected("兑换码无效，请核对后重试，或联系作者")
            default:
                return .offline("服务端返回 \(http.statusCode)")
            }
        } catch {
            return .offline(error.localizedDescription)
        }
    }

    // MARK: - helpers

    static func base64URLDecode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        let rem = t.count % 4
        if rem > 0 { t += String(repeating: "=", count: 4 - rem) }
        return Data(base64Encoded: t)
    }
}