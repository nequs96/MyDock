import Foundation

struct ShelfFile: Codable, Hashable, Identifiable {
    var id = UUID()
    var url: URL
    var bookmark: Data?

    init(url: URL) {
        self.url = url.standardizedFileURL
        bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    var resolvedURL: URL { resolution.url }

    /// Resolved location plus whether the stored bookmark reported itself stale.
    var resolution: (url: URL, isStale: Bool) {
        guard let bookmark else { return (url, false) }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else { return (url, false) }
        return (resolved, stale)
    }

    /// Points this entry at a new file while keeping its identity (and therefore title and position).
    mutating func relocate(to newURL: URL) {
        let normalized = newURL.standardizedFileURL
        url = normalized
        let data = try? normalized.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        bookmark = (data?.count ?? 0) > 65_536 ? nil : data
    }
}

struct TextSnippet: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var text: String
}

struct QuickLink: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var url: URL
}

enum FileShelfPolicy {
    static let capacity = 50
    /// Keep references only. Originals are never moved or deleted by the shelf.
    static func adding(_ urls: [URL], to entries: [ShelfFile]) -> [ShelfFile] {
        var result = entries
        var known = Set(entries.map { $0.resolvedURL.standardizedFileURL })
        for url in urls.prefix(capacity) where url.isFileURL && url.host.map({ $0.isEmpty || $0 == "localhost" }) != false {
            let normalized = url.standardizedFileURL
            guard result.count < capacity else { break }
            guard normalized.path.utf8.count <= 8_192, normalized.absoluteString.utf8.count <= 32_768, known.insert(normalized).inserted else { continue }
            var entry = ShelfFile(url: normalized)
            if (entry.bookmark?.count ?? 0) > 65_536 { entry.bookmark = nil }
            result.append(entry)
        }
        return result
    }
}

extension FileShelfPolicy {
    enum RelocationResult: Equatable {
        case relocated([ShelfFile])
        case duplicate(existingName: String)
        case notFound
        case notFileURL
    }

    /// Replaces one entry's URL and bookmark atomically. A file already kept by another entry is rejected and nothing changes.
    static func relocating(_ id: UUID, to newURL: URL, in entries: [ShelfFile], fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> RelocationResult {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return .notFound }
        guard newURL.isFileURL else { return .notFileURL }
        let normalized = newURL.standardizedFileURL
        guard fileExists(normalized) else { return .notFound }
        if let other = entries.first(where: { $0.id != id && $0.resolvedURL.standardizedFileURL == normalized }) {
            return .duplicate(existingName: other.resolvedURL.lastPathComponent)
        }
        var result = entries
        result[index].relocate(to: normalized)
        return .relocated(result)
    }

    /// Regenerates stale bookmarks for entries whose file resolves. Missing entries are kept untouched. Returns nil when nothing changed.
    static func refreshingStaleBookmarks(_ entries: [ShelfFile], fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
                                         resolve: (ShelfFile) -> (url: URL, isStale: Bool) = { $0.resolution }) -> [ShelfFile]? {
        var result = entries
        var changed = false
        for index in result.indices {
            let resolution = resolve(result[index])
            guard resolution.isStale, fileExists(resolution.url) else { continue }
            result[index].relocate(to: resolution.url)
            changed = true
        }
        return changed ? result : nil
    }

    static func isAvailable(_ entry: ShelfFile, fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> Bool {
        fileExists(entry.resolvedURL)
    }
}

enum ConversionCategory: String, CaseIterable, Identifiable {
    case length, mass, temperature, volume, speed, data
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var units: [ConversionUnit] {
        switch self {
        case .length: [.init("Meters", "m", 1), .init("Kilometers", "km", 1_000), .init("Centimeters", "cm", 0.01), .init("Inches", "in", 0.0254), .init("Feet", "ft", 0.3048), .init("Miles", "mi", 1_609.344)]
        case .mass: [.init("Kilograms", "kg", 1), .init("Grams", "g", 0.001), .init("Pounds", "lb", 0.45359237), .init("Ounces", "oz", 0.028349523125)]
        case .temperature: [.init("Celsius", "°C", 1, 273.15), .init("Fahrenheit", "°F", 5 / 9, 255.3722222222222), .init("Kelvin", "K", 1)]
        case .volume: [.init("Liters", "L", 1), .init("Milliliters", "mL", 0.001), .init("US gallons", "gal", 3.785411784), .init("US cups", "cup", 0.2365882365)]
        case .speed: [.init("Meters per second", "m/s", 1), .init("Kilometers per hour", "km/h", 1 / 3.6), .init("Miles per hour", "mph", 0.44704), .init("Knots", "kn", 0.5144444444444445)]
        case .data: [.init("Bytes", "B", 1), .init("Kilobytes", "kB", 1_000), .init("Megabytes", "MB", 1_000_000), .init("Gigabytes", "GB", 1_000_000_000), .init("Kibibytes", "KiB", 1_024), .init("Mebibytes", "MiB", 1_048_576), .init("Gibibytes", "GiB", 1_073_741_824)]
        }
    }
}

struct ConversionUnit: Identifiable {
    var title: String
    var symbol: String
    var scale: Double
    var offset: Double
    var id: String { symbol }
    init(_ title: String, _ symbol: String, _ scale: Double, _ offset: Double = 0) {
        self.title = title; self.symbol = symbol; self.scale = scale; self.offset = offset
    }
    static func convert(_ value: Double, from: Self, to: Self) -> Double? {
        guard value.isFinite, from.scale > 0, to.scale > 0 else { return nil }
        let result = (value * from.scale + from.offset - to.offset) / to.scale
        return result.isFinite ? result : nil
    }
}

enum ConversionResultFormatter {
    /// Six significant digits keep common measurements readable. Scientific notation
    /// preserves very small nonzero values and avoids impractically long large results.
    static func text(_ value: Double, locale: Locale = .current) -> String {
        guard value.isFinite else { return "—" }
        let magnitude = abs(value)
        let style = FloatingPointFormatStyle<Double>.number
            .precision(.significantDigits(1...6)).grouping(.never).locale(locale)
        if magnitude > 0 && (magnitude < 0.0001 || magnitude >= 1_000_000_000) {
            return value.formatted(style.notation(.scientific))
        }
        return (value == 0 ? 0 : value).formatted(style)
    }
}

enum HexColor {
    static func components(_ input: String) -> (red: Double, green: Double, blue: Double)? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, text.allSatisfy({ $0.isASCII && $0.isHexDigit }), let rgb = UInt32(text, radix: 16) else { return nil }
        return (Double((rgb >> 16) & 255) / 255, Double((rgb >> 8) & 255) / 255, Double(rgb & 255) / 255)
    }
    static func string(red: Double, green: Double, blue: Double) -> String {
        func byte(_ value: Double) -> Int { Int((min(1, max(0, value.isFinite ? value : 0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
