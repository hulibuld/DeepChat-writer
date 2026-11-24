import SwiftUI
import DeepChatCore

public struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var keyInput = ""
    @State private var testResult = ""
    @State private var testing = false
    @State private var showingTerms = false

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                section("通道") {
                    field("名称", text: $model.settings.provider.name)
                    field("Base URL", text: $model.settings.provider.baseURL)
                    field("模型", text: $model.settings.provider.model)

                    HStack(spacing: 8) {
                        GhostButton(testing ? "测试中…" : "测试连通性") {
                            testing = true
                            testResult = ""
                            Task {
                                let r = await model.testConnection()
                                await MainActor.run {
                                    testResult = r
                                    testing = false
                                }
                            }
                        }
                    }
                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.system(size: 12.5))
                            .foregroundStyle(testResult.contains("正常") ? Theme.ok : Theme.danger)
                    }
                }

                section("API Key") {
                    Text("当前：\(model.apiKeyMasked)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                    SecureField("粘贴新的 Key", text: $keyInput)
                        .font(.system(size: 14))
                        .padding(11)
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    HStack(spacing: 8) {
                        GhostButton("保存") {
                            model.setAPIKey(keyInput)
                            keyInput = ""
                        }
                        GhostButton("清除") {
                            model.setAPIKey("")
                        }
                    }
                    Text("Key 存在系统 Keychain，界面只显示首尾各 4 位。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faint)
                }

                section("生成") {
                    HStack {
                        Text("温度").font(.system(size: 13)).foregroundStyle(Theme.dim)
                        Slider(value: $model.settings.temperature, in: 0...1.5, step: 0.1)
                            .tint(Theme.accent)
                        Text(String(format: "%.1f", model.settings.temperature))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faint)
                            .frame(width: 32)
                    }
                    HStack {
                        Text("上限 tokens").font(.system(size: 13)).foregroundStyle(Theme.dim)
                        Spacer()
                        Text("\(model.settings.maxTokens)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faint)
                    }
                    Stepper("", value: $model.settings.maxTokens, in: 256...8192, step: 256)
                        .labelsHidden()
                }

                section("授权") {
                    Text("本机设备号（换签凭证时发给作者）")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faint)
                    Text(model.deviceId)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                        .textSelection(.enabled)
                    Text(model.licenseActive ? "已激活" : "未激活")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(model.licenseActive ? Theme.ok : Theme.danger)
                }

                section("使用须知与免责声明") {
                    Text("项目性质、担保与责任限制、合规使用三段。首次启动时已确认同意。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faint)
                    GhostButton("查看全文") { showingTerms = true }
                }

                section("关于") {
                    Text("DeepChat iOS · 1.2.0")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                    Text("侧载安装，不上架 App Store。对话与历史只在本机，请求直连你配置的接口。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faint)
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .onChange(of: model.settings.temperature) { _ in model.saveSettings() }
        .onChange(of: model.settings.maxTokens) { _ in model.saveSettings() }
        .sheet(isPresented: $showingTerms) { TermsView() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.faint)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.faint)
            TextField("", text: text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .padding(10)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onSubmit { model.saveSettings() }
        }
    }
}