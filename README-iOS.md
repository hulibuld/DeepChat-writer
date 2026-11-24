# DeepChat iOS

Android 版的 iOS 对应实现：SwiftUI 写的原生客户端，不依赖任何第三方库，只用 Apple 自带框架（SwiftUI、CryptoKit、Security、AVFoundation）。

- 源码：`ios/Sources/DeepChatCore`（逻辑，无 UI 依赖）、`ios/Sources/DeepChatUI`（界面）、`ios/App`（App 入口、Info.plist、图标）
- 工程文件：`ios/DeepChat.xcodeproj`（由 `ios/project.yml` 经 xcodegen 生成，也可直接双击打开）
- 最低系统：iOS 16
- 已经出过包：Xcode 26.3 + iOS 26.2 SDK，见下方「一、直接装」

## 一、直接装（不编译）

两个包内容完全相同，区别只在签名方式：

| 包 | 给谁用 | 怎么装 |
|---|---|---|
| `DeepChat-1.0.0-trollstore.ipa` | iOS 14.0b2 – 16.6.1、16.7 RC、17.0 | 已带 `platform-application`，TrollStore 直接吃 |
| `DeepChat-1.0.0-unsigned.ipa` | iOS 17.0.1 及以上 | 用 SideStore / AltStore / Sideloadly / 爱思自助签名 |

下载地址在官网页面（`#ios` 区块），校验值：

```
trollstore  1,108,394 字节  6c356c32e5643a3f3f1e573daee4f7e48677f6686437b2121c8824689895cbe3
unsigned    1,077,222 字节  8cd4b0c46d56cd85baa44821c70aea50324160003c6085f6651557a7944f2007
```

## 二、自己出包

只需要两样：Xcode（免费，提供 iOS SDK）与 xcodegen。

```bash
brew install xcodegen
cd ios
./build-ipa.sh
```

`build-ipa.sh` 依次做：`xcodegen generate` 生成工程 → `xcodebuild` 出 arm64 Release 包（不签名）→ 压成通用未签名 `.ipa` → 复制一份用 ad-hoc 签名加 `platform-application` 出 TrollStore 包。产物在 `ios/dist/`，末尾会打印文件名、字节数与 SHA-256。

Xcode 版本：26.3 是最后一个支持 macOS 15 Sequoia 的版本，装 26.4 及以上需要 macOS 26。SDK 版本不影响产物兼容性，`IPHONEOS_DEPLOYMENT_TARGET` 固定 16.0。

### 用 Xcode 图形界面出签名包

想直接把 App 装到自己手机上、不经过第三方工具，用你自己的免费 Apple ID 签：

1. 双击 `ios/DeepChat.xcodeproj`。
2. 选中 `DeepChat` target → Signing & Capabilities → Team 选你的 Apple ID（Personal Team 即可），Bundle Identifier 改成 `com.你的名字.deepchat`。
3. 顶部设备选你的 iPhone → Run（免费签名 7 天有效，到期重新 Run 一次，数据保留）。
4. 要出 `.ipa` 文件：设备选 Any iOS Device (arm64) → Product → Archive → Distribute App → Development。

## 三、免费安装（不花一分钱）

先说结论：**iOS 未越狱、且不在 TrollStore 覆盖范围内的设备，签名校验屏蔽不了**。校验在 AMFI / CoreTrust 层，不随 App 走，改 Info.plist、改 bundle id、塞描述文件都跳不过去。能"免签"的只有下面第 1、2 条（吃系统漏洞 / 越狱），其余都是「签名 + 定期续签」。

| 方案 | 适用 | 有效期 | 需要电脑 |
|---|---|---|---|
| **TrollStore（巨魔）** | iOS 14.0b2–16.6.1、16.7 RC、17.0 | 永久 | 装机时可能要 |
| **越狱 + AppSync Unified** | checkm8 设备（A11 及更早，iPhone X 及以前） | 永久 | 需要 |
| **SideStore** | 全版本 | 7 天，设备端自动续 | 首次配对 |
| **AltStore** | 全版本 | 7 天，AltServer 后台续 | 需要（常开） |
| **Sideloadly** | 全版本 | 7 天，手动重签 | 需要 |
| **爱思助手** | 全版本 | 7 天，手动重签 | 需要 |
| **共享企业证书** | 全版本 | 名义 1 年，实际随时掉签 | 不需要 |

### 1. TrollStore（永久，首选）

先看版本：设置 → 通用 → 关于本机 → 软件版本。

