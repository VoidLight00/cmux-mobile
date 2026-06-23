import Foundation

/// Server-Sent Events client that connects to the bridge `/events` endpoint.
/// Supports automatic reconnection with `Last-Event-ID`, heartbeat timeout
/// detection, and fallback to polling when SSE fails repeatedly.
final class SSEClient {

    // MARK: - Types

    struct SSEEvent {
        let id: String?
        let event: String?
        let data: String
    }

    enum SSEState {
        case disconnected
        case connecting
        case connected
        case polling
    }

    // MARK: - Configuration

    private let heartbeatTimeout: TimeInterval = 15.0
    private let maxSSEFailures = 3
    private let sseFailureWindow: TimeInterval = 30.0
    private let pollingInterval: TimeInterval = 2.0

    // MARK: - Callbacks

    var onEvent: ((SSEEvent) -> Void)?
    var onStateChange: ((SSEState) -> Void)?

    // MARK: - Properties

    private(set) var state: SSEState = .disconnected {
        didSet {
            if oldValue != state {
                onStateChange?(state)
            }
        }
    }

    private var baseURL: URL?
    private var token: String?
    private var lastEventId: String?

    private var urlSession: URLSession?
    private var dataTask: URLSessionDataTask?
    private var heartbeatTimer: Timer?
    private var pollingTimer: Timer?

    // Failure tracking for SSE -> polling fallback
    private var sseFailures: [Date] = []

    // Connection generation: bumped on every (re)start and teardown. Delegate
    // callbacks carry the generation they were created with and are ignored if
    // stale — so cancelling a task (intentional stop, or a reconnect replacing
    // an old stream) never triggers a phantom reconnect or leaks old data.
    private var generation = 0

    // Buffer for parsing SSE lines
    private var lineBuffer = ""
    private var currentEventType: String?
    private var currentEventData: [String] = []
    private var currentEventId: String?

    // Delegate for streaming
    private var sessionDelegate: SSESessionDelegate?

    // MARK: - Lifecycle

    func connect(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
        startSSE()
    }

    func disconnect() {
        stopSSE()
        stopPolling()
        state = .disconnected
    }

    // MARK: - SSE Connection

