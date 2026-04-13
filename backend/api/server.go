package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"mo-code/backend/agent"
	agentctx "mo-code/backend/context"
	"mo-code/backend/provider"
	"mo-code/backend/runtime"

	"github.com/gorilla/websocket"
)

const (
	DefaultPort = 19280
	MaxPortScan = 50
	Version     = "0.1.0"
)

// Server is the mo-code daemon HTTP/WebSocket server.
type Server struct {
	httpServer *http.Server
	listener   net.Listener
	portFile   string
	startedAt  time.Time

	Tasks     *TaskManager
	PlanTasks *TaskManager // plan mode uses a separate runner (read-only)
	Config    *ConfigManager
	Sessions  *agentctx.SessionStore
	// Registry holds the provider registry for wiring config changes to providers.
	Registry *provider.Registry
	// Proot is the optional proot runtime (nil if not configured).
	Proot *runtime.ProotRuntime
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		if origin == "" {
			return true
		}
		parsed, err := url.Parse(origin)
		if err != nil {
			return false
		}
		host := parsed.Hostname()
		return host == "127.0.0.1" || host == "localhost" || strings.HasSuffix(host, ".localhost")
	},
}

// HealthResponse is the JSON body for GET /api/health.
type HealthResponse struct {
	Status    string `json:"status"`
	Service   string `json:"service"`
	Timestamp string `json:"timestamp"`
}

// Start creates and starts the daemon server with the given agent runner, provider registry,
// and optional session store (may be nil).
// Start creates and starts the HTTP/WebSocket server.
// planRunner is optional — if provided, plan mode (plan.start) is enabled.
func Start(portFile string, runner agent.Runner, registry *provider.Registry, sessions *agentctx.SessionStore, planRunner ...agent.Runner) (*Server, error) {
	listener, port, err := listenLocalhost(DefaultPort, MaxPortScan)
	if err != nil {
		return nil, err
	}

	s := &Server{
		listener:  listener,
		portFile:  portFile,
		startedAt: time.Now(),
		Tasks:     NewTaskManager(runner),
		Config:    NewConfigManager(registry),
		Sessions:  sessions,
		Registry:  registry,
	}
	if len(planRunner) > 0 && planRunner[0] != nil {
		s.PlanTasks = NewTaskManager(planRunner[0])
	}

	s.httpServer = &http.Server{
		Addr:              fmt.Sprintf("127.0.0.1:%d", port),
		Handler:           s.newMux(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	if err := writePortFile(portFile, port); err != nil {
		listener.Close()
		return nil, err
	}

	go func() {
		_ = s.httpServer.Serve(listener)
	}()

	return s, nil
}

// SetProot attaches the proot runtime to the server for the /api/runtime/status endpoint.
func (s *Server) SetProot(p *runtime.ProotRuntime) {
	s.Proot = p
}

// Port returns the port the server is listening on.
func (s *Server) Port() int {
	if s.listener == nil {
		return 0
	}
	if addr, ok := s.listener.Addr().(*net.TCPAddr); ok {
		return addr.Port
	}
	return 0
}

// Close shuts down the server and cleans up the port file.
func (s *Server) Close() error {
	var err error
	if s.httpServer != nil {
		err = s.httpServer.Close()
	}
	if s.portFile != "" {
		if removeErr := os.Remove(s.portFile); removeErr != nil && !errors.Is(removeErr, os.ErrNotExist) && err == nil {
			err = removeErr
		}
	}
	return err
}

func (s *Server) newMux() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/health", handleHealth)
	mux.HandleFunc("/health", handleHealth) // alias for convenience
	mux.HandleFunc("/api/config", s.Config.HandleHTTP)
	mux.HandleFunc("/api/provider/switch", s.Config.HandleProviderSwitch)
	mux.HandleFunc("/api/status", s.handleStatus)
	mux.HandleFunc("/api/auth/copilot/device", s.handleCopilotDeviceAuth)
	mux.HandleFunc("/api/auth/copilot/poll", s.handleCopilotPoll)
	mux.HandleFunc("/api/runtime/status", s.handleRuntimeStatus)
	mux.HandleFunc("/ws", s.handleWebSocket)

	// File browser endpoints (used by Flutter Files tab).
	mux.HandleFunc("/file/content", s.handleFileContent)
	mux.HandleFunc("/find/file", s.handleFindFile)
	mux.HandleFunc("/find", s.handleFind)

	// Session HTTP endpoints (used by Flutter Sessions/Tasks tabs).
	mux.HandleFunc("/session", s.handleSessionHTTP)

	return mux
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(ServerStatusPayload{
		UptimeSeconds: int64(time.Since(s.startedAt).Seconds()),
		ActiveTasks:   s.Tasks.ActiveCount(),
		QueuedTasks:   s.Tasks.QueuedCount(),
		Version:       Version,
	})
}

func (s *Server) handleRuntimeStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	type runtimeStatus struct {
		Available bool   `json:"available"`
		ProotBin  string `json:"proot_bin,omitempty"`
		RootFS    string `json:"rootfs,omitempty"`
		Projects  string `json:"projects_dir,omitempty"`
		SizeBytes int64  `json:"size_bytes,omitempty"`
	}
	resp := runtimeStatus{Available: s.Proot != nil}
	if s.Proot != nil {
		resp.ProotBin = s.Proot.ProotBin
		resp.RootFS = s.Proot.RootFS
		resp.Projects = s.Proot.ProjectsDir
		if size, err := s.Proot.RootFSSize(); err == nil {
			resp.SizeBytes = size
		}
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(HealthResponse{
		Status:    "ok",
		Service:   "mo-code-daemon",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	})
}

// ---------------------------------------------------------------------------
// WebSocket handler
// ---------------------------------------------------------------------------

func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	client := &wsClient{
		conn:    conn,
		server:  s,
		writeMu: sync.Mutex{},
	}
	client.serve()
}

