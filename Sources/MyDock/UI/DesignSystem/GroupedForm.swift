import SwiftUI

/// An inset grouped section in the System Settings style: an optional header, rows in one
/// rounded container with inset hairline separators, and an optional short footer.
struct GroupedSection<Content: View>: View {
    var header: String?
    var footer: String?
    var separatorInset: CGFloat
    var content: Content
    @DockAccessibilityStyle() private var accessibility

    init(_ header: String? = nil, footer: String? = nil,
         separatorInset: CGFloat = DockDesign.Grouped.separatorInset, @ViewBuilder content: () -> Content) {
        self.header = header
        self.footer = footer
        self.separatorInset = separatorInset
        self.content = content()
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DockDesign.Grouped.radius, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header).font(DockDesign.Grouped.headerFont)
                    .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
                    .accessibilityAddTraits(.isHeader)
            }
            GroupedRows(separatorInset: separatorInset) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DockDesign.Grouped.fill, in: shape)
                .clipShape(shape)
                .overlay {
                    if accessibility.contrast == .increased {
                        shape.strokeBorder(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                    }
                }
            if let footer {
                Text(footer).font(DockDesign.Grouped.footerFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stacks rows and draws a separator between each pair, inset to the title column.
private struct GroupedRows<Content: View>: View {
    var separatorInset: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 15.0, *) {
            Group(subviews: content) { rows in
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        row
                        if index < rows.count - 1 { GroupedSeparator(inset: separatorInset) }
                    }
                }
            }
        } else {
            _VariadicView.Tree(GroupedRowsRoot(separatorInset: separatorInset)) { content }
        }
    }
}

private struct GroupedRowsRoot: _VariadicView_MultiViewRoot {
    var separatorInset: CGFloat
    @ViewBuilder func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(spacing: 0) {
            ForEach(children) { row in
                row
                if row.id != last { GroupedSeparator(inset: separatorInset) }
            }
        }
    }
}

