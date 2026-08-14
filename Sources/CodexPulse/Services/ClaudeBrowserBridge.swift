import CryptoKit
import Foundation
import Network

struct ClaudeBrowserBridgeEnvelope: Decodable, Sendable {
    struct Window: Decodable, Sendable {
        let id: String
        let scope: String
        let title: String?
        let utilization: Double
        let resetsAt: String?
    }

    struct Plan: Decodable, Sendable {
        let rateLimitTier: String?
        let billingType: String?
        let seatTier: String?
    }

    let schemaVersion: Int
    let capturedAt: String?
    let windows: [Window]
    let plan: Plan?
}

enum ClaudeBrowserBridgeParser {
    enum ParseError: LocalizedError {
        case unsupportedSchema
        case noQuotaWindows

        var errorDescription: String? {
            switch self {
            case .unsupportedSchema: "Pulse Connector sent an unsupported data format"
            case .noQuotaWindows: "Claude Web returned no readable quota windows"
            }
        }
    }

    static func parse(_ data: Data) throws -> ClaudeProviderData {
        let envelope = try JSONDecoder().decode(ClaudeBrowserBridgeEnvelope.self, from: data)
        guard envelope.schemaVersion == 1 else { throw ParseError.unsupportedSchema }

        let meters = envelope.windows.compactMap { item -> ClaudeQuotaMeter? in
            guard item.utilization.isFinite else { return nil }
            let scope: ClaudeQuotaScope = switch item.scope {
            case "session": .session
            case "weekly": .weekly
            default: .modelWeekly
            }
            return ClaudeQuotaMeter(
                id: item.id,
                scope: scope,
                providerTitle: item.title,
                window: QuotaWindow(
                    usedPercent: min(100, max(0, item.utilization)),
                    resetsAt: parseDate(item.resetsAt),
                    windowMinutes: scope == .session ? 300 : 10_080
                ),
                usageKnown: true
            )
        }
        guard let limiting = meters.min(by: { lhs, rhs in
            let difference = lhs.window.remainingPercent - rhs.window.remainingPercent
            if abs(difference) > 0.01 { return difference < 0 }
            if (lhs.window.resetsAt != nil) != (rhs.window.resetsAt != nil) {
                return lhs.window.resetsAt != nil
            }
            return scopePriority(lhs.scope) < scopePriority(rhs.scope)
        }) else {
            throw ParseError.noQuotaWindows
        }

        return ClaudeProviderData(
            snapshot: ProviderSnapshot(
                provider: .claude,
                state: .connected,
                quota: limiting.window,
                source: "Claude Web · Pulse Connector",
                message: nil,
                updatedAt: parseDate(envelope.capturedAt) ?? .now,
                history: []
            ),
            accountDetails: ClaudeAccountDetails(
                quotaMeters: meters,
                planName: planName(envelope.plan),
                creditBalance: nil
            )
        )
    }

    private static func scopePriority(_ scope: ClaudeQuotaScope) -> Int {
        switch scope {
        case .weekly: 0
        case .modelWeekly: 1
        case .session: 2
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func planName(_ plan: ClaudeBrowserBridgeEnvelope.Plan?) -> String? {
        guard let plan else { return nil }
        let values = [plan.rateLimitTier, plan.billingType, plan.seatTier]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if values.contains("max") {
            if values.contains("20") { return "Claude Max 20x" }
            if values.contains("5") { return "Claude Max 5x" }
            return "Claude Max"
        }
        if values.contains("enterprise") { return "Claude Enterprise" }
        if values.contains("team") { return "Claude Team" }
        if values.contains("pro") { return "Claude Pro" }
        return nil
    }
}

final class ClaudeBrowserBridge: @unchecked Sendable {
    static let shared = ClaudeBrowserBridge()
    static let port: UInt16 = 37_421
    static let maximumRequestBytes = 128 * 1024

    private let queue = DispatchQueue(label: "ai.sharafutdinov.codexpulse.claude-bridge")
    private let lock = NSLock()
    private var listener: NWListener?
    private var pairingCode: String?
    private var pairingExpiresAt: Date?
    private var failedPairingAttempts = 0
    private var pairingBlockedUntil: Date?
    private var usageHandler: (@Sendable (ClaudeProviderData) -> Void)?
    private var storedLatestData: ClaudeProviderData?
    private let tokenHashKey = "providers.claude.extensionTokenHash"
    private let latestUsageKey = "providers.claude.extensionLatestUsage"

    private init() {
        guard let cached = UserDefaults.standard.data(forKey: latestUsageKey),
              let parsed = try? ClaudeBrowserBridgeParser.parse(cached),
              Date.now.timeIntervalSince(parsed.snapshot.updatedAt) < 24 * 60 * 60
        else {
            UserDefaults.standard.removeObject(forKey: latestUsageKey)
            return
        }
        storedLatestData = parsed
    }

    var latestData: ClaudeProviderData? {
        lock.withLock { storedLatestData }
    }

    var isPaired: Bool {
        UserDefaults.standard.string(forKey: tokenHashKey) != nil
    }

    func start(onUsage: @escaping @Sendable (ClaudeProviderData) -> Void) {
        lock.withLock { usageHandler = onUsage }
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            // Settings exposes the missing-bridge state; no provider credentials are involved.
        }
    }

    func beginPairing() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var generator = SystemRandomNumberGenerator()
        let code = String((0..<8).compactMap { _ in alphabet.randomElement(using: &generator) })
        lock.withLock {
            pairingCode = code
            pairingExpiresAt = Date().addingTimeInterval(10 * 60)
            failedPairingAttempts = 0
            pairingBlockedUntil = nil
        }
        return code
    }

