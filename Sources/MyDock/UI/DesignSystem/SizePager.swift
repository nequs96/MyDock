import AppKit
import SwiftUI

/// Horizontal paged previews with side chevrons, page dots and a caption, as in the iOS
/// widget gallery. Left/right arrow keys, the chevrons, the dots, a click-drag and a
/// horizontal trackpad swipe change the page. Pages move on a spring, instantly under
/// Reduce Motion. VoiceOver sees one adjustable element ("Size, Standard, 2 of 4").
struct SizePager<Page: Hashable, Content: View>: View {
    var pages: [Page]
    @Binding var selection: Page
    var caption: (Page) -> String
    var accessibilityLabel: String
    var content: (Page) -> Content

    @DockAccessibilityStyle() private var accessibility
    @State private var dragOffset: CGFloat = 0
    @State private var pageWidth: CGFloat = 0

    init(_ pages: [Page], selection: Binding<Page>, accessibilityLabel: String = "Size",
         caption: @escaping (Page) -> String, @ViewBuilder content: @escaping (Page) -> Content) {
        self.pages = pages
        self._selection = selection
        self.caption = caption
        self.accessibilityLabel = accessibilityLabel
        self.content = content
    }

    private var index: Int { pages.firstIndex(of: selection) ?? 0 }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                chevron("chevron.left", step: -1)
                PagerTrack(position: Double(index) - (pageWidth > 0 ? Double(dragOffset / pageWidth) : 0)) {
                    ForEach(pages, id: \.self) { page in
                        content(page).frame(maxWidth: .infinity)
                    }
                }
                .clipped()
                .contentShape(Rectangle())
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { pageWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { pageWidth = $0 }
                    }
                }
                .background(HorizontalSwipeReader { step(by: $0) })
                .gesture(drag)
                chevron("chevron.right", step: 1)
            }
            if pages.count > 1 { dots }
            Text(caption(selection))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .animation(nil, value: selection)
        }
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left: step(by: -1)
            case .right: step(by: 1)
            default: break
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(caption(selection)), \(index + 1) of \(pages.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(by: 1)
            case .decrement: step(by: -1)
            @unknown default: break
            }
        }
    }

    private func chevron(_ symbol: String, step offset: Int) -> some View {
        let target = index + offset
        let enabled = pages.indices.contains(target)
        return Button { step(by: offset) } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled && pages.count > 1 ? 1 : 0)
        .disabled(!enabled)
        .accessibilityHidden(true)
    }

    private var dots: some View {
        HStack(spacing: 0) {
            ForEach(Array(pages.enumerated()), id: \.offset) { offset, page in
                Button { select(page) } label: {
                    Circle()
                        .fill(Color.primary.opacity(offset == index ? 0.8 : 0.22))
                        .frame(width: 6, height: 6)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                // Rubber-band past the first and last page.
                let atEdge = (index == 0 && value.translation.width > 0) || (index == pages.count - 1 && value.translation.width < 0)
                dragOffset = atEdge ? value.translation.width * 0.3 : value.translation.width
            }
            .onEnded { value in
                let width = max(pageWidth, 1)
                let projected = value.predictedEndTranslation.width
                let threshold = width * 0.25
                let offset = projected < -threshold ? 1 : projected > threshold ? -1 : 0
                let target = pages.indices.contains(index + offset) ? index + offset : index
                DockDesign.Motion.perform(DockDesign.Motion.morph, reduceMotion: accessibility.reduceMotion) {
                    dragOffset = 0
                    selection = pages[target]
                }
            }
    }

    private func step(by offset: Int) {
        let target = index + offset
        guard pages.indices.contains(target) else { return }
        select(pages[target])
    }

    private func select(_ page: Page) {
        guard page != selection else { return }
        DockDesign.Motion.perform(DockDesign.Motion.morph, reduceMotion: accessibility.reduceMotion) {
            selection = page
        }
    }
}

/// Places every page side by side at the track's width and shows `position` (fractional
/// while dragging). Animating `position` slides the pages.
private struct PagerTrack: Layout {
    var position: Double
    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (offset, subview) in subviews.enumerated() {
            let x = bounds.minX + (Double(offset) - position) * bounds.width
            // Pages of different heights share a vertical centre.
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: bounds.width, height: proposal.height))
        }
    }
}

/// Turns one horizontal two-finger trackpad swipe over the view into a single page step.
/// It reads scroll events through a local monitor scoped to its own window and bounds,
/// and leaves vertical scrolling to the enclosing view.
private struct HorizontalSwipeReader: NSViewRepresentable {
    var onStep: (Int) -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.onStep = onStep
        return view
    }

    func updateNSView(_ view: SwipeView, context: Context) { view.onStep = onStep }

    final class SwipeView: NSView {
        var onStep: ((Int) -> Void)?
        nonisolated(unsafe) private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var fired = false
        private static let threshold: CGFloat = 40

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                // Local monitors run on the main thread; the event never leaves it.
                nonisolated(unsafe) let scrollEvent = event
                let consumed = MainActor.assumeIsolated { self?.consumes(scrollEvent) ?? false }
                return consumed ? nil : event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        /// True for the events of a horizontal swipe over this view, which the pager consumes.
        private func consumes(_ event: NSEvent) -> Bool {
            guard let window, event.window === window, event.hasPreciseScrollingDeltas else { return false }
            let point = convert(event.locationInWindow, from: nil)
            if event.phase == .began || event.phase == .mayBegin { accumulated = 0; fired = false }
            guard bounds.contains(point) || (event.phase.contains(.changed) && accumulated != 0) else { return false }
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || accumulated != 0 else { return false }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                accumulated = 0; fired = false
                return true
            }
            guard event.momentumPhase.isEmpty else { return true }
            accumulated += event.scrollingDeltaX
            if !fired, abs(accumulated) > Self.threshold {
                fired = true
                // Content follows the fingers: a swipe to the left reveals the next page.
                onStep?(accumulated < 0 ? 1 : -1)
            }
            return true
        }
    }
}
