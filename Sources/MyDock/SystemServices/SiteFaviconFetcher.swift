import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SiteFaviconFetcher {
    private static let maximumResponseBytes = 128 * 1_024
    private static let maximumPixelDimension = 1_024

    static func faviconURL(for destination: URL) -> URL? {
        guard let components = URLComponents(url: destination, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              let rawHost = components.host?.lowercased(),
              rawHost.contains("."),
              !isLocalHostname(rawHost),
              !isIPAddress(rawHost) else { return nil }

        var icon = URLComponents()
        icon.scheme = "https"
        icon.host = rawHost
        icon.path = "/favicon.ico"
        return icon.url
    }

    typealias FixtureTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static func fetchIconData(for destination: URL, transport: FixtureTransport? = nil) async -> Data? {
        guard transport != nil || AppRuntimeEnvironment.allowsNetwork else { return nil }
        guard let iconURL = faviconURL(for: destination), let host = iconURL.host else { return nil }
        if let transport {
            do {
                try Task.checkCancellation()
                let (data, response) = try await transport(URLRequest(url: iconURL))
                guard !Task.isCancelled, accepts(response) else { return nil }
                return normalizedPNG(from: data)
            } catch { return nil }
        }
        let hasPublicDNS = await Task.detached(priority: .utility) {
            resolvesOnlyToPublicAddresses(host)
        }.value
        guard hasPublicDNS, !Task.isCancelled else { return nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: iconURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 5
        request.httpShouldHandleCookies = false
        request.setValue("image/avif,image/webp,image/png,image/x-icon,image/vnd.microsoft.icon,image/*;q=0.8",
                         forHTTPHeaderField: "Accept")

        let policy = SameHostRedirectPolicy(host: host)
        do {
            let (data, response) = try await BoundedHTTPFetch.fetch(request, session: session, maximumBytes: maximumResponseBytes,
                                                                    delegate: policy)
            guard !Task.isCancelled, accepts(response), !policy.connectedToNonPublicAddress else { return nil }
            return normalizedPNG(from: data)
        } catch {
            return nil
        }
    }

    /// The response checks shared by the production and fixture transports. The body size is checked
    /// while reading and again in `normalizedPNG`.
    static func accepts(_ response: HTTPURLResponse) -> Bool {
        (200..<300).contains(response.statusCode)
            && response.mimeType?.lowercased().hasPrefix("image/") == true
            && response.expectedContentLength <= Int64(maximumResponseBytes)
    }

    /// Icon formats MyDock decodes (the ones the request's Accept header names, plus BMP); other ImageIO
    /// formats in web or archive bytes are refused before decoding.
    static let decodableTypeIdentifiers: Set<String> = [
        "com.microsoft.ico", "public.png", "public.jpeg", "com.compuserve.gif", "org.webmproject.webp", "com.microsoft.bmp",
        "public.avif"
    ]

    static func normalizedPNG(from data: Data) -> Data? {
        guard data.count <= maximumResponseBytes else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              decodableTypeIdentifiers.contains(type as String) else { return nil }
        let imageCount = min(CGImageSourceGetCount(source), 64)
        guard imageCount > 0 else { return nil }

        // favicon.ico usually lists 16 px first; prefer the largest usable frame (square on a tie) so Dock tiles stay sharp.
        var candidates: [(index: Int, size: Int, square: Bool)] = []
        for index in 0..<imageCount {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.intValue > 0, height.intValue > 0,
                  width.intValue <= maximumPixelDimension,
                  height.intValue <= maximumPixelDimension else { continue }
            candidates.append((index, min(width.intValue, height.intValue), width.intValue == height.intValue))
        }
        candidates.sort { lhs, rhs in lhs.size != rhs.size ? lhs.size > rhs.size : (lhs.square && !rhs.square) }

        for candidate in candidates {
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, candidate.index, thumbnailOptions as CFDictionary) else {
                continue
            }

            let output = NSMutableData()
            guard let png = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(png, thumbnail, nil)
            guard CGImageDestinationFinalize(png), output.length <= maximumResponseBytes else { return nil }
            return output as Data
        }
        return nil
    }

    private static func isLocalHostname(_ host: String) -> Bool {
        let trimmed = host.hasSuffix(".") ? String(host.dropLast()) : host
        let blockedSuffixes = ["localhost", "local", "internal", "test", "invalid", "example", "onion", "arpa"]
        return blockedSuffixes.contains(where: { trimmed == $0 || trimmed.hasSuffix(".\($0)") })
    }

    private static func isIPAddress(_ host: String) -> Bool {
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 { return true }
        var ipv6 = in6_addr()
        return host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1
    }

    private static func resolvesOnlyToPublicAddresses(_ host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return false }
        defer { freeaddrinfo(first) }

        var foundAddress = false
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let entry = current {
            guard let address = entry.pointee.ai_addr else {
                current = entry.pointee.ai_next
                continue
            }
            switch Int32(entry.pointee.ai_family) {
            case AF_INET:
                let rawAddress = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
                guard isPublicIPv4(UInt32(bigEndian: rawAddress)) else { return false }
                foundAddress = true
            case AF_INET6:
                let addressBytes = withUnsafeBytes(of: UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr) {
                    Array($0)
                }
                guard isPublicIPv6(addressBytes) else { return false }
                foundAddress = true
            default:
                return false
            }
            current = entry.pointee.ai_next
        }
        return foundAddress
    }

    /// A numeric IPv4 or IPv6 address that is public; anything else, including a host name, is not.
    static func isPublicAddressLiteral(_ address: String) -> Bool {
        // A scoped IPv6 literal (fe80::1%en0) is link-local and so never public.
        guard !address.contains("%") else { return false }
        var ipv4 = in_addr()
        if address.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return isPublicIPv4(UInt32(bigEndian: ipv4.s_addr))
        }
        var ipv6 = in6_addr()
        guard address.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 else { return false }
        return isPublicIPv6(withUnsafeBytes(of: ipv6) { Array($0) })
    }

    private static func isPublicIPv4(_ address: UInt32) -> Bool {
        let first = (address >> 24) & 0xff
        let second = (address >> 16) & 0xff
        let third = (address >> 8) & 0xff
        if first == 0 || first == 10 || first == 127 || first >= 224 { return false }
        if first == 100 && (second & 0xc0) == 0x40 { return false }
        if first == 169 && second == 254 { return false }
        if first == 172 && (second & 0xf0) == 16 { return false }
        if first == 192 && second == 0 && third == 0 { return false }
        if first == 192 && second == 0 && third == 2 { return false }
        if first == 192 && second == 168 { return false }
        if first == 198 && (second == 18 || second == 19) { return false }
        if first == 198 && second == 51 && third == 100 { return false }
        if first == 203 && second == 0 && third == 113 { return false }
        return true
    }

    private static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16,
              (bytes[0] & 0xe0) == 0x20,
              !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8),
              !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x00 && bytes[3] == 0x00) else { return false }
        return true
    }
}

/// Keeps redirects on the icon's host, and records whether a direct connection reached a non-public address,
/// for example when DNS answered differently after MyDock's own check (DNS rebinding).
private final class SameHostRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let host: String
    private let lock = NSLock()
    private var reachedNonPublicAddress = false

    init(host: String) {
        self.host = host
    }

    var connectedToNonPublicAddress: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reachedNonPublicAddress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        // Through a proxy the remote address is the proxy's, which may be on the local network.
        let nonPublic = metrics.transactionMetrics.contains { transaction in
            guard !transaction.isProxyConnection, let address = transaction.remoteAddress else { return false }
            return !SiteFaviconFetcher.isPublicAddressLiteral(address)
        }
        guard nonPublic else { return }
        lock.lock()
        reachedNonPublicAddress = true
        lock.unlock()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              url.host?.caseInsensitiveCompare(host) == .orderedSame,
              url.port == nil || url.port == 443 else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
