import Foundation
import Testing
@testable import MyDock

private final class IsolationWeatherProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data(#"{"results":[{"id":1,"name":"Fixture City","latitude":1,"longitude":2,"timezone":"UTC"}]}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json", "Content-Length": String(data.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct ReliabilityIsolationTests {
    @Test func productionDefaultsFailClosedBeforeAnyTransportOrDNS() async throws {
        // Running this case outside the isolated test harness must never make an external request.
        try #require(AppRuntimeEnvironment.isIsolated)
        #expect(!AppRuntimeEnvironment.allowsNetwork)
        #expect(AppRuntimeEnvironment.allowsProductionNetwork(validationRoot: nil))
        #expect(!AppRuntimeEnvironment.allowsProductionNetwork(validationRoot: URL(fileURLWithPath: "/synthetic")))
        #expect(throws: ValidationBoundaryError.self) { try AppRuntimeEnvironment.requireNetwork() }
        let request = URLRequest(url: URL(string: "https://fixture.invalid/unused")!)
        await #expect(throws: ValidationBoundaryError.self) { _ = try await URLSessionMarketDataTransport().data(for: request) }
        await #expect(throws: ValidationBoundaryError.self) { _ = try await URLSessionStripeDataTransport().response(for: request) }
        await #expect(throws: ValidationBoundaryError.self) { _ = try await URLSessionPaddleDataTransport().response(for: request) }
        await #expect(throws: ValidationBoundaryError.self) { _ = try await URLSessionShopifyDataTransport().response(for: request) }
        await #expect(throws: ValidationBoundaryError.self) { _ = try await OpenMeteoWeatherProvider().searchLocations("Fixture City") }
        await #expect(throws: ValidationBoundaryError.self) {
            _ = try await GitHubCopilotBillingClient.read(credentials: .init(username: "fixture", token: "synthetic"), monthlyAllowance: 100)
        }
        #expect(await SiteFaviconFetcher.fetchIconData(for: URL(string: "https://public-looking.invalid")!) == nil)
        #expect(await NowPlayingArtwork.fetchSpotifyArtwork(at: URL(string: "https://i.scdn.co/image/fixture")!) == nil)
    }

    @Test func explicitFakeSessionAndArtworkTransportWorkInsideIsolation() async throws {
        try #require(AppRuntimeEnvironment.isIsolated)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IsolationWeatherProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let locations = try await OpenMeteoWeatherProvider(session: session).searchLocations("Fixture")
        #expect(locations.count == 1 && locations[0].name == "Fixture City")
        let url = URL(string: "https://i.scdn.co/image/fixture")!
        let bytes = Data([1, 2, 3])
        let returned = await NowPlayingArtwork.fetchSpotifyArtwork(at: url) { request in
            #expect(request.url == url)
            return (bytes, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!)
        }
        #expect(returned == bytes)
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1kAAAAASUVORK5CYII="))
        let destination = URL(string: "https://fixture.example.org/path")!
        let favicon = await SiteFaviconFetcher.fetchIconData(for: destination) { request in
            #expect(request.url?.path == "/favicon.ico")
            return (png, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!)
        }
        #expect(favicon != nil)
        let oversized = await NowPlayingArtwork.fetchSpotifyArtwork(at: url) { _ in
            (Data(repeating: 0, count: 2 * 1_024 * 1_024 + 1),
             HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!)
        }
        #expect(oversized == nil)
    }

    @Test func canceledSmallStreamAndInvalidBoundsAreRejectedBeforeConsumption() async {
        let stream = AsyncStream<UInt8> { continuation in continuation.yield(1); continuation.finish() }
        await #expect(throws: BoundedHTTPFetchError.invalidLimit) {
            _ = try await BoundedHTTPFetch.collect(stream, maximumBytes: 0)
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await BoundedHTTPFetch.collect(stream, maximumBytes: 10)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test @MainActor func defaultCoordinatorFailsClosedAndInjectedLoaderPublishes() async throws {
        try #require(AppRuntimeEnvironment.isIsolated)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-Isolation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let item = DockItem.widget("AI Limits")
        let id = try store.createProfile(.init(name: "Fixture", kind: .custom, items: [item]))
        let coordinator = WidgetDataCoordinator(store: store)
        await coordinator.refresh(item: item, profileID: id)
        #expect(!coordinator.errors.isEmpty && store.runtimeCache.readings(for: item.id)?.aiLimits == nil)
        let injected = WidgetDataCoordinator(store: store) { query, _ in
            .limits(.init(fetchedAt: .now, readings: [], sourceScope: query.aiSourceScope))
        }
        await injected.refresh(item: item, profileID: id)
        #expect(store.runtimeCache.readings(for: item.id)?.aiLimits != nil)
        #expect(store.state.profiles[0].items[0].widgetConfiguration?.aiLimitsSnapshot == nil)
    }
}