// wsClient handles one WebSocket connection.
type wsClient struct {
	conn    *websocket.Conn
	server  *Server
	writeMu sync.Mutex
	closed  chan struct{} // closed when connection ends
}

func (c *wsClient) serve() {
	c.closed = make(chan struct{})
	defer close(c.closed)

	c.conn.SetReadLimit(1 << 20) // 1 MB
	_ = c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		return c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	})

	// Ping ticker for keepalive.
	done := make(chan struct{})
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	go func() {
		defer close(done)
		for range ticker.C {
			c.writeMu.Lock()
			err := c.conn.WriteControl(websocket.PingMessage, []byte("ping"), time.Now().Add(5*time.Second))
			c.writeMu.Unlock()
			if err != nil {
				return
			}
		}
	}()

	for {
		var raw RawMessage
		if err := c.conn.ReadJSON(&raw); err != nil {
			return
		}

		select {
		case <-done:
			return
		default:
		}

		log.Printf("[ws:recv] type=%s id=%s task_id=%s", raw.Type, raw.ID, raw.TaskID)
		c.dispatch(raw)
	}
}

// send writes a message to the WebSocket. Returns false if the write failed
// (connection closed), so callers can stop sending.
func (c *wsClient) send(msg OutMessage) bool {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	// Log outgoing messages (truncate payload for readability).
	if msg.Type == TypeAgentStream {
		if p, ok := msg.Payload.(AgentStreamPayload); ok {
			content := p.Content
			if len(content) > 80 {
				content = content[:80] + "..."
			}
			log.Printf("[ws:send] type=%s task=%s kind=%s content=%q", msg.Type, msg.TaskID, p.Kind, content)
		}
	} else {
		log.Printf("[ws:send] type=%s id=%s task=%s", msg.Type, msg.ID, msg.TaskID)
	}
	if err := c.conn.WriteJSON(msg); err != nil {
		log.Printf("ws write error: %v", err)
		return false
	}
	return true
}

func (c *wsClient) sendError(id string, code, message string) {
	c.send(OutMessage{
		Type: TypeError,
		ID:   id,
		Payload: ErrorPayload{
			Code:    code,
			Message: message,
		},
	})
}