    private func startSSE() {
        stopSSE()
        state = .connecting

        guard let baseURL, let token else { return }

        generation += 1
        let myGeneration = generation

        let eventsURL = baseURL.appendingPathComponent("events")
        var request = URLRequest(url: eventsURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 0 // No timeout for SSE

        if let lastEventId {
            request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID")
        }

        let delegate = SSESessionDelegate(client: self, generation: myGeneration)
        self.sessionDelegate = delegate

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 0
        config.timeoutIntervalForResource = 0

        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.urlSession = session

        let task = session.dataTask(with: request)
        self.dataTask = task
        task.resume()

        resetHeartbeatTimer()
    }

    private func stopSSE() {
        // Invalidate any in-flight callbacks: the task we're about to cancel will
        // fire didCompleteWithError(cancelled) under the OLD generation, which the
        // client handlers will ignore — no phantom reconnect.
        generation += 1
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        dataTask?.cancel()
        dataTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        sessionDelegate = nil
        lineBuffer = ""
        currentEventType = nil
        currentEventData = []
        currentEventId = nil
    }

    // MARK: - Heartbeat

    private func resetHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: heartbeatTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.handleHeartbeatTimeout()
        }
    }

    private func handleHeartbeatTimeout() {
        // No data received within the heartbeat window -- reconnect
        recordSSEFailure()
        reconnectOrFallback()
    }

    // MARK: - Failure tracking & fallback

    private func recordSSEFailure() {
        let now = Date()
        sseFailures.append(now)
        // Prune old failures outside the window
        sseFailures = sseFailures.filter { now.timeIntervalSince($0) < sseFailureWindow }
    }

    private func shouldFallbackToPolling() -> Bool {
        let now = Date()
        let recentFailures = sseFailures.filter { now.timeIntervalSince($0) < sseFailureWindow }
        return recentFailures.count >= maxSSEFailures
    }

    private func reconnectOrFallback() {
        stopSSE()   // bumps generation

        if shouldFallbackToPolling() {
            startPolling()
        } else {
            // Reconnect SSE after a brief delay — but only if we weren't
            // intentionally stopped (disconnect) or superseded in the meantime.
            let gen = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.generation == gen, self.baseURL != nil else { return }
                self.startSSE()
            }
        }
    }

    // MARK: - Polling fallback

    private func startPolling() {
        stopPolling()
        state = .polling

        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: pollingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.poll()
        }
        // Immediate first poll
        poll()
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    /// Re-attempt the real SSE stream while degraded to polling. Clears the
    /// 3-in-30s failure budget so a transient blip can recover; a fresh failure
    /// records again and falls back to polling. Called periodically by RelayService.
    func retrySSE() {
        guard state == .polling else { return }   // don't disturb a healthy/connecting stream
        sseFailures.removeAll()
        stopPolling()
        startSSE()
    }

    private func poll() {
        guard let baseURL, let token else { return }
        let gen = generation

        let statusURL = baseURL.appendingPathComponent("status")
        var request = URLRequest(url: statusURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard error == nil, let data else { return }
            guard (try? JSONSerialization.jsonObject(with: data)) != nil else { return }
            let event = SSEEvent(id: nil, event: "poll-status", data: String(data: data, encoding: .utf8) ?? "{}")
            DispatchQueue.main.async {
                // Drop a poll response from a superseded connection (e.g. SSE
                // recovered or the client was torn down meanwhile).
                guard let self, gen == self.generation else { return }
                self.onEvent?(event)
            }
        }
        task.resume()
    }

    // MARK: - SSE Parsing

    // NOTE: all the handle*/start*/stop*/parse state below runs ONLY on the main
    // queue — the delegate marshals every callback through DispatchQueue.main
    // (and the serial delegate queue preserves order), and connect/disconnect/
    // retry are called from the main actor. So `generation`, the timers, and the
    // parser buffers are single-threaded — no cross-queue races, and a stale
    // generation is rejected at the point the event is actually consumed.
    fileprivate func handleSSEConnected(generation: Int) {
        guard generation == self.generation else { return }
        state = .connected
    }

    fileprivate func handleReceivedData(_ data: Data, generation: Int) {
        guard generation == self.generation else { return }   // stale stream
        resetHeartbeatTimer()

        guard let text = String(data: data, encoding: .utf8) else { return }
        lineBuffer += text

        // Process complete lines
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])
            processSSELine(line)
        }
    }

    private func processSSELine(_ line: String) {
        // Empty line = end of event
        if line.isEmpty {
            dispatchCurrentEvent()
            return
        }

        // Comment (heartbeat)
        if line.hasPrefix(":") {
            return
        }

        // Parse field:value
        if line.hasPrefix("id:") {
            let value = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            currentEventId = value
        } else if line.hasPrefix("event:") {
            let value = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            currentEventType = value
        } else if line.hasPrefix("data:") {
            let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            currentEventData.append(value)
        } else if line.hasPrefix("retry:") {
            // Could adjust reconnection interval; ignored for now
        }
    }

    private func dispatchCurrentEvent() {
        guard !currentEventData.isEmpty else {
            // Reset but no event to dispatch
            currentEventType = nil
            currentEventId = nil
            return
        }

        let data = currentEventData.joined(separator: "\n")
        let event = SSEEvent(
            id: currentEventId,
            event: currentEventType,
            data: data
        )

        if let id = currentEventId {
            lastEventId = id
        }

        // Reset
        currentEventType = nil
        currentEventData = []
        currentEventId = nil

        onEvent?(event)   // already on main (see handleReceivedData note)
    }

    fileprivate func handleSSEError(_ error: Error?, generation: Int) {
        // Ignore callbacks from a superseded/cancelled stream (intentional stop
        // or a reconnect that already replaced this task) — no phantom reconnect.
        guard generation == self.generation else { return }
        recordSSEFailure()
        reconnectOrFallback()
    }

    fileprivate func handleSSEComplete(generation: Int) {
        guard generation == self.generation else { return }
        reconnectOrFallback()
    }
}

// MARK: - URLSession Delegate for streaming

private final class SSESessionDelegate: NSObject, URLSessionDataDelegate {

    private weak var client: SSEClient?
    private let generation: Int

    init(client: SSEClient, generation: Int) {
        self.client = client
        self.generation = generation
    }

    // Delegate callbacks arrive on URLSession's serial delegate queue. We marshal
    // each to the main queue (FIFO-preserving, since the source queue is serial)
    // so ALL SSEClient state is touched on main only — see the note in SSEClient.
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let ok = (response as? HTTPURLResponse)?.statusCode == 200
        let c = client, gen = generation
        DispatchQueue.main.async { ok ? c?.handleSSEConnected(generation: gen) : c?.handleSSEError(nil, generation: gen) }
        completionHandler(ok ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let c = client, gen = generation
        DispatchQueue.main.async { c?.handleReceivedData(data, generation: gen) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let c = client, gen = generation
        DispatchQueue.main.async {
            if let error { c?.handleSSEError(error, generation: gen) }
            else { c?.handleSSEComplete(generation: gen) }
        }
    }
}