private struct GroupedSeparator: View {
    var inset: CGFloat
    @DockAccessibilityStyle() private var accessibility
    var body: some View {
        Rectangle()
            .fill(accessibility.contrast == .increased ? DockDesign.Outline.color(.increased) : DockDesign.Grouped.separator)
            .frame(height: 0.5)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// A row of an inset grouped form.
///
/// Leading glyph in a coloured rounded square, a title, an optional subtitle, and a trailing
/// value, chevron, switch or custom accessory. Rows with an action are buttons; `.destructive`
/// and `.button` rows draw a tinted title, usually without a glyph.
struct GroupedRow<Accessory: View>: View {
    enum Role { case standard, button, destructive }

    var title: String
    var subtitle: String?
    var symbol: String?
    var symbolColor: Color
    var role: Role
    var trailing: Trailing
    var action: (() -> Void)?
    var accessory: Accessory

    enum Trailing {
        case none
        case value(String)
        case chevron(value: String?)
        /// Inline disclosure: the chevron turns down when expanded.
        case disclosure(Bool)
        case toggle(Binding<Bool>)
        case custom
    }

    @Environment(\.isEnabled) private var isEnabled
    @DockAccessibilityStyle() private var accessibility

    var body: some View {
        switch trailing {
        case .toggle(let isOn):
            rowContent(showsAccessory: false) {
                Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel(title)
                    .accessibilityHint(subtitle ?? "")
            }
            .accessibilityElement(children: .contain)
        default:
            if let action {
                Button(action: action) {
                    rowContent(showsAccessory: true) { EmptyView() }
                }
                .buttonStyle(GroupedRowButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(hintText)
                .accessibilityAddTraits(.isButton)
            } else if case .custom = trailing {
                // The subtitle stays readable inside the group: it often carries status (a reset time, a reason).
                rowContent(showsAccessory: true) { EmptyView() }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(title)
            } else {
                rowContent(showsAccessory: true) { EmptyView() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue(accessibilityValue)
                    .accessibilityHint(subtitle ?? "")
            }
        }
    }

    private var accessibilityValue: String {
        switch trailing {
        case .value(let value): value
        case .chevron(let value): value ?? ""
        case .disclosure(let expanded): expanded ? "Expanded" : "Collapsed"
        default: ""
        }
    }

    private var hintText: String {
        if case .disclosure(let expanded) = trailing { return expanded ? "Collapses this section" : "Expands this section" }
        return subtitle ?? ""
    }

    private var titleColor: Color {
        switch role {
        case .standard: .primary
        case .button: DockDesign.accent
        case .destructive: Color(nsColor: .systemRed)
        }
    }

    @ViewBuilder private func rowContent<Control: View>(showsAccessory: Bool, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: DockDesign.Grouped.glyphSpacing) {
            if let symbol {
                GroupedRowGlyph(symbol: symbol, color: symbolColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(DockDesign.Grouped.titleFont).foregroundStyle(titleColor)
                    .lineLimit(DockDesign.Module.maxTextLines)
                    .accessibilityHidden(isCustom)
                if let subtitle {
                    Text(subtitle).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                        .lineLimit(DockDesign.Module.maxTextLines)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityHidden(isToggle)
            Spacer(minLength: 8)
            if showsAccessory { trailingView }
            control()
        }
        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
        .padding(.vertical, DockDesign.Grouped.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: DockDesign.Grouped.rowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.45)
    }

    /// Switch rows read the title and subtitle from the switch itself, so the visible text is hidden.
    private var isToggle: Bool { if case .toggle = trailing { true } else { false } }
    /// Custom-accessory rows carry the title on the container, so only the visible title is hidden
    /// to keep VoiceOver from reading it twice.
    private var isCustom: Bool { if case .custom = trailing { true } else { false } }

    @ViewBuilder private var trailingView: some View {
        switch trailing {
        case .none, .toggle: EmptyView()
        case .value(let value):
            Text(value).font(DockDesign.Grouped.titleFont).foregroundStyle(.secondary).lineLimit(1)
        case .chevron(let value):
            HStack(spacing: 6) {
                if let value { Text(value).font(DockDesign.Grouped.titleFont).foregroundStyle(.secondary).lineLimit(1) }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        case .disclosure(let expanded):
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .animation(accessibility.animation(DockDesign.Motion.disclosure), value: expanded)
                .accessibilityHidden(true)
        case .custom: accessory
        }
    }
}

extension GroupedRow where Accessory == EmptyView {
    /// Informational or navigation row: trailing value text and/or a chevron. With an action it is a button.
    init(_ title: String, subtitle: String? = nil, symbol: String? = nil, color: Color = .gray,
         value: String? = nil, chevron: Bool = false, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.symbolColor = color
        self.role = .standard
        self.trailing = chevron ? .chevron(value: value) : value.map(Trailing.value) ?? .none
        self.action = action
        self.accessory = EmptyView()
    }

    /// Disclosure row: the chevron turns down when expanded; VoiceOver reads Expanded or Collapsed.
    init(_ title: String, isExpanded: Bool, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = nil
        self.symbol = nil
        self.symbolColor = .gray
        self.role = .standard
        self.trailing = .disclosure(isExpanded)
        self.action = action
        self.accessory = EmptyView()
    }

    /// Switch row. VoiceOver reads the title with the switch's value and traits.
    init(_ title: String, subtitle: String? = nil, symbol: String? = nil, color: Color = .gray, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.symbolColor = color
        self.role = .standard
        self.trailing = .toggle(isOn)
        self.action = nil
        self.accessory = EmptyView()
    }

    /// Button row (accent title) or destructive row (red title). A glyph is optional.
    init(_ title: String, role: Role, symbol: String? = nil, color: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = nil
        self.symbol = symbol
        self.symbolColor = color ?? (role == .destructive ? Color(nsColor: .systemRed) : DockDesign.accent)
        self.role = role
        self.trailing = .none
        self.action = action
        self.accessory = EmptyView()
    }
}

extension GroupedRow {
    /// Row with a custom trailing control (picker, stepper, menu, slider…). The control stays
    /// its own accessibility element; give it a label if the title is not enough.
    init(_ title: String, subtitle: String? = nil, symbol: String? = nil, color: Color = .gray,
         @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.symbolColor = color
        self.role = .standard
        self.trailing = .custom
        self.action = nil
        self.accessory = accessory()
    }
}

/// A short note inside a grouped card, inset like every other row. `.warning` adds the orange
/// triangle; an optional small trailing button acts on the note (Retry, Open Settings…).
struct GroupedNote: View {
    enum Tone { case secondary, warning }
    var text: String
    var tone: Tone
    var showsProgress: Bool
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ text: String, tone: Tone = .secondary, showsProgress: Bool = false,
         actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.tone = tone
        self.showsProgress = showsProgress
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if showsProgress { ProgressView().controlSize(.small) }
            Group {
                switch tone {
                case .secondary: Text(text).foregroundStyle(.secondary)
                case .warning: Label(text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action).controlSize(.small)
            }
        }
        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
        .padding(.vertical, DockDesign.Grouped.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// White SF Symbol in a coloured rounded square, as in System Settings.
struct GroupedRowGlyph: View {
    var symbol: String
    var color: Color
    var size: CGFloat = DockDesign.Grouped.glyphSize
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.56, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * DockDesign.Grouped.glyphRadius / DockDesign.Grouped.glyphSize, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Hover and press highlight for actionable rows. Keyboard focus uses the system ring.
private struct GroupedRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GroupedRowButtonBody(configuration: configuration)
    }
    private struct GroupedRowButtonBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background(Color.primary.opacity(configuration.isPressed ? 0.08 : hovered ? 0.04 : 0))
                .onHover { hovered = $0 }
        }
    }
}
