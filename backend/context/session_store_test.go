package context

import (
	"os"
	"testing"

	"mo-code/backend/provider"
)

func TestSessionStoreCreateAndGet(t *testing.T) {
	dir := t.TempDir()
	store, err := NewSessionStore(dir)
	if err != nil {
		t.Fatalf("NewSessionStore: %v", err)
	}

	sess, err := store.Create("s1", "Hello world", "/tmp/project", "claude", "claude-sonnet-4")
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	if sess.ID != "s1" {
		t.Errorf("ID = %q, want s1", sess.ID)
	}
	if sess.Title != "Hello world" {
		t.Errorf("Title = %q, want 'Hello world'", sess.Title)
	}
	if sess.State != "active" {
		t.Errorf("State = %q, want active", sess.State)
	}

	got := store.Get("s1")
	if got == nil {
		t.Fatal("Get returned nil")
	}
	if got.Provider != "claude" {
		t.Errorf("Provider = %q, want claude", got.Provider)
	}
}

func TestSessionStoreAppendMessage(t *testing.T) {
	dir := t.TempDir()
	store, err := NewSessionStore(dir)
	if err != nil {
		t.Fatalf("NewSessionStore: %v", err)
	}

	store.Create("s1", "test", "/tmp", "claude", "")

	msg := provider.Message{Role: provider.RoleUser, Content: "hello"}
	if err := store.AppendMessage("s1", msg); err != nil {
		t.Fatalf("AppendMessage: %v", err)
	}

	sess := store.Get("s1")
	if len(sess.Messages) != 1 {
		t.Fatalf("expected 1 message, got %d", len(sess.Messages))
	}
	if sess.Messages[0].Content != "hello" {
		t.Errorf("message content = %q", sess.Messages[0].Content)
	}
}

func TestSessionStorePersistence(t *testing.T) {
	dir := t.TempDir()

	// Create store, add session + message, then drop it.
	store1, _ := NewSessionStore(dir)
	store1.Create("s1", "persist test", "/tmp", "gemini", "gemini-pro")
	store1.AppendMessage("s1", provider.Message{Role: provider.RoleUser, Content: "hello"})
	store1.AppendMessage("s1", provider.Message{Role: provider.RoleAssistant, Content: "hi there"})
	store1.UpdateState("s1", "completed")

	// Create a new store from the same directory — should reload.
	store2, err := NewSessionStore(dir)
	if err != nil {
		t.Fatalf("NewSessionStore (reload): %v", err)
	}

	sess := store2.Get("s1")
	if sess == nil {
		t.Fatal("session not found after reload")
	}
	if len(sess.Messages) != 2 {
		t.Fatalf("expected 2 messages after reload, got %d", len(sess.Messages))
	}
	if sess.State != "completed" {
		t.Errorf("State = %q, want completed", sess.State)
	}
	if sess.Provider != "gemini" {
		t.Errorf("Provider = %q, want gemini", sess.Provider)
	}
}

func TestSessionStoreList(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewSessionStore(dir)

	store.Create("s1", "first", "/tmp", "claude", "")
	store.Create("s2", "second", "/tmp", "gemini", "")

	list := store.List()
	if len(list) != 2 {
		t.Fatalf("expected 2 sessions, got %d", len(list))
	}

	// Most recently updated should be first.
	if list[0].ID != "s2" {
		t.Errorf("expected s2 first (most recent), got %s", list[0].ID)
	}
}

func TestSessionStoreDelete(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewSessionStore(dir)

	store.Create("s1", "delete me", "/tmp", "claude", "")

	if err := store.Delete("s1"); err != nil {
		t.Fatalf("Delete: %v", err)
	}

	if store.Get("s1") != nil {
		t.Error("session still in cache after delete")
	}

	// Check file is gone.
	if _, err := os.Stat(store.filePath("s1")); !os.IsNotExist(err) {
		t.Error("session file still on disk after delete")
	}
}

func TestSessionStoreAppendMessageNotFound(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewSessionStore(dir)

	err := store.AppendMessage("nonexistent", provider.Message{})
	if err == nil {
		t.Error("expected error for nonexistent session")
	}
}

// --- Concurrent access (run with -race) ---

func TestSessionStore_ConcurrentAccess(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewSessionStore(dir)

	store.Create("concurrent-1", "test", "/tmp", "claude", "")

	done := make(chan struct{})

	// Writer goroutine: append messages.
	go func() {
		defer func() { done <- struct{}{} }()
		for i := 0; i < 50; i++ {
			store.AppendMessage("concurrent-1", provider.Message{
				Role:    provider.RoleUser,
				Content: "msg",
			})
		}
	}()

	// Reader goroutine: read session.
	go func() {
		defer func() { done <- struct{}{} }()
		for i := 0; i < 50; i++ {
			sess := store.Get("concurrent-1")
			if sess == nil {
				t.Error("Get returned nil during concurrent access")
				return
			}
			_ = len(sess.Messages)
		}
	}()

	// List goroutine.
	go func() {
		defer func() { done <- struct{}{} }()
		for i := 0; i < 50; i++ {
			list := store.List()
			_ = len(list)
		}
	}()

	// State update goroutine.
	go func() {
		defer func() { done <- struct{}{} }()
		for i := 0; i < 50; i++ {
			store.UpdateState("concurrent-1", "active")
		}
	}()

	// Wait for all goroutines.
	for i := 0; i < 4; i++ {
		<-done
	}

	sess := store.Get("concurrent-1")
	if sess == nil {
		t.Fatal("session nil after concurrent ops")
	}
	if len(sess.Messages) != 50 {
		t.Errorf("expected 50 messages, got %d", len(sess.Messages))
	}
}

// --- Large message history ---

func TestSessionStore_LargeMessageHistory(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewSessionStore(dir)

	store.Create("large-1", "stress test", "/tmp", "claude", "")

	// Append 150 messages.
	for i := 0; i < 150; i++ {
		role := provider.RoleUser
		if i%2 == 1 {
			role = provider.RoleAssistant
		}
		store.AppendMessage("large-1", provider.Message{
			Role:    role,
			Content: "message number " + string(rune('0'+i%10)),
		})
	}

	sess := store.Get("large-1")
	if len(sess.Messages) != 150 {
		t.Fatalf("expected 150 messages, got %d", len(sess.Messages))
	}

	// Verify persistence with large history.
	store2, _ := NewSessionStore(dir)
	sess2 := store2.Get("large-1")
	if sess2 == nil {
		t.Fatal("session lost after reload")
	}
	if len(sess2.Messages) != 150 {
		t.Fatalf("expected 150 messages after reload, got %d", len(sess2.Messages))
	}
}

// --- UpdateTokens ---

func TestSessionStore_UpdateTokens(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewSessionStore(dir)

	store.Create("tok-1", "test", "/tmp", "claude", "")
	store.UpdateTokens("tok-1", 1234)

	sess := store.Get("tok-1")
	if sess.TokensUsed != 1234 {
		t.Errorf("TokensUsed = %d, want 1234", sess.TokensUsed)
	}
}

func TestSessionStore_UpdateTokens_NotFound(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewSessionStore(dir)

	err := store.UpdateTokens("nonexistent", 100)
	if err == nil {
		t.Error("expected error for nonexistent session")
	}
}

func TestGenerateTitle(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"Hello world", "Hello world"},
		{"Line 1\nLine 2", "Line 1"},
		{"", "Untitled session"},
		{string(make([]byte, 200)), string(make([]byte, 77)) + "..."},
	}

	for _, tt := range tests {
		got := generateTitle(tt.input)
		if got != tt.want {
			t.Errorf("generateTitle(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}
