import SwiftUI
import DeepChatCore

public struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var keyInput = ""
    @State private var testResult = ""
    @State private var testing = false
    @State private var showingTerms = false
    @AppStorage(Theme.fontScaleKey) private var fontScaleStored: Double = 1.0
    @AppStorage(Appearance.storageKey) private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("reasoning_collapse") private var autoCollapse = true

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
                            .font(.system(size: Theme.size(12.5)))
                            .foregroundStyle(testResult.contains("正常") ? Theme.ok : Theme.danger)
                    }
                }

                section("API Key") {
                    Text("当前：\(model.apiKeyMasked)")
                        .font(.system(size: Theme.size(13)))
                        .foregroundStyle(Theme.dim)
                    SecureField("粘贴新的 Key", text: $keyInput)
                        .font(.system(size: Theme.size(14)))
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
                        .font(.system(size: Theme.size(11.5)))
                        .foregroundStyle(Theme.faint)
                }

                section("生成") {
                    HStack {
                        Text("温度").font(.system(size: Theme.size(13))).foregroundStyle(Theme.dim)
                        Slider(value: $model.settings.temperature, in: 0...1.5, step: 0.1)
                            .tint(Theme.accent)
                        Text(String(format: "%.1f", model.settings.temperature))
                            .font(.system(size: Theme.size(12)))
                            .foregroundStyle(Theme.faint)
                            .frame(width: 32)
                    }
                    HStack {
                        Text("上限 tokens").font(.system(size: Theme.size(13))).foregroundStyle(Theme.dim)
                        Spacer()
                        Text("\(model.settings.maxTokens)")
                            .font(.system(size: Theme.size(12)))
                            .foregroundStyle(Theme.faint)
                    }
                    Stepper("", value: $model.settings.maxTokens, in: 256...8192, step: 256)
                        .labelsHidden()
                }

                section("显示") {
                    Text("字体大小")
                        .font(.system(size: Theme.size(11.5)))
                        .foregroundStyle(Theme.faint)
                    HStack(spacing: 6) {
                        ForEach(Array(Theme.fontScales.enumerated()), id: \.offset) { index, scale in
                            chip(Theme.fontScaleLabels[index], active: abs(fontScaleStored - Double(scale)) < 0.001) {
                                fontScaleStored = Double(scale)
                                Theme.setFontScale(scale)
                                model.bumpUI()
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    Text("外观")
                        .font(.system(size: Theme.size(11.5)))
                        .foregroundStyle(Theme.faint)
                    HStack(spacing: 6) {
                        ForEach(Appearance.allCases) { item in
                            chip(item.label, active: appearanceRaw == item.rawValue) {
                                appearanceRaw = item.rawValue
                                model.bumpUI()
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    Toggle(isOn: $autoCollapse) {
                        Text("思考内容自动折叠")
                            .font(.system(size: Theme.size(13)))
                            .foregroundStyle(Theme.dim)
                    }
                    .tint(Theme.accent)
                    Text("开启时思考过程只显示一行「已深度思考」，点开才看全文。")
                        .font(.system(size: Theme.size(11.5)))
                        .foregroundStyle(Theme.faint)
                }

                section("语音输入") {
                    Text("按住输入框旁的麦克风键说话，音频只在内存里转成文字：不落文件、不上传本应用的服务器。识别由系统（Apple）提供，设备不支持离线识别时会走系统网络服务。")
                        .font(.system(size: Theme.size(11.5)))
                        .foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section("授权") {
                    Text("本机设备号（换签凭证时发给作者）")
                        .font(.system(size: Theme.size(11.5)))
                        .foregroundStyle(Theme.faint)
                    Text(model.deviceId)
                        .font(.system(size: Theme.size(12), design: .monospaced))
                        .foregroundStyle(Theme.dim)
                        .textSelection(.enabled)
                    Text(model.licenseActive ? "已激活" : "未激活")
                        .font(.system(size: Theme.size(13), weight: .semibold))
                        .foregroundStyle(model.licenseActive ? Theme.ok : Theme.danger)
                }

                section("使用须知与免责声明") {
                    Text("项目性质、担保与责任限制、合规使用三段。首次启动时已确认同意。")
                        .font(.system(size: Theme.size(11.5)))
                        .foregroundStyle(Theme.faint)
                    GhostButton("查看全文") { showingTerms = true }
                }

                section("关于") {
                    Text("DeepChat iOS · 1.3.0")
                        .font(.system(size: Theme.size(13)))
                        .foregroundStyle(Theme.dim)
                    Text("侧载安装，不上架 App Store。对话与历史只在本机，请求直连你配置的接口。")
                        .font(.system(size: Theme.size(11.5)))
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
                .font(.system(size: Theme.size(12), weight: .semibold))
                .foregroundStyle(Theme.faint)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.size(12.5), weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(active ? Theme.accent : Theme.surface2)
                .foregroundStyle(active ? Theme.accentInk : Theme.dim)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: Theme.size(11.5))).foregroundStyle(Theme.faint)
            TextField("", text: text)
                .font(.system(size: Theme.size(14)))
                .foregroundStyle(Theme.ink)
                .padding(10)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onSubmit { model.saveSettings() }
        }
    }
}