- iOS 14.0 beta 2 – 16.6.1：**TrollInstallerX**
- iOS 15.7.2 – 15.8.6：**TrollMisaka**
- iOS 17.0：**TrollRestore**
- iOS 17.0.1 及更高：不支持，别浪费时间

装好 TrollStore 后，把 `.ipa` 存进「文件」App，长按 → 共享 → TrollStore → 安装。装完永久有效。

### 2. SideStore（全版本，配对一次后不用电脑）

1. 电脑装 AltServer（Windows / Mac），或照 SideStore 官网的配对流程走一遍。
2. 手机上装 SideStore，用免费 Apple ID 登录。
3. SideStore → 左上角 + → 选 `.ipa` → 安装。
4. 打开 SideStore 的「后台刷新」，7 天到期自动续签。

免费 Apple ID 同时最多 3 个自签应用，每周最多 10 个 App ID。

### 3. Sideloadly / AltStore / 爱思助手

- **Sideloadly**：电脑装，连上 iPhone，拖入 `.ipa`，填 Apple ID，点 Start。7 天后重复一次，数据保留。
- **AltStore**：电脑常开 AltServer，手机同 WiFi，自动续签。
- **爱思助手**：工具箱 → IPA 签名 → 导入 IPA → 输入 Apple ID → 签名并安装。

### 4. 共享企业证书（不建议）

网上公开的免费企业证书（p12 + mobileprovision）能签，装完到 设置 → 通用 → VPN 与设备管理 信任。但 2023 年起苹果收紧，共享证书一周掉签好几次，部分设备信任后仍闪退甚至被拉黑。测试可以，**收费产品别用**——用户刚付完钱打不开，退款和差评一起到。

## 四、装完怎么用

1. 首次打开停在「兑换码」页，页面上显示**本机设备号**。
2. 把整串 `YC2.…` 凭证粘贴进去 → 点「验证 / 兑换」。零售码按「未绑定设备」签发，第一次激活绑这台机器；换手机或重装后设备号会变，需要按新设备号换签。
3. 进主界面先去「设置」：Base URL 填 `https://api.deepseek.com`（或任意 OpenAI 兼容地址）、模型填 `deepseek-chat`、API Key 粘贴自己的 Key（进 Keychain，界面只显示首尾各四位）、点「测试连通性」。
4. 五个 tab：

| tab | 里面有什么 |
|---|---|
| **对话** | 四种模式（普通 / 专家 / 深度思考 / 智能搜索），流式输出，可停止、可重新生成；每条回复旁有朗读按钮 |
| **写作** | 贴一段原文，选「收紧 / 展开 / 加细节 / 改对话 / 列结构」，只出改后段落，可复制、可替换原文、可存成会话 |
| **会话** | 本地历史，左滑删除，可导出 Markdown |
| **资料** | 角色卡、记忆、用量、导出、通道五个入口 |
| **设置** | 通道、Key、温度、token 上限、设备号、授权状态 |

**资料 → 角色卡**：姓名、人设、口癖、不会说的话、开场白分行填，勾选哪些小节参与拼装，选中一张卡后它的内容会接在系统提示词后面一起发出去。

**资料 → 记忆**：人物、地名、设定单独记，每条有开关，启用中的条目自动排进上下文。

**资料 → 用量**：按天累计请求次数与估算 token（中文 1 字 ≈ 1 token，ASCII 4 字符 ≈ 1 token，每条消息再 +4 结构开销）。

**资料 → 通道**：多个接口地址与模型并存，选中一个作为当前，Key 存 Keychain。

## 五、数据和隐私

- 会话、设置、角色卡、记忆、用量、通道都存在应用沙盒的 JSON 文件里（`Application Support/DeepChat/`）。
- API Key 与设备号存在系统 Keychain，界面只显示首尾各四位。
- 请求直连你配置的接口，本应用不经过任何中转服务器，也不上报任何统计。
- 卸载会连同本地数据一起删除，重要稿子先导出 Markdown。

## 六、已知限制（实话）

- **酒馆模式、世界书没有**：Android 版有，iOS 首版没做。
- **图片与文件附件没有**；JSON 会话语义导入（Android 的一键导入）没有，只有导出。
- 朗读用的是系统 `AVSpeechSynthesizer`，音色随系统，不能选第三方语音。
- 后台刷新没做，SideStore 续签要靠它自己跑起来。
- 小组件、分享扩展未做。
- 只有 App 图标，没有启动图（`UILaunchScreen` 用系统默认）。