func (c *wsClient) dispatch(raw RawMessage) {
	switch raw.Type {

	// ----- Task lifecycle -----
	case TypeTaskStart:
		c.handleTaskStart(raw)
	case TypePlanStart:
		c.handlePlanStart(raw)
	case TypeTaskCancel:
		c.handleTaskCancel(raw)
	case TypeTaskRetry:
		c.handleTaskRetry(raw)

	// ----- Provider / Config -----
	case TypeProviderSwitch:
		c.handleProviderSwitch(raw)
	case TypeConfigSet:
		c.handleConfigSet(raw)

	// ----- Sessions -----
	case TypeSessionList:
		c.handleSessionList(raw)
	case TypeSessionGet:
		c.handleSessionGet(raw)
	case TypeSessionResume:
		c.handleSessionResume(raw)
	case TypeSessionDelete:
		c.handleSessionDelete(raw)
	case TypeSessionInfo:
		c.handleSessionInfo(raw)
	case TypeSessionClear:
		c.handleSessionClear(raw)

	// ----- Filesystem (stub for now — OpenCode will implement) -----
	case TypeFSList, TypeFSRead:
		c.sendError(raw.ID, ErrInternalError, "filesystem operations not yet implemented")

	// ----- Git (stub for now — OpenCode will implement) -----
	case TypeGitStatus, TypeGitCommit, TypeGitPush, TypeGitDiff, TypeGitClone:
		c.sendError(raw.ID, ErrInternalError, "git operations not yet implemented")

	default:
		c.sendError(raw.ID, ErrUnsupportedMessage, fmt.Sprintf("unsupported message type: %s", raw.Type))
	}
}

// ---------------------------------------------------------------------------
// Message handlers
// ---------------------------------------------------------------------------

func (c *wsClient) handleTaskStart(raw RawMessage) {
	var payload TaskStartPayload
	if err := json.Unmarshal(raw.Payload, &payload); err != nil {
		c.sendError(raw.ID, ErrInvalidPayload, "invalid task.start payload")
		return
	}

	if payload.Prompt == "" {
		c.sendError(raw.ID, ErrInvalidPayload, "prompt is required")
		return
	}

	taskID := raw.TaskID
	if taskID == "" {
		taskID = raw.ID // use message ID as task ID if not specified
	}

	req := agent.TaskRequest{
		ID:           taskID,
		Prompt:       payload.Prompt,
		Provider:     payload.Provider,
		WorkingDir:   payload.WorkingDir,
		ContextFiles: payload.ContextFiles,
	}

	if req.Provider == "" {
		req.Provider = c.server.Config.ActiveProvider()
	}

	events, err := c.server.Tasks.StartTask(req)
	if err != nil {
		c.sendError(raw.ID, ErrInternalError, err.Error())
		return
	}

	// Stream events to the client in a goroutine.
	// Stop when client disconnects (c.closed) to prevent goroutine leaks.
	go func() {
		for {
			select {
			case <-c.closed:
				return
			case evt, ok := <-events:
				if !ok {
					return
				}
				if !c.send(OutMessage{
					Type:   TypeAgentStream,
					TaskID: evt.TaskID,
					Payload: AgentStreamPayload{
						Kind:      string(evt.Kind),
						Content:   evt.Content,
						Metadata:  evt.Metadata,
						Timestamp: time.Now().UTC().Format(time.RFC3339),
					},
				}) {
					return // connection closed
				}

				if evt.Kind == agent.EventDone {
					info, _ := c.server.Tasks.CompletionInfo(evt.TaskID)
					c.send(OutMessage{
						Type:    TypeTaskComplete,
						TaskID:  evt.TaskID,
						Payload: info,
					})
					return
				}
			}
		}
	}()
}

func (c *wsClient) handlePlanStart(raw RawMessage) {
	var payload TaskStartPayload
	if err := json.Unmarshal(raw.Payload, &payload); err != nil {
		c.sendError(raw.ID, ErrInvalidPayload, "invalid plan.start payload")
		return
	}

	if payload.Prompt == "" {
		c.sendError(raw.ID, ErrInvalidPayload, "prompt is required")
		return
	}

	if c.server.PlanTasks == nil {
		c.sendError(raw.ID, ErrInternalError, "plan mode not available")
		return
	}

	taskID := raw.TaskID
	if taskID == "" {
		taskID = "plan-" + raw.ID
	}

	req := agent.TaskRequest{
		ID:           taskID,
		Prompt:       payload.Prompt,
		Provider:     payload.Provider,
		WorkingDir:   payload.WorkingDir,
		ContextFiles: payload.ContextFiles,
	}

	if req.Provider == "" {
		req.Provider = c.server.Config.ActiveProvider()
	}

	events, err := c.server.PlanTasks.StartTask(req)
	if err != nil {
		c.sendError(raw.ID, ErrInternalError, err.Error())
		return
	}

	// Stream plan events to client.
	go func() {
		for {
			select {
			case <-c.closed:
				return
			case evt, ok := <-events:
				if !ok {
					return
				}
				if !c.send(OutMessage{
					Type:   TypeAgentStream,
					TaskID: evt.TaskID,
					Payload: AgentStreamPayload{
						Kind:      string(evt.Kind),
						Content:   evt.Content,
						Metadata:  evt.Metadata,
						Timestamp: time.Now().UTC().Format(time.RFC3339),
					},
				}) {
					return
				}

				if evt.Kind == agent.EventDone {
					c.send(OutMessage{
						Type:   TypeTaskComplete,
						TaskID: evt.TaskID,
						Payload: TaskCompletePayload{
							Summary: "Plan complete",
						},
					})
					return
				}
			}
		}
	}()
}

