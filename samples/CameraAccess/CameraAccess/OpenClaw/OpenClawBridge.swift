import Foundation

@MainActor
class OpenClawBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle

  private let session: URLSession
  private var sessionKey: String

  init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 60
    self.session = URLSession(configuration: config)
    self.sessionKey = OpenClawBridge.newSessionKey()
  }

  func resetSession() {
    sessionKey = OpenClawBridge.newSessionKey()
  }

  // cryptographically random session key instead of predictable timestamp
  private static func newSessionKey() -> String {
    return "agent:main:glass:\(UUID().uuidString)"
  }

  // MARK: - Agent Chat (session continuity via x-openclaw-session-key header)

  func delegateTask(
    task: String,
    toolName: String = "execute"
  ) async -> ToolResult {
    lastToolCallStatus = .executing(toolName)

    guard GeminiConfig.isOpenClawConfigured else {
      lastToolCallStatus = .failed(toolName, "OpenClaw not configured")
      return .failure("OpenClaw gateway not configured")
    }

    let hostString = "\(GeminiConfig.openClawHost):\(GeminiConfig.openClawPort)/v1/chat/completions"

    // validate url scheme is http or https only
    guard let url = URL(string: hostString),
          let scheme = url.scheme,
          ["http", "https"].contains(scheme.lowercased()) else {
      lastToolCallStatus = .failed(toolName, "Invalid URL")
      return .failure("Invalid gateway URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(GeminiConfig.openClawGatewayToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(sessionKey, forHTTPHeaderField: "x-openclaw-session-key")

    let body: [String: Any] = [
      "model": "openclaw",
      "messages": [
        ["role": "user", "content": task]
      ],
      "stream": false
    ]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await session.data(for: request)
      let httpResponse = response as? HTTPURLResponse

      guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
        let code = httpResponse?.statusCode ?? 0
        lastToolCallStatus = .failed(toolName, "HTTP \(code)")
        return .failure("Agent returned HTTP \(code)")
      }

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let choices = json["choices"] as? [[String: Any]],
         let first = choices.first,
         let message = first["message"] as? [String: Any],
         let content = message["content"] as? String {
        lastToolCallStatus = .completed(toolName)
        return .success(content)
      }

      let raw = String(data: data, encoding: .utf8) ?? "OK"
      lastToolCallStatus = .completed(toolName)
      return .success(raw)
    } catch {
      lastToolCallStatus = .failed(toolName, "Connection error")
      return .failure("Agent connection error")
    }
  }
}
