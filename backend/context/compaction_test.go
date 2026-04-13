package context

import (
	"testing"

	"mo-code/backend/provider"
)

// --- SummaryBudget tests ---

func TestSummaryBudget_Apply_TruncatesLongLines(t *testing.T) {
	budget := SummaryBudget{MaxChars: 10000, MaxLines: 100, MaxLineChars: 20}
	input := "short\n" + string(make([]byte, 50)) + "\nend"
	result := budget.Apply(input)

	lines := splitLines(result)
	for _, line := range lines {
		if len(line) > 20+3 { // 20 + "..."
			t.Errorf("line too long after Apply: %d chars", len(line))
		}
	}
}

func TestSummaryBudget_Apply_CapsLines(t *testing.T) {
	budget := SummaryBudget{MaxChars: 100000, MaxLines: 3, MaxLineChars: 1000}
	input := "line1\nline2\nline3\nline4\nline5"
	result := budget.Apply(input)

	lines := splitLines(result)
	if len(lines) > 3 {
		t.Errorf("expected at most 3 lines, got %d", len(lines))
	}
}

func TestSummaryBudget_Apply_CapsChars(t *testing.T) {
	budget := SummaryBudget{MaxChars: 50, MaxLines: 1000, MaxLineChars: 1000}
	input := string(make([]byte, 200))
	result := budget.Apply(input)

	if len(result) > 80 { // 50 + truncation message
		t.Errorf("expected result under 80 chars, got %d", len(result))
	}
}

func TestSummaryBudget_Apply_DedupesConsecutiveLines(t *testing.T) {
	budget := DefaultSummaryBudget()
	input := "hello\nhello\nhello\nworld\nworld"
	result := budget.Apply(input)

	lines := splitLines(result)
	if len(lines) != 2 {
		t.Errorf("expected 2 unique lines, got %d: %v", len(lines), lines)
	}
}

func splitLines(s string) []string {
	var lines []string
	for _, line := range splitString(s, '\n') {
		if line != "" {
			lines = append(lines, line)
		}
	}
	return lines
}

func splitString(s string, sep byte) []string {
	var result []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == sep {
			result = append(result, s[start:i])
			start = i + 1
		}
	}
	result = append(result, s[start:])
	return result
}

// --- ClearMessages + IncrementCompaction tests ---

func TestSessionStore_ClearMessages(t *testing.T) {
	dir := t.TempDir()
	store, err := NewSessionStore(dir)
	if err != nil {
		t.Fatalf("NewSessionStore: %v", err)
	}

	store.Create("s1", "test session", "/tmp", "claude", "")
	store.AppendMessage("s1", provider.Message{Role: provider.RoleUser, Content: "hello"})
	store.AppendMessage("s1", provider.Message{Role: provider.RoleAssistant, Content: "hi"})
	store.UpdateTokens("s1", 500)
	store.UpdateState("s1", "completed")

	// Clear messages.
	if err := store.ClearMessages("s1"); err != nil {
		t.Fatalf("ClearMessages: %v", err)
	}

	sess := store.Get("s1")
	if len(sess.Messages) != 0 {
		t.Errorf("expected 0 messages after clear, got %d", len(sess.Messages))
	}
	if sess.TokensUsed != 0 {
		t.Errorf("expected 0 tokens after clear, got %d", sess.TokensUsed)
	}
	if sess.State != "active" {
		t.Errorf("expected state active after clear, got %q", sess.State)
	}
	// Session itself should still exist.
	if sess.Title != "test session" {
		t.Errorf("title should be preserved, got %q", sess.Title)
	}
}

func TestSessionStore_ClearMessages_NotFound(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewSessionStore(dir)
	err := store.ClearMessages("nonexistent")
	if err == nil {
		t.Error("expected error for nonexistent session")
	}
}

func TestSessionStore_IncrementCompaction(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewSessionStore(dir)

	store.Create("s1", "test", "/tmp", "claude", "")

	sess := store.Get("s1")
	if sess.CompactionCount != 0 {
		t.Fatalf("initial CompactionCount = %d, want 0", sess.CompactionCount)
	}

	for i := 0; i < 3; i++ {
		if err := store.IncrementCompaction("s1"); err != nil {
			t.Fatalf("IncrementCompaction %d: %v", i, err)
		}
	}

	sess = store.Get("s1")
	if sess.CompactionCount != 3 {
		t.Errorf("CompactionCount = %d, want 3", sess.CompactionCount)
	}

	// Verify persists across reload.
	store2, _ := NewSessionStore(dir)
	sess2 := store2.Get("s1")
	if sess2.CompactionCount != 3 {
		t.Errorf("CompactionCount after reload = %d, want 3", sess2.CompactionCount)
	}
}

func TestSessionStore_IncrementCompaction_NotFound(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewSessionStore(dir)
	err := store.IncrementCompaction("nonexistent")
	if err == nil {
		t.Error("expected error for nonexistent session")
	}
}