func (c *wsClient) handleTaskCancel(raw RawMessage) {
	taskID := raw.TaskID
	if taskID == "" {
		c.sendError(raw.ID, ErrInvalidPayload, "task_id is required for task.cancel")
		return
	}

	if err := c.server.Tasks.CancelTask(taskID); err != nil {
		c.sendError(raw.ID, ErrInternalError, err.Error())
		return
	}

	c.send(OutMessage{
		Type:   TypeServerStatus,
		ID:     raw.ID,
		TaskID: taskID,
		Payload: ServerStatusPayload{
			Version: Version,
		},
	})
}

func (c *wsClient) handleTaskRetry(raw RawMessage) {
	taskID := raw.TaskID
	if taskID == "" {
		c.sendError(raw.ID, ErrInvalidPayload, "task_id is required for task.retry")
		return
	}

	info, err := c.server.Tasks.TaskStatus(taskID)
	if err != nil {
		c.sendError(raw.ID, ErrInternalError, err.Error())
		return
	}

	if info.State != agent.StateFailed && info.State != agent.StateCanceled {
		c.sendError(raw.ID, ErrInternalError, fmt.Sprintf("cannot retry task in state: %s", info.State))
		return
	}

	// Re-start with same parameters.
	newReq := agent.TaskRequest{
		ID:       taskID + "-retry",
		Prompt:   info.Prompt,
		Provider: info.Provider,
	}

	events, err := c.server.Tasks.StartTask(newReq)
	if err != nil {
		c.sendError(raw.ID, ErrInternalError, err.Error())
		return
	}

	go func() {
		for {
			select {
			case <-c.closed:
				return
			case evt, ok := <-events:
				if !ok {
					return
				}
				if !c.send(OutMessage{
					Type:   TypeAgentStream,
					TaskID: evt.TaskID,
					Payload: AgentStreamPayload{
						Kind:      string(evt.Kind),
						Content:   evt.Content,
						Metadata:  evt.Metadata,
						Timestamp: time.Now().UTC().Format(time.RFC3339),
					},
				}) {
					return
				}
				if evt.Kind == agent.EventDone {
					complInfo, _ := c.server.Tasks.CompletionInfo(evt.TaskID)
					c.send(OutMessage{
						Type:    TypeTaskComplete,
						TaskID:  evt.TaskID,
						Payload: complInfo,
					})
					return
				}
			}
		}
	}()
}

func (c *wsClient) handleProviderSwitch(raw RawMessage) {
	var payload ProviderSwitchPayload
	if err := json.Unmarshal(raw.Payload, &payload); err != nil {
		c.sendError(raw.ID, ErrInvalidPayload, "invalid provider.switch payload")
		return
	}

	if err := c.server.Config.SwitchProvider(payload.Provider); err != nil {
		c.sendError(raw.ID, ErrInternalError, err.Error())
		return
	}

	c.send(OutMessage{
		Type:    TypeConfigCurrent,
		ID:      raw.ID,
		Payload: c.server.Config.Snapshot(),
	})
}

func (c *wsClient) handleConfigSet(raw RawMessage) {
	var payload ConfigSetPayload
	if err := json.Unmarshal(raw.Payload, &payload); err != nil {
		c.sendError(raw.ID, ErrInvalidPayload, "invalid config.set payload")
		return
	}

	if err := c.server.Config.SetConfig(payload.Key, payload.Value); err != nil {
		c.sendError(raw.ID, ErrInternalError, err.Error())
		return
	}

	c.send(OutMessage{
		Type:    TypeConfigCurrent,
		ID:      raw.ID,
		Payload: c.server.Config.Snapshot(),
	})
}

// ---------------------------------------------------------------------------
// Session handlers
// ---------------------------------------------------------------------------

