package agent

import (
	"context"
	"testing"

	agentctx "mo-code/backend/context"
	"mo-code/backend/provider"
)

// E2E tests for the full agent loop: multi-turn conversations, session
// persistence round-trips, provider switching, and cancel behavior.

// --- Multi-turn tool call conversation ---

func TestE2E_AgentLoop_MultiTurnToolCalls(t *testing.T) {
	// Simulate: user asks → LLM calls file_read → gets result → LLM calls shell_exec → gets result → LLM responds
	mp := newMockProvider([][]provider.StreamChunk{
		// Round 1: LLM requests file_read
		{
			{Text: "Let me read the file first."},
			{ToolCall: &provider.ToolCall{ID: "call-1", Name: "file_read", Args: `{"path":"test.txt"}`}},
			{Done: true, Usage: &provider.Usage{InputTokens: 100, OutputTokens: 30}},
		},
		// Round 2: LLM requests shell_exec
		{
			{Text: "Now let me check the project structure."},
			{ToolCall: &provider.ToolCall{ID: "call-2", Name: "shell_exec", Args: `{"command":"echo project_check"}`}},
			{Done: true, Usage: &provider.Usage{InputTokens: 200, OutputTokens: 40}},
		},
		// Round 3: LLM gives final text answer
		{
			{Text: "Based on my analysis, everything looks good."},
			{Done: true, Usage: &provider.Usage{InputTokens: 300, OutputTokens: 25}},
		},
	})

	reg := &mockRegistry{p: mp}
	e := NewEngine(reg, "/tmp", nil)

	events, err := e.Start(context.Background(), TaskRequest{
		ID:     "e2e-multi-turn",
		Prompt: "Check the project",
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}

	var allEvents []Event
	for evt := range events {
		allEvents = append(allEvents, evt)
	}

	// Verify event sequence: text, tool_call, token_usage, tool_result, text, tool_call, token_usage, tool_result, text, token_usage, done
	kinds := make([]EventKind, len(allEvents))
	for i, e := range allEvents {
		kinds[i] = e.Kind
	}

	// Should have text→tool_call→usage→tool_result→text→tool_call→usage→tool_result→text→usage→done
	if allEvents[len(allEvents)-1].Kind != EventDone {
		t.Fatalf("last event should be done, got: %s", allEvents[len(allEvents)-1].Kind)
	}

	// Count event types.
	counts := map[EventKind]int{}
	for _, e := range allEvents {
		counts[e.Kind]++
	}
	if counts[EventText] != 3 {
		t.Errorf("expected 3 text events, got %d", counts[EventText])
	}
	if counts[EventToolCall] != 2 {
		t.Errorf("expected 2 tool_call events, got %d", counts[EventToolCall])
	}
	if counts[EventToolResult] != 2 {
		t.Errorf("expected 2 tool_result events, got %d", counts[EventToolResult])
	}
	if counts[EventTokenUsage] != 3 {
		t.Errorf("expected 3 token_usage events, got %d", counts[EventTokenUsage])
	}
	if counts[EventDone] != 1 {
		t.Errorf("expected 1 done event, got %d", counts[EventDone])
	}

	// Verify task completed.
	info, err := e.Status("e2e-multi-turn")
	if err != nil {
		t.Fatalf("Status: %v", err)
	}
	if info.State != StateCompleted {
		t.Fatalf("task state = %s, want completed", info.State)
	}
}

// --- Session persistence round-trip ---

func TestE2E_SessionPersistence_SaveAndResume(t *testing.T) {
	dir := t.TempDir()
	store, err := agentctx.NewSessionStore(dir)
	if err != nil {
		t.Fatalf("NewSessionStore: %v", err)
	}

	// First conversation: simple text response.
	mp1 := newMockProvider([][]provider.StreamChunk{
		{
			{Text: "Hello! I can help with that."},
			{Done: true, Usage: &provider.Usage{InputTokens: 50, OutputTokens: 10}},
		},
	})

	reg := &mockRegistry{p: mp1}
	e1 := NewEngine(reg, "/tmp", store)

	events, err := e1.Start(context.Background(), TaskRequest{
		ID:     "session-1",
		Prompt: "Help me with my project",
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	for range events {
	} // drain

	// Verify session was saved.
	sess := store.Get("session-1")
	if sess == nil {
		t.Fatal("session not persisted")
	}
	if sess.State != "completed" {
		t.Fatalf("session state = %q, want completed", sess.State)
	}
	if len(sess.Messages) < 2 {
		t.Fatalf("expected at least 2 messages (user + assistant), got %d", len(sess.Messages))
	}

	// Verify messages: user prompt + assistant response.
	if sess.Messages[0].Role != provider.RoleUser {
		t.Errorf("first message role = %s, want user", sess.Messages[0].Role)
	}
	if sess.Messages[0].Content != "Help me with my project" {
		t.Errorf("first message content = %q", sess.Messages[0].Content)
	}
	if sess.Messages[1].Role != provider.RoleAssistant {
		t.Errorf("second message role = %s, want assistant", sess.Messages[1].Role)
	}

	// Resume the session with a follow-up.
	mp2 := newMockProvider([][]provider.StreamChunk{
		{
			{Text: "Sure, continuing from where we left off."},
			{Done: true, Usage: &provider.Usage{InputTokens: 80, OutputTokens: 15}},
		},
	})
	reg2 := &mockRegistry{p: mp2}
	e2 := NewEngine(reg2, "/tmp", store)

	events2, err := e2.Start(context.Background(), TaskRequest{
		ID:     "session-1",
		Prompt: "Can you also check the tests?",
	})
	if err != nil {
		t.Fatalf("Resume Start: %v", err)
	}
	for range events2 {
	} // drain

	// Session should now have more messages (original + follow-up + response).
	sess2 := store.Get("session-1")
	if len(sess2.Messages) < 4 {
		t.Fatalf("expected at least 4 messages after resume, got %d", len(sess2.Messages))
	}
}

// --- Session persistence survives restart ---

func TestE2E_SessionPersistence_SurvivesRestart(t *testing.T) {
	dir := t.TempDir()

	// Create store, run a task, close it.
	store1, _ := agentctx.NewSessionStore(dir)
	mp := newMockProvider([][]provider.StreamChunk{
		{
			{Text: "First response."},
			{Done: true, Usage: &provider.Usage{InputTokens: 10, OutputTokens: 5}},
		},
	})
	e1 := NewEngine(&mockRegistry{p: mp}, "/tmp", store1)
	events, _ := e1.Start(context.Background(), TaskRequest{ID: "persist-test", Prompt: "Hello"})
	for range events {
	}

	// Simulate daemon restart — create new store from same dir.
	store2, _ := agentctx.NewSessionStore(dir)
	sess := store2.Get("persist-test")
	if sess == nil {
		t.Fatal("session not found after simulated restart")
	}
	if sess.State != "completed" {
		t.Fatalf("state = %q after restart", sess.State)
	}
	if len(sess.Messages) < 2 {
		t.Fatalf("expected messages after restart, got %d", len(sess.Messages))
	}
}

// --- Cancel mid-stream ---

func TestE2E_Cancel_MidStream(t *testing.T) {
	// Provider sends text slowly — we cancel before it finishes.
	slowCh := make(chan provider.StreamChunk, 10)

	mp := &channelProvider{name: "slow", ch: slowCh}
	reg := &mockRegistry{p: mp}
	e := NewEngine(reg, "/tmp", nil)

	events, err := e.Start(context.Background(), TaskRequest{
		ID:     "cancel-test",
		Prompt: "Do something slow",
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}

	// Send one chunk, then cancel.
	slowCh <- provider.StreamChunk{Text: "Starting..."}
	// Read the first event.
	<-events

	err = e.Cancel("cancel-test")
	if err != nil {
		t.Fatalf("Cancel: %v", err)
	}

	// Drain remaining events — the channel provider's goroutine will exit
	// via context cancellation, so we don't close slowCh (it would race).
	for range events {
	}

	info, _ := e.Status("cancel-test")
	if info.State != StateCanceled {
		t.Fatalf("state = %s, want canceled", info.State)
	}
}

// --- Provider info in task ---

func TestE2E_TaskInfo_HasProviderName(t *testing.T) {
	mp := newMockProvider([][]provider.StreamChunk{
		{
			{Text: "ok"},
			{Done: true, Usage: &provider.Usage{InputTokens: 5, OutputTokens: 2}},
		},
	})
	reg := &mockRegistry{p: mp}
	e := NewEngine(reg, "/tmp", nil)

	events, _ := e.Start(context.Background(), TaskRequest{
		ID:     "info-test",
		Prompt: "test",
	})
	for range events {
	}

	info, err := e.Status("info-test")
	if err != nil {
		t.Fatalf("Status: %v", err)
	}
	if info.Provider != "mock" {
		t.Fatalf("provider = %q, want mock", info.Provider)
	}
	if info.Prompt != "test" {
		t.Fatalf("prompt = %q, want test", info.Prompt)
	}
}

// --- Engine info ---

func TestE2E_EngineInfo(t *testing.T) {
	reg := provider.NewRegistry()
	e := NewEngine(reg, "/tmp/project", nil)

	info := e.EngineInfo()
	if info["working_dir"] != "/tmp/project" {
		t.Fatalf("working_dir = %v", info["working_dir"])
	}
	tools, ok := info["tools"].([]string)
	if !ok || len(tools) == 0 {
		t.Fatalf("expected non-empty tools list, got: %v", info["tools"])
	}
	providers, ok := info["providers"].([]string)
	if !ok || len(providers) == 0 {
		t.Fatalf("expected non-empty providers list, got: %v", info["providers"])
	}
}

// --- Multi-turn context continuity (FEAT-003) ---

func TestE2E_MultiTurnContextContinuity(t *testing.T) {
	// 3 sequential prompts on the same session ID.
	// Each turn, the mock provider records the messages it received
	// so we can verify history accumulates.
	dir := t.TempDir()
	store, _ := agentctx.NewSessionStore(dir)

	var receivedMsgCounts []int

	// We need a provider that records how many messages it receives each call.
	// Use a custom provider for this.
	mp := &recordingProvider{
		name:       "recorder",
		msgCounts:  &receivedMsgCounts,
		responses: [][]provider.StreamChunk{
			// Turn 1 response
			{{Text: "Response to turn 1."}, {Done: true, Usage: &provider.Usage{InputTokens: 50, OutputTokens: 10}}},
			// Turn 2 response
			{{Text: "Response to turn 2."}, {Done: true, Usage: &provider.Usage{InputTokens: 100, OutputTokens: 15}}},
			// Turn 3 response
			{{Text: "Response to turn 3."}, {Done: true, Usage: &provider.Usage{InputTokens: 150, OutputTokens: 20}}},
		},
	}

	reg := &mockRegistry{p: mp}

	// Turn 1: fresh session
	e1 := NewEngine(reg, "/tmp", store)
	events1, err := e1.Start(context.Background(), TaskRequest{
		ID:     "multi-turn-1",
		Prompt: "What is 2+2?",
	})
	if err != nil {
		t.Fatalf("Turn 1 Start: %v", err)
	}
	for range events1 {
	}

	// Turn 2: same session ID → should resume with history
	mp.callIdx = 1
	e2 := NewEngine(reg, "/tmp", store)
	events2, err := e2.Start(context.Background(), TaskRequest{
		ID:     "multi-turn-1",
		Prompt: "Now what is 3+3?",
	})
	if err != nil {
		t.Fatalf("Turn 2 Start: %v", err)
	}
	for range events2 {
	}

	// Turn 3: same session ID → should have full history
	mp.callIdx = 2
	e3 := NewEngine(reg, "/tmp", store)
	events3, err := e3.Start(context.Background(), TaskRequest{
		ID:     "multi-turn-1",
		Prompt: "And 4+4?",
	})
	if err != nil {
		t.Fatalf("Turn 3 Start: %v", err)
	}
	for range events3 {
	}

	// Verify message counts increased each turn.
	// Turn 1: system + 1 user = provider sees 1 user message
	// Turn 2: system + 1 user + 1 assistant + 1 user = provider sees 3 messages (+ system)
	// Turn 3: system + 1u + 1a + 1u + 1a + 1u = provider sees 5 messages (+ system)
	if len(receivedMsgCounts) != 3 {
		t.Fatalf("expected 3 provider calls, got %d", len(receivedMsgCounts))
	}
	// Each turn should see more messages than the previous.
	for i := 1; i < len(receivedMsgCounts); i++ {
		if receivedMsgCounts[i] <= receivedMsgCounts[i-1] {
			t.Errorf("turn %d received %d messages, should be more than turn %d's %d",
				i+1, receivedMsgCounts[i], i, receivedMsgCounts[i-1])
		}
	}

	// Verify session has all messages persisted.
	sess := store.Get("multi-turn-1")
	if sess == nil {
		t.Fatal("session not found")
	}
	// 3 user + 3 assistant = 6 messages minimum
	if len(sess.Messages) < 6 {
		t.Errorf("expected at least 6 messages in session, got %d", len(sess.Messages))
	}
}

// --- Concurrent task guard ---

func TestE2E_ConcurrentTaskGuard(t *testing.T) {
	dir := t.TempDir()
	store, _ := agentctx.NewSessionStore(dir)

	// Start a long-running task using channel provider.
	slowCh := make(chan provider.StreamChunk, 10)
	mp := &channelProvider{name: "slow", ch: slowCh}
	reg := &mockRegistry{p: mp}
	e := NewEngine(reg, "/tmp", store)

	events, err := e.Start(context.Background(), TaskRequest{
		ID:     "guard-test",
		Prompt: "Do something slow",
	})
	if err != nil {
		t.Fatalf("First Start: %v", err)
	}

	// Try to start another task on the same session ID while the first is running.
	_, err = e.Start(context.Background(), TaskRequest{
		ID:     "guard-test",
		Prompt: "This should be rejected",
	})
	if err == nil {
		t.Fatal("expected error when starting concurrent task on same session")
	}

	// Clean up: unblock the provider and drain the event channel.
	e.Cancel("guard-test")
	close(slowCh)
	for range events {
	}
}

// --- Provider switch mid-session ---

func TestE2E_ProviderSwitchMidSession(t *testing.T) {
	dir := t.TempDir()
	store, _ := agentctx.NewSessionStore(dir)

	// Turn 1: use provider "alpha"
	mpAlpha := newMockProvider([][]provider.StreamChunk{
		{{Text: "Alpha response."}, {Done: true, Usage: &provider.Usage{InputTokens: 30, OutputTokens: 10}}},
	})
	mpAlpha.name = "alpha"

	regAlpha := &mockRegistry{p: mpAlpha}
	e1 := NewEngine(regAlpha, "/tmp", store)

	events1, _ := e1.Start(context.Background(), TaskRequest{
		ID:     "switch-test",
		Prompt: "Hello from alpha",
	})
	for range events1 {
	}

	// Turn 2: switch to provider "beta" — same session ID
	mpBeta := &recordingProvider{
		name:      "beta",
		msgCounts: new([]int),
		responses: [][]provider.StreamChunk{
			{{Text: "Beta response."}, {Done: true, Usage: &provider.Usage{InputTokens: 60, OutputTokens: 12}}},
		},
	}
	regBeta := &mockRegistry{p: mpBeta}
	e2 := NewEngine(regBeta, "/tmp", store)

	events2, err := e2.Start(context.Background(), TaskRequest{
		ID:       "switch-test",
		Prompt:   "Hello from beta",
		Provider: "beta",
	})
	if err != nil {
		t.Fatalf("Turn 2 Start: %v", err)
	}
	for range events2 {
	}

	// Beta should have received the full history including alpha's messages.
	if len(*mpBeta.msgCounts) != 1 {
		t.Fatalf("expected 1 provider call, got %d", len(*mpBeta.msgCounts))
	}
	// Should see: user("Hello from alpha") + assistant("Alpha response.") + user("Hello from beta") = 3+ messages
	if (*mpBeta.msgCounts)[0] < 3 {
		t.Errorf("beta received %d messages, expected at least 3 (history should carry over)", (*mpBeta.msgCounts)[0])
	}

	// Verify session persists both turns.
	sess := store.Get("switch-test")
	if len(sess.Messages) < 4 {
		t.Errorf("expected at least 4 messages, got %d", len(sess.Messages))
	}
}

// --- recordingProvider: tracks how many messages are passed to Stream ---

type recordingProvider struct {
	name      string
	responses [][]provider.StreamChunk
	callIdx   int
	msgCounts *[]int // pointer to shared slice so multiple engines can share
}

func (p *recordingProvider) Name() string                    { return p.name }
func (p *recordingProvider) Configured() bool                { return true }
func (p *recordingProvider) Configure(provider.Config) error { return nil }

func (p *recordingProvider) Stream(ctx context.Context, msgs []provider.Message, tools []provider.ToolDef) (<-chan provider.StreamChunk, error) {
	*p.msgCounts = append(*p.msgCounts, len(msgs))

	ch := make(chan provider.StreamChunk, 32)
	go func() {
		defer close(ch)
		if p.callIdx < len(p.responses) {
			for _, chunk := range p.responses[p.callIdx] {
				select {
				case <-ctx.Done():
					return
				case ch <- chunk:
				}
			}
			p.callIdx++
		}
	}()
	return ch, nil
}

// --- channelProvider: lets tests control streaming manually ---

type channelProvider struct {
	name string
	ch   <-chan provider.StreamChunk
}

func (p *channelProvider) Name() string                    { return p.name }
func (p *channelProvider) Configured() bool                { return true }
func (p *channelProvider) Configure(provider.Config) error { return nil }

func (p *channelProvider) Stream(ctx context.Context, msgs []provider.Message, tools []provider.ToolDef) (<-chan provider.StreamChunk, error) {
	out := make(chan provider.StreamChunk, 32)
	go func() {
		defer close(out)
		for {
			select {
			case <-ctx.Done():
				return
			case chunk, ok := <-p.ch:
				if !ok {
					return
				}
				select {
				case <-ctx.Done():
					return
				case out <- chunk:
				}
			}
		}
	}()
	return out, nil
}
