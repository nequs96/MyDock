import SwiftUI

extension WidgetLayoutPresets {
    static let audioOutput = [option(.compact, 96, "Device icon and name"), option(.wide, 164, "Device name and volume")]
}

struct AudioOutputWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AudioOutputCompactView())
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AudioOutputPopoutView())
    }
}

/// The Audio Output module. Compact: the device icon over its short name. Wide: the full device name
/// over its volume (or "Muted", or the connection when the device sets its own volume). Neutral at rest.
struct AudioOutputDockFace: View {
    var reading: AudioOutputFaceReading
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    private let kind = "Audio Output"

    var body: some View {
        Group {
            if WidgetModuleMetrics.isNarrow(width) {
                WidgetIcon(kind: kind, symbol: reading.symbol, size: 36, enclosed: true)
            } else if layout == .wide {
                HStack(spacing: 8) {
                    WidgetIcon(kind: kind, symbol: reading.symbol, size: 30, enclosed: true)
                    ModuleStack(kind: kind, label: reading.name, value: reading.detail ?? "—", size: .medium,
                                showsGlyph: false, keepsLeading: true)
                }
            } else {
                VStack(spacing: 2) {
                    WidgetIcon(kind: kind, symbol: reading.symbol, size: 28, enclosed: true)
                    Text(reading.shortName).font(DockDesign.Module.label).lineLimit(1)
                        .minimumScaleFactor(DockDesign.Module.minimumTextSize / 11)
                }
            }
        }
        .moduleInsets()
    }
}

private struct AudioOutputCompactView: View {
    @Environment(\.dockWidgetContentWidth) private var contentWidth
    @StateObject private var service = AudioOutputService.shared
    @State private var subscriptionID = UUID()

    private var reading: AudioOutputFaceReading {
        AudioOutputFaceReading(device: service.currentDevice, controls: service.controls)
    }

    var body: some View {
        AudioOutputDockFace(reading: reading)
            .frame(width: contentWidth, height: 54)
            .onAppear { service.subscribe(subscriptionID) }
            .onDisappear { service.unsubscribe(subscriptionID) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Audio Output")
            .accessibilityValue(reading.accessibilityValue)
    }
}

private struct AudioOutputPopoutView: View {
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @Environment(\.widgetAccent) private var accent
    @StateObject private var service = AudioOutputService.shared
    @State private var subscriptionID = UUID()
    /// The slider's value while it is being dragged, so the thumb follows the pointer.
    @State private var draftVolume: Double?
    private let kind = "Audio Output"

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            if showsHero {
                hero
                deviceList
                controlsSection
                if let error = service.lastError {
                    Label(error.message, systemImage: "exclamationmark.triangle")
                        .font(DockDesign.Grouped.footerFont).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
                        .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { if showsHero { service.subscribe(subscriptionID, popout: true) } }
        .onDisappear { service.unsubscribe(subscriptionID) }
    }

    // MARK: Hero

    private var hero: some View {
        let device = service.currentDevice
        let reading = AudioOutputFaceReading(device: device, controls: service.controls)
        return WidgetPopoutHero(value: device?.name ?? "No output device",
                                caption: device == nil ? nil : reading.detail,
                                symbol: reading.symbol, forcedStyle: .status)
    }

    // MARK: Devices

    @ViewBuilder private var deviceList: some View {
        GroupedSection("Output") {
            if service.devices.isEmpty {
                GroupedRow("No output devices", symbol: "speaker.slash")
            } else {
                ForEach(service.devices) { device in deviceRow(device) }
            }
        }
    }

    private func deviceRow(_ device: AudioOutputDevice) -> some View {
        let isCurrent = device.id == service.currentID
        // Colour marks state only: the current device takes the family accent; every other row stays neutral.
        let tint = WidgetPalette.resolved(kind: kind, accent: accent, active: isCurrent)
        return Button { service.select(device) } label: {
            WidgetPopoutRow {
                HStack(spacing: DockDesign.Grouped.glyphSpacing) {
                    Image(systemName: device.symbol).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tint).frame(width: 22).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name).font(DockDesign.Grouped.titleFont).lineLimit(DockDesign.Module.maxTextLines)
                        if let title = device.transport.title {
                            Text(title).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                        .opacity(isCurrent ? 1 : 0).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.name)
        .accessibilityValue([device.transport.title, isCurrent ? "Current output" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(isCurrent ? "" : "Switches the Mac’s sound output to this device")
        .accessibilityAddTraits(isCurrent ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
    }

    // MARK: Volume and mute

    @ViewBuilder private var controlsSection: some View {
        let controls = service.controls
        if controls.volume != nil || controls.isMuted != nil {
            GroupedSection {
                if let volume = controls.volume {
                    volumeRow(current: draftVolume ?? volume)
                }
                if let muted = controls.isMuted {
                    GroupedRow("Mute", isOn: Binding(get: { muted }, set: { service.setMuted($0) }))
                }
            }
        }
        if service.currentDevice != nil, controls.volume == nil {
            WidgetPopoutCaption("This device’s volume is controlled by the device.")
        }
    }

    private func volumeRow(current: Double) -> some View {
        WidgetPopoutRow {
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(.system(size: 11)).foregroundStyle(.secondary).accessibilityHidden(true)
                Slider(value: Binding(get: { current }, set: { value in
                    draftVolume = value
                    service.setVolume(value)
                }), in: 0...1, onEditingChanged: { editing in
                    if !editing { draftVolume = nil }
                })
                .accessibilityLabel("Volume")
                .accessibilityValue(AudioOutputPresentation.percentText(current))
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
    }
}
