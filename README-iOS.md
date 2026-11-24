# DeepChat iOS

Android 版的 iOS 对应实现：SwiftUI 写的原生客户端，功能对齐「对话 / 写作改写 / 会话库 / 通道与 Key / 兑换码」。不依赖任何第三方库，只用 Apple 自带的框架（SwiftUI、CryptoKit、Security、URLSession）。

- 源码：`ios/Sources/DeepChatCore`（逻辑，无 UI 依赖）、`ios/Sources/DeepChatUI`（界面）
- 最低系统：iOS 16 / macOS 13（包同时声明了两个平台，方便在 Mac 上直接编译校验）
- 包管理：Swift Package（`Package.swift`），没有 `.xcodeproj`

## 一、当前状态（实话）

`swift build` 在这台机器上已通过（Core 与 UI 全部编译成功），但**这台机器只有 CommandLineTools，没有完整 Xcode，也没有 iOS SDK**，因此没有产出 `.ipa`。

出 `.ipa` 需要 iOS SDK，而 iOS SDK 只随 Xcode 分发。Xcode 本身免费（不需要 99 美元开发者账号），两条获取途径：

1. Mac App Store 搜 Xcode 安装（约 15 GB，要 Apple ID 登录，免费）
2. developer.apple.com 下载 Xcode 的 .xip（同样免费，需要登录 Apple ID）

