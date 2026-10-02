import Foundation
import Testing
@testable import MyDock

struct DockBadgePolicyTests {
    @Test func badgeLabelsHideEmptyAndZeroValuesAndCapLargeCounts() {
        #expect(DockBadgeValuePolicy.visibleLabel(nil) == nil)
        #expect(DockBadgeValuePolicy.visibleLabel("  ") == nil)
        #expect(DockBadgeValuePolicy.visibleLabel("0") == nil)
        #expect(DockBadgeValuePolicy.visibleLabel("000") == nil)
        #expect(DockBadgeValuePolicy.visibleLabel(" 12 ") == "12")
        #expect(DockBadgeValuePolicy.visibleLabel("1000") == "999+")
        #expect(DockBadgeValuePolicy.visibleLabel("999+") == "999+")
    }

    @Test func badgeLabelsBoundUnexpectedText() {
        #expect(DockBadgeValuePolicy.visibleLabel("New message") == "New mess")
    }

    @Test func badgeMappingSkipsEmptyAndZeroAndKeepsOneValuePerApp() {
        let entries = [
            DockBadgeEntry(bundleIdentifier: "com.example.mail", statusLabel: "4"),
            DockBadgeEntry(bundleIdentifier: "com.example.mail", statusLabel: "9"),
            DockBadgeEntry(bundleIdentifier: "com.example.chat", statusLabel: "0"),
            DockBadgeEntry(bundleIdentifier: "", statusLabel: "2")
        ]

        #expect(DockBadgeValuePolicy.badges(from: entries) == ["com.example.mail": "4"])
    }
}
