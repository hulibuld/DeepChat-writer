import SwiftUI
import DeepChatCore

public struct LicenseView: View {
    @ObservedObject var model: AppModel
    @State private var code = ""
    @State private var showingReset = false

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                VStack(alignment: .leading, spacing: 6) {
                    Text("兑换码")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("1 元一枚，一码一设备。粘贴后本机即激活。")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.dim)
                }
                .padding(.top, 28)

                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("未激活")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.danger)
                            Spacer()
                        }
                        TextField("XXXX-XXXX-XXXX-XXXX-XXXX 或粘贴 YC2 激活凭证", text: $code, axis: .vertical)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2...6)
                            .padding(11)
                            .background(Theme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif

                        PrimaryButton(model.activating ? "联网登记中…" : "验证 / 兑换") {
                            Task { await model.activate(code) }
                        }

                        if !model.licenseMessage.isEmpty {
                            Text(model.licenseMessage)
                                .font(.system(size: 12.5))
                                .foregroundStyle(model.licenseActive ? Theme.ok : Theme.dim)
                        }
                    }
                }

                Surface {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本机设备号")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.faint)
                        Text(model.deviceId)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.dim)
                            .textSelection(.enabled)
                        Text("换手机或重装系统后这个号会变，需要找作者换签。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.faint)
                    }
                }

                Surface {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("为什么收费")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                        Text("收费旨在培养互联网用户的付费意识，倡导摒弃无偿获取的观念。")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.dim)
                        Text("1 元一枚，一码一设备。所有收入捐给贫困儿童教育事业，6 个月后公开收入与捐赠记录。")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.dim)
                    }
                }

                if model.licenseActive {
                    GhostButton("重置为未激活") { showingReset = true }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Theme.bg)
        .alert("重置为未激活", isPresented: $showingReset) {
            Button("取消", role: .cancel) {}
            Button("确认", role: .destructive) { model.deactivate() }
        } message: {
            Text("将清除本机授权凭据，重置后需要重新兑换。")
        }
    }
}