import Foundation

enum BoundedHTTPFetchError: Error, Equatable {
    case notHTTP
    case tooLarge
    case deadlineExceeded
    case invalidLimit
}

extension BoundedHTTPFetchError {
    /// User-facing copy for a failed transfer from `provider`, such as "Stripe".
    func message(provider: String) -> String {
        switch self {
        case .deadlineExceeded: "\(provider) took too long to respond. Try again later."
        case .tooLarge: "\(provider) sent a response larger than MyDock accepts."
        case .notHTTP, .invalidLimit: "\(provider) returned data MyDock could not read. Try again later."
        }
    }
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

    /// `delegate` receives this task's events, for example a redirect policy.
    static func fetch(_ request: URLRequest, session: URLSession, maximumBytes: Int,
                      maximumDuration: TimeInterval = 60,
                      delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (data: Data, response: HTTPURLResponse) {
        guard maximumBytes > 0 else { throw BoundedHTTPFetchError.invalidLimit }
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
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
        guard maximumBytes > 0 else { throw BoundedHTTPFetchError.invalidLimit }
        guard maximumDuration > 0, maximumDuration.isFinite else { throw BoundedHTTPFetchError.deadlineExceeded }
        try Task.checkCancellation()
        if expectedLength > Int64(maximumBytes) { throw BoundedHTTPFetchError.tooLarge }
        let deadline = Date.now.addingTimeInterval(maximumDuration)
        var data = Data()
        if expectedLength > 0 { data.reserveCapacity(Int(min(expectedLength, Int64(maximumBytes)))) }
        for try await byte in bytes {
            if data.count >= maximumBytes { throw BoundedHTTPFetchError.tooLarge }
            data.append(byte)
            // Clock and cancellation are checked once per KiB rather than per byte; URLSession's own
            // timeout still bounds a stalled transfer between checks.
            if data.count & 0x3FF == 0 {
                try Task.checkCancellation()
                if Date.now > deadline { throw BoundedHTTPFetchError.deadlineExceeded }
            }
        }
        return data
    }
}
