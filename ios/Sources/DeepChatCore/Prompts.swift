import Foundation

/// 四种走法共用一套对话结构，只换指令与温度；不引入任何外部服务。
public enum Prompts {

    public static func system(for mode: WritingMode) -> String {
        let base = """
        你是一个中文写作助手。回答用中文，句子短，不堆形容词，不用排比句撑篇幅。
        用户给你一段文字时，先判断他要的是「改」还是「续」还是「问」；不确定就直接问一句。
        不改写用户没有要求改的部分。给出修改时，说明改了哪里、为什么改，不要一次给五个版本。
        """

        switch mode {
        case .normal:
            return base
        case .expert:
            return base + """

            现在进入专家模式：假设读者是有经验的编辑。可以直接指出结构问题、逻辑跳跃、视角混乱，
            给出可执行的修改动作（删哪句、把哪段提前、哪个词换掉）。不要为了客气而模糊判断。
            """
        case .deep:
            return base + """

            现在进入深度思考模式：回答前先在心里列出至少三条不同的处理路径，比较它们的代价，
            再选一条写出来。最终只输出结论与理由，不要输出思考过程本身。
            """
        case .search:
            return base + """

            现在进入检索模式：如果问题涉及具体事实（时间、数字、地名、人名、条文），
            先说明这一点需要核对，再给出你确定的部分；不确定就标明不确定，不要编造来源。
            """
        }
    }

    /// 写作动作：一键改写。传入原文与动作，返回给模型的用户消息。
    public enum Action: String, CaseIterable, Sendable {
        case tighten, expand, describe, dialogue, outline

        public var label: String {
            switch self {
            case .tighten: return "收紧"
            case .expand: return "展开"
            case .describe: return "加细节"
            case .dialogue: return "改对话"
            case .outline: return "列结构"
            }
        }

        public var instruction: String {
            switch self {
            case .tighten:
                return "把下面这段收紧：删掉解释性的句子和多余的修饰，保留原意与信息量。只输出改后的段落。"
            case .expand:
                return "把下面这段展开一倍：补具体动作、物件、光线，不要加形容词堆叠，不要加评论。只输出改后的段落。"
            case .describe:
                return "给下面这段补可感知的细节（声音、温度、手上的动作），不超过原段的两倍长。只输出改后的段落。"
            case .dialogue:
                return "把下面这段改成对话：去掉“他说”“她想”这类转述，靠台词本身区分人物。只输出改后的段落。"
            case .outline:
                return "给下面这段列出结构：用三到六条短句写清它现在讲了什么、缺什么。不要改写原文。"
            }
        }
    }
}