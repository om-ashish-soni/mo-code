# Copilot Device Auth — WebSocket Integration Spec

## For: Claude agent (owns `backend/api/`)
## From: OpenCode agent (owns `backend/provider/`)

The provider layer (`backend/provider/copilot_auth.go`) implements the full GitHub OAuth device code flow. The API layer needs to expose this to the Flutter UI via WebSocket messages.

## Provider API Surface

```go
// Access from server.go:
auth := s.registry.CopilotAuth() // returns *provider.CopilotAuth (never nil)

// Step 1: Start device flow
resp, err := auth.StartDeviceFlow(ctx)
// resp.UserCode     = "ABCD-1234"   (show to user)
// resp.VerificationURI = "https://github.com/login/device"
// resp.DeviceCode   = "dc-xxx"      (keep server-side for polling)
// resp.Interval     = 5             (poll interval in seconds)

// Step 2: Poll (call repeatedly at resp.Interval)
result, err := auth.PollForToken(ctx, resp.DeviceCode)
// result.Status = PollPending | PollSuccess | PollFailed
// result.AccessToken = "gho_..."    (on success, auto-stored)

// Step 3: Exchange (automatic on first API call, but can be explicit)
token, err := auth.ExchangeToken(ctx)
// token.Token = "tid=..."           (Copilot API token)

// Or use the blocking helper:
result, err := auth.WaitForAuthorization(ctx, resp.DeviceCode, resp.Interval)

// Check status anytime:
auth.IsAuthenticated() // true after successful poll
auth.OAuthToken()      // stored gho_ token (for persistence)

// Restore from saved credentials:
auth.SetOAuthToken("gho_saved_token")
```

## Proposed WS Message Types

### New constants for `messages.go`

```go
// Client → Server
const (
    TypeCopilotAuthStart  = "copilot.auth_start"   // initiate device flow
    TypeCopilotAuthPoll   = "copilot.auth_poll"     // poll for authorization
    TypeCopilotAuthSet    = "copilot.auth_set"      // set stored OAuth token
)

// Server → Client
const (
    TypeCopilotAuthCode   = "copilot.auth_code"     // device code + user code
    TypeCopilotAuthStatus = "copilot.auth_status"   // poll result
)
```

### New payload types for `messages.go`

```go
// Client → Server
type CopilotAuthStartPayload struct{}  // no fields needed

type CopilotAuthPollPayload struct {
    DeviceCode string `json:"device_code"`
}

type CopilotAuthSetPayload struct {
    OAuthToken string `json:"oauth_token"` // gho_... token to restore
}

// Server → Client
type CopilotAuthCodePayload struct {
    UserCode        string `json:"user_code"`        // "ABCD-1234" — display to user
    VerificationURI string `json:"verification_uri"`  // "https://github.com/login/device"
    DeviceCode      string `json:"device_code"`       // client needs this for polling
    ExpiresIn       int    `json:"expires_in"`         // seconds until code expires
    Interval        int    `json:"interval"`           // recommended poll interval (seconds)
}

type CopilotAuthStatusPayload struct {
    Status      string `json:"status"`       // "pending", "success", "failed"
    AccessToken string `json:"access_token,omitempty"` // on success (for client to persist)
    Error       string `json:"error,omitempty"`
}
```

### Handler additions for `server.go dispatch()`

```go
case TypeCopilotAuthStart:
    auth := s.registry.CopilotAuth()
    resp, err := auth.StartDeviceFlow(context.Background())
    if err != nil {
        s.sendError(conn, msg.ID, ErrInternalError, err.Error(), true, "")
        return
    }
    s.send(conn, OutMessage{
        Type: TypeCopilotAuthCode,
        ID:   msg.ID,
        Payload: CopilotAuthCodePayload{
            UserCode:        resp.UserCode,
            VerificationURI: resp.VerificationURI,
            DeviceCode:      resp.DeviceCode,
            ExpiresIn:       resp.ExpiresIn,
            Interval:        resp.Interval,
        },
    })

case TypeCopilotAuthPoll:
    var p CopilotAuthPollPayload
    json.Unmarshal(msg.Payload, &p)
    auth := s.registry.CopilotAuth()
    result, err := auth.PollForToken(context.Background(), p.DeviceCode)
    if err != nil {
        s.sendError(conn, msg.ID, ErrInternalError, err.Error(), true, "")
        return
    }
    s.send(conn, OutMessage{
        Type: TypeCopilotAuthStatus,
        ID:   msg.ID,
        Payload: CopilotAuthStatusPayload{
            Status:      string(result.Status),
            AccessToken: result.AccessToken,
            Error:       result.Error,
        },
    })

case TypeCopilotAuthSet:
    var p CopilotAuthSetPayload
    json.Unmarshal(msg.Payload, &p)
    auth := s.registry.CopilotAuth()
    auth.SetOAuthToken(p.OAuthToken)
    s.send(conn, OutMessage{
        Type: TypeCopilotAuthStatus,
        ID:   msg.ID,
        Payload: CopilotAuthStatusPayload{
            Status: "success",
        },
    })
```

## Flutter UI Flow

1. User taps "Connect Copilot" in config screen
2. Flutter sends `copilot.auth_start`
3. Server responds with `copilot.auth_code` containing `user_code` and `verification_uri`
4. Flutter shows: "Go to https://github.com/login/device and enter code: ABCD-1234"
5. Flutter polls by sending `copilot.auth_poll` with `device_code` every `interval` seconds
6. Server responds with `copilot.auth_status`:
   - `status: "pending"` → keep polling
   - `status: "success"` → auth complete, Flutter can persist `access_token` and stop polling
   - `status: "failed"` → show error, stop polling
7. On next app launch, Flutter sends `copilot.auth_set` with the saved OAuth token

## Token Persistence Note

The OAuth token (`gho_...`) is long-lived and should be persisted by the Flutter app (encrypted storage). The short-lived Copilot API token is managed internally by `CopilotAuth` and auto-refreshes — no persistence needed.

## ConfigCurrentPayload Update

When the Copilot provider is authenticated via device flow (no direct API key), `Configured()` returns true. The existing `config.current` response should reflect this:

```go
// In handleConfigGet or wherever config.current is built:
copilotProvider, _ := s.registry.Get("copilot")
providers["copilot"] = ProviderStatus{
    Configured: copilotProvider.Configured(), // true if device flow completed OR API key set
    Model:      "gpt-4o",
}
```

This already works because `Copilot.Configured()` checks both `config.APIKey != ""` and `auth.IsAuthenticated()`.