装好之后 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`，再按下一节打包。

## 二、打包成 .ipa

### 方式 A：Xcode 图形界面（推荐，最省事）

1. Xcode → File → New → Project → iOS → App，Product Name 填 `DeepChat`，Interface 选 SwiftUI，Language 选 Swift。
2. 删掉模板生成的 `ContentView.swift`。
3. 把 `ios/Sources/DeepChatCore/*.swift` 和 `ios/Sources/DeepChatUI/*.swift` 全部拖进工程（勾选 Copy items if needed）。
4. 新建 `DeepChatApp.swift`：

```swift
import SwiftUI
import DeepChatUI

@main
struct DeepChatApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
```

5. Signing & Capabilities → Team 选你的 Apple ID（免费的 Personal Team 也行），Bundle Identifier 改成你自己的，比如 `com.你的名字.deepchat`。
6. 顶部设备选 Any iOS Device (arm64) → Product → Archive → Distribute App → **Development** 或 **Ad Hoc** 导出 `.ipa`。
   - 免费 Personal Team 只能导出 Development 描述文件，7 天有效，正好对应下面的免费安装路。

### 方式 B：命令行（有 Xcode 时）

```bash
cd ios
xcodebuild -scheme DeepChat -configuration Release -sdk iphoneos \
  -archivePath build/DeepChat.xcarchive archive \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

产出的 `.app` 在 `build/DeepChat.xcarchive/Products/Applications/`，压成 Payload 目录再 `zip` 就是未签名 `.ipa`，交给签名工具处理：

```bash
mkdir -p build/Payload && cp -R build/DeepChat.xcarchive/Products/Applications/DeepChat.app build/Payload/
cd build && zip -qr DeepChat-unsigned.ipa Payload
```

## 三、免费安装（不花一分钱）

先明确一件事：**iOS 未越狱、且不在 TrollStore 覆盖范围内的设备，签名校验屏蔽不了**。校验发生在 AMFI / CoreTrust 层，不随 App 走，改 Info.plist、改 bundle id、塞描述文件都跳不过去。能"免签"的只有下面第 1 条（吃系统漏洞）和第 2 条（越狱）；其余都是"签名 + 定期续签"。

| 方案 | 适用 | 有效期 | 需要电脑 |
| --- | --- | --- | --- |
| **TrollStore（巨魔）** | iOS 14.0b2–16.6.1、16.7 RC、17.0 | 永久 | 不需要（装机时可能要） |
| **越狱 + AppSync Unified** | checkm8 设备（A11 及更早，iPhone X 及以前） | 永久 | 需要 |
| **SideStore** | 全版本 | 7 天，设备端自动续 | 首次配对需要 |
| **AltStore** | 全版本 | 7 天，靠 AltServer 后台续 | 需要（Mac/Windows 常开） |
| **Sideloadly** | 全版本 | 7 天，手动重签 | 需要 |
| **爱思助手** | 全版本 | 7 天，手动重签 | 需要（Windows/Mac） |
| **共享企业证书** | 全版本 | 名义 1 年，实际随时掉签 | 不需要 |

按你的机器选：

### 1. TrollStore（永久，首选）

先看版本：设置 → 通用 → 关于本机 → 软件版本。

- iOS 14.0 beta 2 – 16.6.1：用 **TrollInstallerX**
- iOS 15.7.2 – 15.8.6：用 **TrollMisaka**
- iOS 17.0：用 **TrollRestore**
- iOS 17.0.1 及更高：**永远不支持**，别浪费时间

装好 TrollStore 后，把 `DeepChat.ipa`（签名与否都行）存到「文件」App，长按 → 共享 → TrollStore → 安装。装完永久有效，不会过期。

### 2. SideStore（全版本免费，配对一次后不用电脑）

1. 电脑装 AltServer（Windows/Mac）或直接按 SideStore 官网文档走。
2. 手机上装 SideStore，用免费 Apple ID 登录。
3. SideStore → 左上角 + → 选 `DeepChat.ipa` → 安装。
4. 开启 SideStore 的「后台刷新」，7 天到期它会自己重签。

注意：免费 Apple ID 同时最多装 3 个自签应用，每周最多 10 个 App ID。

### 3. AltStore / Sideloadly / 爱思助手

- **Sideloadly**：电脑装，连上 iPhone，拖入 `DeepChat.ipa`，填 Apple ID，点 Start。7 天后重复一次即可，数据保留。
- **AltStore**：电脑常开 AltServer，手机同 WiFi，AltStore 自动续签。
- **爱思助手**：工具箱 → IPA 签名 → 导入 IPA → 输入 Apple ID → 签名并安装。

### 4. 共享企业证书（不建议）

网上公开的免费企业证书（p12 + mobileprovision）可以签，装完到 设置 → 通用 → VPN 与设备管理 里信任。但从 2023 年起苹果收紧，共享证书一周掉签好几次，部分设备信任后仍然闪退、甚至被拉黑。用它做测试可以，**收费产品千万别用**——用户刚付完钱打不开，退款和差评一起到。

## 四、安装后怎么用

1. 首次打开停在「兑换码」页，页面上会显示**本机设备号**。
2. 把整串 `YC2.…` 凭证（或 20 位兑换码）粘贴进输入框 → 点「验证 / 兑换」。
   - 零售码是「未绑定设备」签发的，第一次激活就绑这台机器。
   - 换手机或重装系统后设备号会变，需要找作者按新设备号换签。
3. 进主界面后先去「设置」：
   - Base URL 填 `https://api.deepseek.com`（或任意 OpenAI 兼容地址）
   - 模型填 `deepseek-chat`
   - API Key 粘贴自己的 Key（存 Keychain，界面只显示首尾各 4 位）
   - 点「测试连通性」确认能拿到模型列表
4. 四个 tab：
   - **对话**：底部四种模式（普通 / 专家 / 深度思考 / 智能搜索），流式输出，可停止、可重新生成
   - **写作**：贴一段原文，选「收紧 / 展开 / 加细节 / 改对话 / 列结构」，只出改后的段落，可复制、可替换原文、可存成会话
   - **会话**：本地历史，左滑删除，可导出 Markdown 到「文件」App
   - **设置**：通道、Key、温度、token 上限、设备号

## 五、数据和隐私

- 会话与设置存在应用沙盒的 JSON 文件里；API Key 与设备号存在系统 Keychain。
- 请求直连你配置的接口，本应用不经过任何中转服务器。
- 卸载应用会连同本地会话一起删除，重要稿子先导出 Markdown。

## 六、已知限制

- 没有 TTS 朗读、没有角色卡/世界书（Android 版有），iOS 首版只保证「能写、能改、能存、能导出」。
- 没有后台刷新定时任务，SideStore 续签要它自己跑起来。
- 分享扩展、小组件未做。
- Swift Package 里没有 Assets.xcassets，图标需要在 Xcode 工程里自己加（放 1024×1024 的 AppIcon 即可）。