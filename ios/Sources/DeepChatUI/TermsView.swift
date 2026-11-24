import SwiftUI

/// 使用须知与免责声明。文案照抄仓库根目录 `DISCLAIMER.md` 的第一、五、六节，不做改写。
/// 两种用法：
/// - 首次启动拦截：`TermsView(onAgree:onDecline:)`，同意才往下走，不同意退出；
/// - 设置页常驻入口：`TermsView()`，当 sheet 打开只读。
public struct TermsView: View {

    /// 同意状态存在 UserDefaults，键写死在这里。
    public static let agreedKey = "terms_v1"

    @Environment(\.dismiss) private var dismiss

    private let onAgree: (() -> Void)?
    private let onDecline: (() -> Void)?

    public init(onAgree: (() -> Void)? = nil, onDecline: (() -> Void)? = nil) {
        self.onAgree = onAgree
        self.onDecline = onDecline
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("使用须知与免责声明")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("下载、安装、激活或使用本项目，即视为你已阅读、理解并同意下列全部内容。不同意其中任何一条，请不要安装或使用。")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.dim)
                        if onAgree == nil {
                            // 设置页以 sheet 打开时给一个明确的关闭入口。
                            GhostButton("关闭") { dismiss() }
                        }
                    }

                    ForEach(TermsView.sections) { section in
                        Surface {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                ForEach(section.items, id: \.self) { item in
                                    Text(LocalizedStringKey(item))
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Theme.dim)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 30)
                .padding(.bottom, 24)
            }

            if let onAgree, let onDecline {
                VStack(spacing: 10) {
                    PrimaryButton("同意并继续") { onAgree() }
                    GhostButton("不同意，退出") { onDecline() }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Theme.surface)
            }
        }
        .background(Theme.bg)
    }

    // MARK: - 原文

    private struct Section: Identifiable {
        let id: String
        let title: String
        let items: [String]
    }

    private static let sections: [Section] = [
        Section(
            id: "nature",
            title: "一、项目性质",
            items: [
                "1. 本项目是由个人独立开发的第三方客户端，目的是把「与模型对话」和「改稿」这两件事的界面做得顺手一些。",
                "2. 本项目**不是**任何公司、机构或组织的官方产品。本项目与 DeepSeek（杭州深度求索人工智能基础技术研究有限公司）、OpenAI、Anthropic、Google 及其各自关联公司之间，**不存在隶属、授权、代理、合作、赞助或背书关系**。",
                "3. 本项目未获得上述任何主体的事先审阅或认可。上述主体对本项目不知情、未参与、不承担任何责任。",
                "4. 文中出现的产品名称、商标、服务标记、界面术语，归各自权利人所有。本项目提及它们仅用于指称对象与说明兼容性，不主张任何权利，也不表示任何关联。"
            ]
        ),
        Section(
            id: "warranty",
            title: "五、担保与责任限制",
            items: [
                "1. 本软件按「现状」与「现有」提供，不附带任何明示或默示的担保，包括但不限于适销性担保、特定用途适用性担保、不侵权担保、无病毒担保与准确性担保。",
                "2. 不保证软件没有缺陷，不保证运行不中断，不保证与任何第三方接口的兼容性长期有效，不保证模型输出内容的真实性、准确性与合法性。模型输出由你自行判断与承担。",
                "3. 在适用法律允许的最大范围内，因使用或无法使用本软件而产生的任何直接、间接、附带、特殊、惩罚性或后果性损失（包括但不限于数据丢失、设备损坏、利润损失、商誉损失、第三方索赔、行政处罚），作者不承担赔偿责任。",
                "4. 本条不排除或限制依法律规定不得排除或限制的责任。若你所在法域不允许上述排除，则以该法域法律为准，其余条款继续有效。"
            ]
        ),
        Section(
            id: "compliance",
            title: "六、合规使用",
            items: [
                "1. 你应自行确认：使用本软件、接入你所选定的模型服务、处理你所输入的内容，均符合你所在地的法律法规、你所在学校或用人单位的规定、以及第三方服务的使用条款。",
                "2. 不得将本软件用于：生成或传播违法信息；侵犯他人知识产权、隐私权、名誉权；绕过他人的技术保护措施；实施欺诈、冒充、伪造证明文件；其他依法禁止的用途。",
                "3. 因你的使用行为引起的一切法律后果与第三方主张，由你自行承担；因此给作者造成损失的，你应予赔偿。"
            ]
        )
    ]
}