import Foundation

@MainActor
class ToolCallRouter {
  private let bridge: OpenClawBridge
  private var inFlightTasks: [String: Task<Void, Never>] = [:]

  // only tools declared in ToolDeclarations are allowed
  private static let allowedToolNames: Set<String> = Set(
    ToolDeclarations.allDeclarations().compactMap { $0["name"] as? String }
  )

  init(bridge: OpenClawBridge) {
    self.bridge = bridge
  }

  /// Route a tool call from Gemini to OpenClaw. Calls sendResponse with the
  /// JSON dictionary to send back as a toolResponse message.
  func handleToolCall(
    _ call: GeminiFunctionCall,
    sendResponse: @escaping ([String: Any]) -> Void
  ) {
    let callId = call.id
    let callName = call.name

    // reject tool calls not in the whitelist
    guard Self.allowedToolNames.contains(callName) else {
      NSLog("[ToolCall] Rejected unknown tool: %@", callName)
      let response = buildToolResponse(
        callId: callId,
        name: callName,
        result: .failure("Unknown tool: \(callName)")
      )
      sendResponse(response)
      return
    }

    let task = Task { @MainActor in
      let taskDesc = call.args["task"] as? String ?? String(describing: call.args)

      // enforce a max length on task descriptions to limit abuse
      let sanitizedTask = String(taskDesc.prefix(4096))

      let result = await bridge.delegateTask(task: sanitizedTask, toolName: callName)

      guard !Task.isCancelled else { return }

      let response = self.buildToolResponse(callId: callId, name: callName, result: result)
      sendResponse(response)

      self.inFlightTasks.removeValue(forKey: callId)
    }

    inFlightTasks[callId] = task
  }

  /// Cancel specific in-flight tool calls (from toolCallCancellation)
  func cancelToolCalls(ids: [String]) {
    for id in ids {
      if let task = inFlightTasks[id] {
        task.cancel()
        inFlightTasks.removeValue(forKey: id)
      }
    }
    bridge.lastToolCallStatus = .cancelled(ids.first ?? "unknown")
  }

  /// Cancel all in-flight tool calls (on session stop)
  func cancelAll() {
    for (_, task) in inFlightTasks {
      task.cancel()
    }
    inFlightTasks.removeAll()
  }

  // MARK: - Private

  private func buildToolResponse(
    callId: String,
    name: String,
    result: ToolResult
  ) -> [String: Any] {
    return [
      "toolResponse": [
        "functionResponses": [
          [
            "id": callId,
            "name": name,
            "response": result.responseValue
          ]
        ]
      ]
    ]
  }
}