func (c *wsClient) handleSessionList(raw RawMessage) {
	if c.server.Sessions == nil {
		c.sendError(raw.ID, ErrInternalError, "session persistence not enabled")
		return
	}
	c.send(OutMessage{
		Type:    TypeSessionListResult,
		ID:      raw.ID,
		Payload: c.server.Sessions.List(),
	})
}

func (c *wsClient) handleSessionGet(raw RawMessage) {
	if c.server.Sessions == nil {
		c.sendError(raw.ID, ErrInternalError, "session persistence not enabled")
		return
	}
	var payload SessionGetPayload
	if err := json.Unmarshal(raw.Payload, &payload); err != nil {
		c.sendError(raw.ID, ErrInvalidPayload, "invalid session.get payload")
		return
	}
	sess := c.server.Sessions.Get(payload.ID)
	if sess == nil {
		c.sendError(raw.ID, ErrInternalError, fmt.Sprintf("session %s not found", payload.ID))
		return
	}
	c.send(OutMessage{
		Type:    TypeSessionGetResult,
		ID:      raw.ID,
		Payload: sess,
	})
}

func (c *wsClient) handleSessionResume(raw RawMessage) {
	if c.server.Sessions == nil {
		c.sendError(raw.ID, ErrInternalError, "session persistence not enabled")
		return
	}
	var payload SessionResumePayload
	if err := json.Unmarshal(raw.Payload, &payload); err != nil {
		c.sendError(raw.ID, ErrInvalidPayload, "invalid session.resume payload")
		return
	}
	sess := c.server.Sessions.Get(payload.ID)
	if sess == nil {
		c.sendError(raw.ID, ErrInternalError, fmt.Sprintf("session %s not found", payload.ID))
		return
	}

	// Emit session metadata so the UI can show "Resumed session (N messages)".
	c.send(OutMessage{
		Type: TypeSessionInfoResult,
		ID:   raw.ID,
		Payload: SessionInfoResultPayload{
			ID:              sess.ID,
			Title:           sess.Title,
			MessageCount:    len(sess.Messages),
			TokensUsed:      sess.TokensUsed,
			State:           sess.State,
			Provider:        sess.Provider,
			CompactionCount: sess.CompactionCount,
		},
	})

	// Resume by starting a task. Use a unique task ID (session ID + timestamp)
	// so the task manager doesn't conflict with the previous completed task.
	// SessionID points to the persisted session for context restoration.
	req := agent.TaskRequest{
		ID:        fmt.Sprintf("%s-%d", payload.ID, time.Now().UnixMilli()),
		SessionID: payload.ID,
		Prompt:    payload.Prompt,
		Provider:  sess.Provider,
	}
	if req.Provider == "" {
		req.Provider = c.server.Config.ActiveProvider()
	}

	events, err := c.server.Tasks.StartTask(req)
	if err != nil {
		c.sendError(raw.ID, ErrInternalError, err.Error())
		return
	}

	go func() {
		for {
			select {
			case <-c.closed:
				return
			case evt, ok := <-events:
				if !ok {
					return
				}
				if !c.send(OutMessage{
					Type:   TypeAgentStream,
					TaskID: evt.TaskID,
					Payload: AgentStreamPayload{
						Kind:      string(evt.Kind),
						Content:   evt.Content,
						Metadata:  evt.Metadata,
						Timestamp: time.Now().UTC().Format(time.RFC3339),
					},
				}) {
					return
				}
				if evt.Kind == agent.EventDone {
					complInfo, _ := c.server.Tasks.CompletionInfo(evt.TaskID)
					c.send(OutMessage{
						Type:    TypeTaskComplete,
						TaskID:  evt.TaskID,
						Payload: complInfo,
					})
					return
				}
			}
		}
	}()
}

func (c *wsClient) handleSessionDelete(raw RawMessage) {
	if c.server.Sessions == nil {
		c.sendError(raw.ID, ErrInternalError, "session persistence not enabled")
		return
	}
	var payload SessionDeletePayload
	if err := json.Unmarshal(raw.Payload, &payload); err != nil {
		c.sendError(raw.ID, ErrInvalidPayload, "invalid session.delete payload")
		return
	}
	if err := c.server.Sessions.Delete(payload.ID); err != nil {
		c.sendError(raw.ID, ErrInternalError, err.Error())
		return
	}
	// Respond with updated list.
	c.send(OutMessage{
		Type:    TypeSessionListResult,
		ID:      raw.ID,
		Payload: c.server.Sessions.List(),
	})
}