    func revoke() {
        UserDefaults.standard.removeObject(forKey: tokenHashKey)
        UserDefaults.standard.removeObject(forKey: latestUsageKey)
        lock.withLock {
            pairingCode = nil
            pairingExpiresAt = nil
            failedPairingAttempts = 0
            pairingBlockedUntil = nil
            storedLatestData = nil
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        let buffer = HTTPBuffer()
        receive(on: connection, buffer: buffer)
    }

    private func receive(on connection: NWConnection, buffer: HTTPBuffer) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { buffer.data.append(data) }
            if let request = BridgeHTTPRequest(data: buffer.data) {
                self.route(request, on: connection)
            } else if error == nil, !complete, buffer.data.count < Self.maximumRequestBytes {
                self.receive(on: connection, buffer: buffer)
            } else {
                self.respond(status: 400, json: ["error": "invalid_request"], on: connection)
            }
        }
    }

    private func route(_ request: BridgeHTTPRequest, on connection: NWConnection) {
        if request.method == "GET", request.path == "/v1/health" {
            respond(status: 200, json: ["paired": isPaired], on: connection)
            return
        }
        if request.method == "POST", request.path == "/v1/pair" {
            pair(request, on: connection)
            return
        }
        if request.method == "POST", request.path == "/v1/claude/usage" {
            receiveUsage(request, on: connection)
            return
        }
        respond(status: 404, json: ["error": "not_found"], on: connection)
    }

    private func pair(_ request: BridgeHTTPRequest, on connection: NWConnection) {
        let supplied = request.headers["x-codex-pulse-code"]?.uppercased()
        let result = lock.withLock { () -> PairingResult in
            if (pairingBlockedUntil ?? .distantPast) > .now { return .blocked }
            guard supplied != nil,
                  supplied == pairingCode,
                  (pairingExpiresAt ?? .distantPast) > .now
            else {
                failedPairingAttempts += 1
                if failedPairingAttempts >= 8 {
                    pairingBlockedUntil = Date().addingTimeInterval(60)
                    failedPairingAttempts = 0
                    return .blocked
                }
                return .invalid
            }
            failedPairingAttempts = 0
            pairingBlockedUntil = nil
            return .valid
        }
        guard result == .valid else {
            if result == .blocked {
                respond(status: 429, json: ["error": "pairing_temporarily_blocked"], on: connection)
                return
            }
            respond(status: 401, json: ["error": "invalid_pairing_code"], on: connection)
            return
        }
        let token = randomToken()
        UserDefaults.standard.set(hash(token), forKey: tokenHashKey)
        lock.withLock {
            pairingCode = nil
            pairingExpiresAt = nil
        }
        respond(status: 200, json: ["token": token], on: connection)
    }

    private func receiveUsage(_ request: BridgeHTTPRequest, on connection: NWConnection) {
        guard let authorization = request.headers["authorization"],
              authorization.hasPrefix("Bearer "),
              let expected = UserDefaults.standard.string(forKey: tokenHashKey),
              hash(String(authorization.dropFirst("Bearer ".count))) == expected
        else {
            respond(status: 401, json: ["error": "not_paired"], on: connection)
            return
        }
        do {
            let data = try ClaudeBrowserBridgeParser.parse(request.body)
            UserDefaults.standard.set(request.body, forKey: latestUsageKey)
            let handler = lock.withLock { () -> (@Sendable (ClaudeProviderData) -> Void)? in
                storedLatestData = data
                return usageHandler
            }
            handler?(data)
            respond(status: 200, json: ["accepted": true], on: connection)
        } catch {
            respond(status: 422, json: ["error": "invalid_usage_payload"], on: connection)
        }
    }

    private func respond(status: Int, json: [String: Any], on connection: NWConnection) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        respond(status: status, data: data, on: connection)
    }

    private func respond(status: Int, data: Data, on connection: NWConnection) {
        let reason = switch status {
        case 200: "OK"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 429: "Too Many Requests"
        case 404: "Not Found"
        case 422: "Unprocessable Content"
        default: "Error"
        }
        let headers = "HTTP/1.1 \(status) \(reason)\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(data.count)\r\n" +
            "Cache-Control: no-store\r\n" +
            "X-Content-Type-Options: nosniff\r\n" +
            "Connection: close\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private enum PairingResult {
    case valid
    case invalid
    case blocked
}

private final class HTTPBuffer: @unchecked Sendable {
    var data = Data()
}

struct BridgeHTTPRequest {
    static let maximumHeaderBytes = 16 * 1024
    static let maximumBodyBytes = 96 * 1024

    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(data: Data) {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter),
              headerRange.lowerBound <= Self.maximumHeaderBytes,
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        guard let contentLength = Int(headers["content-length"] ?? "0"),
              contentLength >= 0,
              contentLength <= Self.maximumBodyBytes
        else { return nil }
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        self.method = String(parts[0])
        self.path = String(parts[1]).components(separatedBy: "?").first ?? String(parts[1])
        self.headers = headers
        self.body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
    }
}

private extension NSLock {
    func withLock<T>(_ work: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try work()
    }
}
