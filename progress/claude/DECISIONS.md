# Claude — Decisions

## Key Decisions

1. **Use OpenCode serve instead of custom Go daemon**
   - OpenCode has built-in headless HTTP server via `opencode serve`
   - Flutter connects to OpenCode HTTP API (port 4096)
   - Eliminates need for custom Go backend

2. **OpenCode API over WebSocket**
   - Using HTTP REST API + SSE for events (simpler than WS)
   - Session-based conversations with message streaming
   - Uses `X-Opencode-Directory` header for project scoping

3. **Architecture pivot**
   - Original: Custom Go daemon with WebSocket
   - Final: OpenCode serve + Flutter HTTP client
   - Go backend kept but optional
