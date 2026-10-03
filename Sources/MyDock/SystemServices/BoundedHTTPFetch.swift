import Foundation

enum BoundedHTTPFetchError: Error, Equatable {
    case notHTTP
    case tooLarge
    case deadlineExceeded
}

/// Streams a response and stops as soon as the byte limit is exceeded, so an oversized
/// body is never fully allocated. Callers keep their own host restrictions and timeouts.
enum BoundedHTTPFetch {
    static func ephemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    static func fetch(_ request: URLRequest, session: URLSession, maximumBytes: Int,
                      maximumDuration: TimeInterval = 60) async throws -> (data: Data, response: HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw BoundedHTTPFetchError.notHTTP }
        let data = try await collect(bytes, expectedLength: http.expectedContentLength,
                                     maximumBytes: maximumBytes, maximumDuration: maximumDuration)
        return (data, http)
    }

    /// Throws before reading the body when the declared length is already over the limit, and while
    /// reading as soon as the running total passes it. Leaving the loop cancels the transfer.
    static func collect<Bytes: AsyncSequence>(_ bytes: Bytes, expectedLength: Int64 = -1, maximumBytes: Int,
                                              maximumDuration: TimeInterval = 60) async throws -> Data
    where Bytes.Element == UInt8 {
        if expectedLength > Int64(maximumBytes) { throw BoundedHTTPFetchError.tooLarge }
        let deadline = Date.now.addingTimeInterval(maximumDuration)
        var data = Data()
        if expectedLength > 0 { data.reserveCapacity(Int(min(expectedLength, Int64(maximumBytes)))) }
        for try await byte in bytes {
            if data.count >= maximumBytes { throw BoundedHTTPFetchError.tooLarge }
            data.append(byte)
            if data.count & 0x3FFF == 0 {
                try Task.checkCancellation()
                if Date.now > deadline { throw BoundedHTTPFetchError.deadlineExceeded }
            }
        }
        return data
    }
}
