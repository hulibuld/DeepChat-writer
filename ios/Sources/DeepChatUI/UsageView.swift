import SwiftUI
import DeepChatCore

/// 用量页：最近 7 天的请求次数与 token 估算，加合计。
/// 记录由调用方写入（`UsageStore.shared.record(...)`），这里只读共享实例。
public struct UsageView: View {

    @StateObject private var store: UsageStore

    public init(store: UsageStore? = nil) {
        _store = StateObject(wrappedValue: store ?? UsageStore.shared)
    }

    private var summary: UsageSummary { store.summary(days: 7) }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    totalsCard
                    todayCard
                    dayList
                    footer
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
        .onAppear { store.reload() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("用量")
                .font(.system(size: Theme.size(20), weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text("本机估算")
                .font(.system(size: Theme.size(11.5)))
                .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近 7 天")
                .font(.system(size: Theme.size(12), weight: .semibold))
                .foregroundStyle(Theme.faint)

            Text("\(summary.requests) 次请求")
                .font(.system(size: Theme.size(26), weight: .bold))
                .foregroundStyle(Theme.ink)

            Text("共 \(tokenText(summary.totalTokens)) tokens · 输入 \(tokenText(summary.promptTokens)) · 输出 \(tokenText(summary.completionTokens))")
                .font(.system(size: Theme.size(12.5)))
                .foregroundStyle(Theme.dim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var todayCard: some View {
        HStack(spacing: 0) {
            stat("今天", "\(summary.today?.requests ?? 0) 次")
            divider
            stat("今天 tokens", tokenText(summary.today?.totalTokens ?? 0))
            divider
            stat("累计记录", "\(store.records.count) 条")
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("按天")
                .font(.system(size: Theme.size(12), weight: .semibold))
                .foregroundStyle(Theme.faint)
                .padding(.bottom, 10)

            if summary.isEmpty {
                Text("最近 7 天还没有调用记录。")
                    .font(.system(size: Theme.size(13)))
                    .foregroundStyle(Theme.faint)
                    .padding(.vertical, 8)
            }

            ForEach(Array(summary.days.enumerated()), id: \.element.id) { index, day in
                dayRow(day)
                if index != summary.days.count - 1 {
                    Rectangle()
                        .fill(Theme.line)
                        .frame(height: 1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func dayRow(_ day: UsageDay) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(dayLabel(day))
                    .font(.system(size: Theme.size(13.5), weight: day.requests > 0 ? .medium : .regular))
                    .foregroundStyle(day.requests > 0 ? Theme.ink : Theme.faint)
                    .frame(width: 58, alignment: .leading)
                Text("\(day.requests) 次")
                    .font(.system(size: Theme.size(12)))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 52, alignment: .leading)
                Spacer(minLength: 6)
                Text("\(tokenText(day.totalTokens)) tokens")
                    .font(.system(size: Theme.size(12), design: .monospaced))
                    .foregroundStyle(day.totalTokens > 0 ? Theme.ink : Theme.faint)
            }
            bar(fraction: fraction(day))
        }
        .padding(.vertical, 9)
    }

    private func bar(fraction value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surface2)
                Capsule()
                    .fill(Theme.accent.opacity(0.85))
                    .frame(width: max(value <= 0 ? 0 : 3, geo.size.width * value))
            }
        }
        .frame(height: 5)
        .padding(.leading, 0)
    }

    private func fraction(_ day: UsageDay) -> Double {
        let peak = summary.peakTokens
        guard peak > 0 else { return 0 }
        return min(1, Double(day.totalTokens) / Double(peak))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("token 是估算值：中文 1 字算 1，英文 4 字符算 1，用来观察趋势，不用于对账。")
                .font(.system(size: Theme.size(11.5)))
                .foregroundStyle(Theme.faint)
            GhostButton("清空用量记录") {
                store.clear()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: Theme.size(10.5)))
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.system(size: Theme.size(14), weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(width: 1, height: 26)
            .padding(.horizontal, 8)
    }

    private func dayLabel(_ day: UsageDay) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day.date) { return "今天" }
        if calendar.isDateInYesterday(day.date) { return "昨天" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: day.date)
    }

    private func tokenText(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return "\(value)"
    }
}