import Foundation
import Security

enum GeminiConfig {
  static let websocketBaseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
  static let model = "models/gemini-2.5-flash-native-audio-preview-12-2025"

  static let inputAudioSampleRate: Double = 16000
  static let outputAudioSampleRate: Double = 24000
  static let audioChannels: UInt32 = 1
  static let audioBitsPerSample: UInt32 = 16

  static let videoFrameInterval: TimeInterval = 1.0
  static let videoJPEGQuality: CGFloat = 0.5

  // max payload size for video frames (2MB) and audio chunks (64KB)
  static let maxVideoPayloadBytes = 2 * 1024 * 1024
  static let maxAudioPayloadBytes = 64 * 1024

  static let systemInstruction = """
    You are an AI assistant for someone wearing Meta Ray-Ban smart glasses. You can see through their camera and have a voice conversation. Keep responses concise and natural.

    CRITICAL: You have NO memory, NO storage, and NO ability to take actions on your own. You cannot remember things, keep lists, set reminders, search the web, send messages, or do anything persistent. You are ONLY a voice interface.

    You have exactly ONE tool: execute. This connects you to a powerful personal assistant that can do anything -- send messages, search the web, manage lists, set reminders, create notes, research topics, control smart home devices, interact with apps, and much more.

    ALWAYS use execute when the user asks you to:
    - Send a message to someone (any platform: WhatsApp, Telegram, iMessage, Slack, etc.)
    - Search or look up anything (web, local info, facts, news)
    - Add, create, or modify anything (shopping lists, reminders, notes, todos, events)
    - Research, analyze, or draft anything
    - Control or interact with apps, devices, or services
    - Remember or store any information for later

    Be detailed in your task description. Include all relevant context: names, content, platforms, quantities, etc. The assistant works better with complete information.

    NEVER pretend to do these things yourself.

    IMPORTANT: Before calling execute, ALWAYS speak a brief acknowledgment first. For example:
    - "Sure, let me add that to your shopping list." then call execute.
    - "Got it, searching for that now." then call execute.
    - "On it, sending that message." then call execute.
    Never call execute silently -- the user needs verbal confirmation that you heard them and are working on it. The tool may take several seconds to complete, so the acknowledgment lets them know something is happening.

    For messages, confirm recipient and content before delegating unless clearly urgent.
    """

  // MARK: - Keychain-based credential storage

  // Keys used to store/retrieve secrets from the iOS Keychain.
  // On first launch, the app should prompt the user to enter these values,
  // which are then stored securely. See KeychainHelper below.
  private static let keychainServicePrefix = "com.visionclaw"

  static var apiKey: String {
    KeychainHelper.read(service: "\(keychainServicePrefix).gemini", account: "apiKey") ?? ""
  }

  static var openClawHost: String {
    KeychainHelper.read(service: "\(keychainServicePrefix).openclaw", account: "host") ?? ""
  }

  static let openClawPort = 18789

  static var openClawHookToken: String {
    KeychainHelper.read(service: "\(keychainServicePrefix).openclaw", account: "hookToken") ?? ""
  }

  static var openClawGatewayToken: String {
    KeychainHelper.read(service: "\(keychainServicePrefix).openclaw", account: "gatewayToken") ?? ""
  }

  // MARK: - Save credentials (call from a setup UI)

  static func saveGeminiApiKey(_ key: String) {
    KeychainHelper.save(service: "\(keychainServicePrefix).gemini", account: "apiKey", value: key)
  }

  static func saveOpenClawCredentials(host: String, gatewayToken: String, hookToken: String) {
    KeychainHelper.save(service: "\(keychainServicePrefix).openclaw", account: "host", value: host)
    KeychainHelper.save(service: "\(keychainServicePrefix).openclaw", account: "gatewayToken", value: gatewayToken)
    KeychainHelper.save(service: "\(keychainServicePrefix).openclaw", account: "hookToken", value: hookToken)
  }

  // MARK: - URL builders

  static func websocketURL() -> URL? {
    guard isConfigured else { return nil }
    return URL(string: "\(websocketBaseURL)?key=\(apiKey)")
  }

  static var isConfigured: Bool {
    return !apiKey.isEmpty
  }

  static var isOpenClawConfigured: Bool {
    return !openClawGatewayToken.isEmpty && !openClawHost.isEmpty
  }
}

// MARK: - Keychain Helper

enum KeychainHelper {
  static func save(service: String, account: String, value: String) {
    guard let data = value.data(using: .utf8) else { return }

    // delete existing item first
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    SecItemAdd(addQuery as CFDictionary, nil)
  }

  static func read(service: String, account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete(service: String, account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
  }
}
