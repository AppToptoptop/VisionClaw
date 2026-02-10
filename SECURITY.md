# Security Fixes for VisionClaw

This fork addresses critical security vulnerabilities found in the original VisionClaw project. These changes are essential before using the app with real API keys and Meta Ray-Ban glasses.

## Changes Summary

### CRITICAL — Fixed

#### 1. Keychain-based credential storage (`GeminiConfig.swift`)
- **Before**: API keys and tokens were hardcoded as string constants, recoverable from the compiled binary via reverse engineering
- **After**: All secrets (Gemini API key, OpenClaw tokens, host) are stored in the iOS Keychain using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Added `KeychainHelper` utility enum with save/read/delete operations
- Added `saveGeminiApiKey()` and `saveOpenClawCredentials()` methods for setup UI integration

#### 2. Cryptographically random session IDs (`OpenClawBridge.swift`)
- **Before**: Session key used a predictable ISO8601 timestamp: `"agent:main:glass:\(ts)"`
- **After**: Session key uses `UUID().uuidString` for cryptographic randomness

#### 3. Sensitive data removed from logs (all files)
- **Before**: `NSLog` calls exposed API responses, tool call arguments, error details, and user transcriptions
- **After**: All sensitive data removed from log statements. Only latency metrics and rejected tool names are logged.

### HIGH — Fixed

#### 4. WSS protocol enforcement (`GeminiLiveService.swift`)
- **Before**: WebSocket URL scheme was not validated
- **After**: Connection is rejected if the URL scheme is not `wss://`

#### 5. Tool call whitelist (`ToolCallRouter.swift`)
- **Before**: Any tool name from Gemini was routed to OpenClaw without validation
- **After**: Only tool names declared in `ToolDeclarations.allDeclarations()` are accepted. Unknown tools are rejected with an error response.
- Task descriptions are capped at 4096 characters to limit abuse

#### 6. Payload size limits (`GeminiLiveService.swift` + `GeminiConfig.swift`)
- **Before**: No size validation on audio or video payloads sent to Gemini
- **After**: Audio capped at 64KB, video frames capped at 2MB per payload

### MEDIUM — Fixed

#### 7. Audio buffer cap (`AudioManager.swift`)
- **Before**: `accumulatedData` could grow without bound if sending failed
- **After**: Buffer capped at 64KB (~2 seconds). Excess data is dropped from the front.

#### 8. URL scheme validation (`OpenClawBridge.swift`)
- Added validation that OpenClaw gateway URL uses `http://` or `https://` scheme only

#### 9. Reduced timeout (`OpenClawBridge.swift`)
- Request timeout reduced from 120s to 60s

## Setup Instructions

Since credentials are no longer hardcoded, you need to call the save methods on first launch:

```swift
// In your setup/onboarding UI:
GeminiConfig.saveGeminiApiKey("your-actual-api-key")
GeminiConfig.saveOpenClawCredentials(
    host: "http://your-mac.local",
    gatewayToken: "your-gateway-token",
    hookToken: "your-hook-token"
)
```

## Remaining Recommendations

These items were not addressed in this fork but are recommended for production use:

1. **Certificate pinning**: Add `URLSessionDelegate` SSL pinning for both Gemini WebSocket and OpenClaw HTTP connections
2. **WebSocket proxy**: Route Gemini API calls through a server-side proxy to avoid exposing the API key in the client app entirely (see original repo issue #1)
3. **Rate limiting**: Add client-side rate limiting for `sendAudio()` and `sendVideoFrame()` calls
4. **Codable models**: Replace `[String: Any]` dictionaries with strongly-typed `Codable` structs for safer JSON parsing
