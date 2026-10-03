import Foundation
import Testing
@testable import MyDock

@MainActor
struct RegistryQualificationTests {
    @Test func everyRegistryFamilyHasProviderPresentationAndQAPage() {
        let names = WidgetRegistry.all.map(\.name)
        #expect(names.count == Set(names).count)
        let paged = PremiumVisualQA.semanticLayoutPages().flatMap { $0 }
        #expect(paged == names)
        for name in names {
            #expect(!String(describing: type(of: WidgetProviderRegistry.provider(for: name))).contains("PlaceholderWidgetProvider"), "\(name) has no provider")
            #expect(!WidgetPresentationCatalog.options(for: name).isEmpty, "\(name) has no presentation option")
            #expect(paged.contains(name), "\(name) missing from QA export")
        }
    }

    @Test func pageListChunksWithoutDroppingTail() {
        let kinds = (0..<35).map { "K\($0)" }
        let pages = PremiumVisualQA.semanticLayoutPages(kinds: kinds, pageSize: 10)
        #expect(pages.count == 4)
        #expect(pages.last?.count == 5)
        #expect(pages.flatMap { $0 } == kinds)
    }
}
