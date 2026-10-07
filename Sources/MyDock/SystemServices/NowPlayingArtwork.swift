import AppKit
import ImageIO

enum NowPlayingArtwork {
    private static let maximumRemoteBytes = 2 * 1_024 * 1_024
    private static let maximumLocalBytes = 8 * 1_024 * 1_024

    static func spotifyURL(from rawValue: String) -> URL? {
        guard let components = URLComponents(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "i.scdn.co",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              components.query == nil, components.fragment == nil,
              components.path.hasPrefix("/image/"),
              let url = components.url else { return nil }
        return url
    }

    typealias FixtureTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static func fetchSpotifyArtwork(at url: URL, transport: FixtureTransport? = nil) async -> Data? {
        guard transport != nil || AppRuntimeEnvironment.allowsNetwork else { return nil }
        guard spotifyURL(from: url.absoluteString) != nil else { return nil }
        if let transport {
            do {
                try Task.checkCancellation()
                let (data, response) = try await transport(URLRequest(url: url))
                guard !Task.isCancelled, (200..<300).contains(response.statusCode),
                      response.mimeType?.lowercased().hasPrefix("image/") == true,
                      response.expectedContentLength <= Int64(maximumRemoteBytes),
                      data.count <= maximumRemoteBytes else { return nil }
                return data
            } catch { return nil }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: NoArtworkRedirects())
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  response.mimeType?.lowercased().hasPrefix("image/") == true,
                  response.expectedContentLength <= Int64(maximumRemoteBytes) else { return nil }
            var data = Data()
            if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
            for try await byte in bytes {
                guard data.count < maximumRemoteBytes, !Task.isCancelled else { return nil }
                data.append(byte)
            }
            return Task.isCancelled ? nil : data
        } catch {
            return nil
        }
    }

    /// Decodes and downsamples on any thread: CGImageSource and the resulting CGImage are thread-safe.
    static func decodedThumbnail(from data: Data) -> NowPlayingDecodedArtwork? {
        guard !data.isEmpty, data.count <= maximumLocalBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0,
              width.intValue <= 8_192, height.intValue <= 8_192 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 192,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NowPlayingDecodedArtwork(cgImage: image)
    }
}

/// Carries a decoded thumbnail from a worker back to the main actor. A CGImage is immutable.
struct NowPlayingDecodedArtwork: @unchecked Sendable {
    let cgImage: CGImage
    var image: NSImage { NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)) }
}

private final class NoArtworkRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