func (c *wsClient) handleSessionInfo(raw RawMessage) {
	if c.server.Sessions == nil {
		c.sendError(raw.ID, ErrInternalError, "session persistence not enabled")
		return
	}
	var payload SessionInfoPayload
	if err := json.Unmarshal(raw.Payload, &payload); err != nil {
		c.sendError(raw.ID, ErrInvalidPayload, "invalid session.info payload")
		return
	}
	sess := c.server.Sessions.Get(payload.ID)
	if sess == nil {
		c.sendError(raw.ID, ErrInternalError, fmt.Sprintf("session %s not found", payload.ID))
		return
	}
	c.send(OutMessage{
		Type: TypeSessionInfoResult,
		ID:   raw.ID,
		Payload: SessionInfoResultPayload{
			ID:              sess.ID,
			Title:           sess.Title,
			MessageCount:    len(sess.Messages),
			TokensUsed:      sess.TokensUsed,
			State:           sess.State,
			Provider:        sess.Provider,
			CompactionCount: sess.CompactionCount,
		},
	})
}

func (c *wsClient) handleSessionClear(raw RawMessage) {
	if c.server.Sessions == nil {
		c.sendError(raw.ID, ErrInternalError, "session persistence not enabled")
		return
	}
	var payload SessionClearPayload
	if err := json.Unmarshal(raw.Payload, &payload); err != nil {
		c.sendError(raw.ID, ErrInvalidPayload, "invalid session.clear payload")
		return
	}
	if err := c.server.Sessions.ClearMessages(payload.ID); err != nil {
		c.sendError(raw.ID, ErrInternalError, err.Error())
		return
	}
	c.send(OutMessage{
		Type: TypeSessionClearResult,
		ID:   raw.ID,
		Payload: SessionInfoResultPayload{
			ID:           payload.ID,
			MessageCount: 0,
			TokensUsed:   0,
			State:        "active",
		},
	})
}

// ---------------------------------------------------------------------------
// File browser HTTP handlers (Flutter Files tab)
// ---------------------------------------------------------------------------

func (s *Server) handleFileContent(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	filePath := r.URL.Query().Get("path")
	if filePath == "" {
		http.Error(w, `{"error":"path is required"}`, http.StatusBadRequest)
		return
	}
	dir := r.URL.Query().Get("directory")
	if dir == "" {
		dir = s.Config.WorkingDir()
	}
	resolvedPath := filePath
	if dir != "" && !filepath.IsAbs(filePath) {
		resolvedPath = filepath.Join(dir, filePath)
	}
	absPath, err := filepath.Abs(resolvedPath)
	if err != nil {
		http.Error(w, `{"error":"invalid path"}`, http.StatusBadRequest)
		return
	}
	if dir != "" {
		absDir, _ := filepath.Abs(dir)
		if !strings.HasPrefix(absPath, absDir) {
			http.Error(w, `{"error":"path outside working directory"}`, http.StatusForbidden)
			return
		}
	}
	content, err := os.ReadFile(absPath)
	if err != nil {
		w.WriteHeader(http.StatusNotFound)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"path":    filePath,
		"content": string(content),
		"size":    len(content),
	})
}

func (s *Server) handleFindFile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	query := r.URL.Query().Get("query")
	if query == "" {
		http.Error(w, `{"error":"query is required"}`, http.StatusBadRequest)
		return
	}
	dir := r.URL.Query().Get("directory")
	if dir == "" {
		dir = s.Config.WorkingDir()
	}
	if dir == "" {
		dir = "."
	}
	limit := 20
	if l := r.URL.Query().Get("limit"); l != "" {
		fmt.Sscanf(l, "%d", &limit)
	}
	var results []map[string]any
	_ = filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			name := d.Name()
			if name == ".git" || name == "node_modules" || name == ".dart_tool" {
				return filepath.SkipDir
			}
			return nil
		}
		if len(results) >= limit {
			return filepath.SkipAll
		}
		name := d.Name()
		matched, _ := filepath.Match(query, name)
		if !matched {
			rel, _ := filepath.Rel(dir, path)
			matched, _ = filepath.Match(query, rel)
		}
		if !matched && !strings.ContainsAny(query, "*?[") {
			matched = strings.Contains(strings.ToLower(name), strings.ToLower(query))
		}
		if matched {
			rel, _ := filepath.Rel(dir, path)
			info, _ := d.Info()
			entry := map[string]any{"path": rel}
			if info != nil {
				entry["size"] = info.Size()
			}
			results = append(results, entry)
		}
		return nil
	})
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"files": results})
}

