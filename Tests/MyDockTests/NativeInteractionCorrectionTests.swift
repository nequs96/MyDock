import Foundation
import Testing
@testable import MyDock

struct NativeInteractionCorrectionTests {
    private func application(path: String = "/fixture/apps/Editor.app", processID: Int32 = 41,
                             launchDate: Date = Date(timeIntervalSince1970: 100)) -> NativeApplicationIdentity {
        NativeApplicationIdentity(processID: processID, bundleIdentifier: "fixture.editor",
                                  bundleURL: URL(fileURLWithPath: path), launchDate: launchDate)
    }

    @Test func selectedApplicationRejectsOtherCopyAndReusedProcess() {
        let selected = application()
        #expect(selected.matches(application()))
        #expect(!selected.matches(application(path: "/fixture/other/Editor.app")))
        #expect(!selected.matches(application(processID: 42)))
        #expect(!selected.matches(application(launchDate: Date(timeIntervalSince1970: 200))))
        var otherBundle = selected
        otherBundle.bundleIdentifier = "fixture.impostor"
        #expect(!selected.matches(otherBundle))
    }

    @Test func equivalentPathsHaveOneInstalledIdentity() {
        let first = URL(fileURLWithPath: "/fixture/apps/Editor.app")
        let second = URL(fileURLWithPath: "/fixture/apps/../apps/Editor.app")
        #expect(InstalledApplicationIdentity.key(bundleIdentifier: "fixture.editor", bundleURL: first)
                == InstalledApplicationIdentity.key(bundleIdentifier: "fixture.editor", bundleURL: second))
        #expect(application().matches(application(path: second.path)))
    }

    @Test func runtimeListRetainsInstalledCopiesButCollapsesDuplicateProcesses() {
        func descriptor(_ path: String, regular: Bool = true, terminated: Bool = false) -> RunningApplicationDescriptor {
            RunningApplicationDescriptor(bundleIdentifier: "fixture.editor", name: "Editor",
                                         bundleURL: URL(fileURLWithPath: path),
                                         isRegularApplication: regular, isTerminated: terminated)
        }
        let first = descriptor("/fixture/apps/Editor.app")
        let other = descriptor("/fixture/other/Editor.app")
        let input = [other, first, first, descriptor("/fixture/background/Editor.app", regular: false),
                     descriptor("/fixture/terminated/Editor.app", terminated: true)]
        let visible = RunningApplicationFilter.visible(input, excluding: [])
        #expect(visible.count == 2)
        #expect(Set(visible.map(\.id)) == Set([first.id, other.id]))
        #expect(visible.map(\.id) == RunningApplicationFilter.visible(Array(input.reversed()), excluding: []).map(\.id))
    }

    @Test func rawUntitledAndWhitespaceTitlesResolveWithoutDisplayFallback() {
        let empty = DockWindowDescriptor(processID: 41, windowIndex: 0, bundleIdentifier: "fixture.editor",
                                         applicationName: "Editor", title: "Editor", isMinimized: false,
                                         accessibilityIdentifier: nil, rawTitle: "", applicationIdentity: application())
        // The raw AX title is the identity title; the display fallback never stands in for it.
        #expect(empty.identityTitle == "")
        var padded = empty
        padded.rawTitle = "  draft  "
        padded.title = "draft"
        #expect(padded.identityTitle == "  draft  ")
    }

    @Test func indistinguishableWindowsAreNeverChosenByIndex() {
        #expect(WindowRestoreIdentity.uniqueIndex([0, 1]) == nil)
        #expect(WindowRestoreIdentity.uniqueIndex([]) == nil)
        #expect(WindowRestoreIdentity.uniqueIndex([2]) == 2)
    }

    @Test func windowObservationIDsExpireAcrossProcessLifetimes() {
        var first = DockWindowDescriptor(processID: 41, windowIndex: 0, bundleIdentifier: "fixture.editor",
                                         applicationName: "Editor", title: "Draft", isMinimized: false,
                                         accessibilityIdentifier: "window", rawTitle: "Draft", applicationIdentity: application())
        let originalID = first.id
        first.applicationIdentity = application(launchDate: Date(timeIntervalSince1970: 200))
        #expect(first.id != originalID)
    }
}
