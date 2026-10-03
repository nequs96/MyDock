import Foundation
import Testing
@testable import MyDock

struct ModeClarityTests {
    @Test func actionTitlesDistinguishActivateFromApply() {
        #expect(DockProfileStatus.actionTitle(for: .custom) == "Activate")
        #expect(DockProfileStatus.actionTitle(for: .native) == "Apply")
        #expect(DockProfileStatus.actionHelp(for: .native).contains("after you quit"))
    }

    @Test func captionSeparatesEditingFromLive() {
        #expect(DockProfileStatus.inactive.workspaceCaption(for: .custom, setupMode: .both).hasPrefix("Editing only"))
        #expect(DockProfileStatus.inactive.workspaceCaption(for: .custom, setupMode: .nativeOnly).contains("turn on the Custom Dock"))
        #expect(DockProfileStatus.active.workspaceCaption(for: .custom, setupMode: .both).contains("on screen"))
        #expect(DockProfileStatus.applied(hidden: true).workspaceCaption(for: .native, setupMode: .customMain).contains("hidden"))
        #expect(DockProfileStatus.inactive.workspaceCaption(for: .native, setupMode: .both).contains("Apply"))
    }

    @Test func everySetupModeStatesNativeConsequence() {
        for mode in SetupMode.allCases { #expect(!DockProfileStatus.nativeConsequence(for: mode).isEmpty) }
        #expect(DockProfileStatus.nativeConsequence(for: .customMain).contains("hidden"))
        #expect(DockProfileStatus.nativeConsequence(for: .both).contains("visible"))
    }

    @Test func itemAccessibilityLabelIncludesKindAndMissingState() {
        let widget = DockItem.widget("Clock")
        #expect(DockItemAccessibility.label(for: widget, missing: false).hasSuffix("Widget"))
        #expect(DockItemAccessibility.label(for: widget, missing: true).hasSuffix(", missing"))
        #expect(DockItemAccessibility.label(for: .spacer(.small), missing: false).hasSuffix("Spacer"))
    }
}