func (s *Server) handleFind(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	pattern := r.URL.Query().Get("pattern")
	if pattern == "" {
		http.Error(w, `{"error":"pattern is required"}`, http.StatusBadRequest)
		return
	}
	dir := r.URL.Query().Get("directory")
	if dir == "" {
		dir = s.Config.WorkingDir()
	}
	if dir == "" {
		dir = "."
	}
	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		fmt.Sscanf(l, "%d", &limit)
	}
	var matches []map[string]any
	_ = filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			name := d.Name()
			if name == ".git" || name == "node_modules" || name == ".dart_tool" || name == "build" {
				return filepath.SkipDir
			}
			return nil
		}
		if len(matches) >= limit {
			return filepath.SkipAll
		}
		info, _ := d.Info()
		if info != nil && info.Size() > 512*1024 {
			return nil
		}
		content, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		lines := strings.Split(string(content), "\n")
		rel, _ := filepath.Rel(dir, path)
		for i, line := range lines {
			if len(matches) >= limit {
				break
			}
			if strings.Contains(line, pattern) {
				matches = append(matches, map[string]any{
					"file": rel, "path": rel,
					"line": i + 1, "content": line, "text": line,
				})
			}
		}
		return nil
	})
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"matches": matches})
}

func (s *Server) handleSessionHTTP(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/session")
	if path != "" && path != "/" {
		s.handleSessionSubRoute(w, r, path)
		return
	}
	switch r.Method {
	case http.MethodGet:
		if s.Sessions == nil {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{"sessions": []any{}})
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"sessions": s.Sessions.List()})
	case http.MethodPost:
		var req struct {
			Title string `json:"title"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req)
		if req.Title == "" {
			req.Title = "Untitled"
		}
		id := fmt.Sprintf("sess-%d", time.Now().UnixMilli())
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"id": id, "title": req.Title})
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (s *Server) handleSessionSubRoute(w http.ResponseWriter, r *http.Request, path string) {
	parts := strings.SplitN(strings.TrimPrefix(path, "/"), "/", 2)
	if len(parts) < 2 {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	sessionID := parts[0]
	action := parts[1]
	switch action {
	case "message":
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"session_id": sessionID,
			"status":     "use WebSocket task.start for real execution",
		})
	case "prompt_async":
		w.WriteHeader(http.StatusNoContent)
	default:
		http.Error(w, "not found", http.StatusNotFound)
	}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Copilot Device Auth HTTP handlers
// ---------------------------------------------------------------------------

func (s *Server) handleCopilotDeviceAuth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	auth := s.Registry.CopilotAuth()
	if auth == nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "copilot provider not available"})
		return
	}

	dcResp, err := auth.StartDeviceFlow(r.Context())
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(dcResp)
}

func (s *Server) handleCopilotPoll(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	auth := s.Registry.CopilotAuth()
	if auth == nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "copilot provider not available"})
		return
	}

	var req struct {
		DeviceCode string `json:"device_code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.DeviceCode == "" {
		http.Error(w, `{"error":"device_code is required"}`, http.StatusBadRequest)
		return
	}

	result, err := auth.PollForToken(r.Context(), req.DeviceCode)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	// If auth succeeded, exchange for Copilot API token immediately.
	if result.Status == provider.PollSuccess {
		if _, err := auth.ExchangeToken(r.Context()); err != nil {
			log.Printf("copilot token exchange after auth: %v", err)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(result)
}

func listenLocalhost(startPort, maxScan int) (net.Listener, int, error) {
	for offset := 0; offset <= maxScan; offset++ {
		port := startPort + offset
		listener, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
		if err == nil {
			return listener, port, nil
		}
	}
	return nil, 0, fmt.Errorf("no free port found in range %d-%d", startPort, startPort+maxScan)
}

func writePortFile(portFile string, port int) error {
	if err := os.MkdirAll(filepath.Dir(portFile), 0o755); err != nil {
		return err
	}
	return os.WriteFile(portFile, []byte(fmt.Sprintf("%d\n", port)), 0o644)
}
