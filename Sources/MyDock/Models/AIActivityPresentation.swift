import Foundation

/// Shared by the tile, chart axes and summary. Raw counters remain available to AX/help.
enum AIActivityFormatting {
    static func tokens(_ value: Int64, fractionDigits: Int = 1) -> String {
        let magnitude = max(0, value)
        for (threshold, suffix) in [(1_000_000_000.0, "B"), (1_000_000.0, "M"), (1_000.0, "K")] {
            if Double(magnitude) >= threshold {
                let number = Double(magnitude) / threshold
                return number.formatted(.number.precision(.fractionLength(0...max(0, min(1, fractionDigits))))) + suffix
            }
        }
        return magnitude.formatted()
    }
}

/// Inert data for the visual item browser; never written to a profile or provider.
enum AIActivityPreviewData {
    static func item() -> DockItem {
        var item = DockItem.widget("AI Activity")
        let today = Calendar.current.startOfDay(for: .now)
        let points = [12, 9, 24, 18, 32, 16, 28].enumerated().map { index, value in
            AIActivityDailyPoint(date: Calendar.current.date(byAdding: .day, value: index - 6, to: today)!, sessions: 2, toolCalls: 12,
                                 totalTokens: Int64(value) * 1_000, cachedInputTokens: 0, inputTokens: 0, outputTokens: 0, requests: 0, reportedCostUSD: nil)
        }
        item.widgetConfiguration?.aiActivityProvider = .codex
        item.widgetConfiguration?.aiActivityRange = .sevenDays
        item.widgetConfiguration?.aiActivitySnapshot = AIActivitySnapshot(provider: .codex, range: .sevenDays, fetchedAt: .now,
            sourceDescription: "Sample local activity", available: true, estimated: false, partial: false, points: points,
            totals: AIActivityDailyPoint(date: today, sessions: 14, toolCalls: 84, totalTokens: 139_000,
                cachedInputTokens: 0, inputTokens: 0, outputTokens: 0, requests: 0, reportedCostUSD: nil))
        return item
    }
}
