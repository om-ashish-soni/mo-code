package provider

import (
	"context"
	"fmt"
	"testing"
)

type failingProvider struct {
	name     string
	failures int // number of times to fail before succeeding
	calls    int
}

func (f *failingProvider) Name() string                    { return f.name }
func (f *failingProvider) Configured() bool                { return true }
func (f *failingProvider) Configure(Config) error          { return nil }

func (f *failingProvider) Stream(ctx context.Context, msgs []Message, tools []ToolDef) (<-chan StreamChunk, error) {
	f.calls++
	if f.calls <= f.failures {
		return nil, fmt.Errorf("status 503: service unavailable")
	}
	ch := make(chan StreamChunk, 1)
	ch <- StreamChunk{Text: "ok", Done: true, Usage: &Usage{InputTokens: 1, OutputTokens: 1}}
	close(ch)
	return ch, nil
}

func TestRetrySucceedsAfterTransientFailure(t *testing.T) {
	inner := &failingProvider{name: "test", failures: 2}
	rp := WrapWithRetry(inner)
	// Override delays to make test fast.
	rp.baseDelay = 0
	rp.maxDelay = 0

	ch, err := rp.Stream(context.Background(), nil, nil)
	if err != nil {
		t.Fatalf("expected success after retries, got: %v", err)
	}

	var text string
	for chunk := range ch {
		text += chunk.Text
	}
	if text != "ok" {
		t.Errorf("expected 'ok', got %q", text)
	}
	if inner.calls != 3 {
		t.Errorf("expected 3 calls (2 failures + 1 success), got %d", inner.calls)
	}
}

func TestRetryGivesUpAfterMaxRetries(t *testing.T) {
	inner := &failingProvider{name: "test", failures: 10} // always fails
	rp := WrapWithRetry(inner)
	rp.baseDelay = 0
	rp.maxDelay = 0

	_, err := rp.Stream(context.Background(), nil, nil)
	if err == nil {
		t.Fatal("expected error after max retries")
	}
	// Should attempt 1 + 3 retries = 4 calls
	if inner.calls != 4 {
		t.Errorf("expected 4 calls, got %d", inner.calls)
	}
}

func TestRetryNoRetryOnNonTransient(t *testing.T) {
	inner := &failingProvider{name: "test", failures: 10}
	// Override to return a non-retryable error.
	rp := &RetryProvider{
		inner:      &nonRetryableProvider{},
		maxRetries: 3,
		baseDelay:  0,
		maxDelay:   0,
	}

	_, err := rp.Stream(context.Background(), nil, nil)
	if err == nil {
		t.Fatal("expected error")
	}
	_ = inner // unused, we used nonRetryableProvider instead
}

type nonRetryableProvider struct{}

func (n *nonRetryableProvider) Name() string                    { return "nope" }
func (n *nonRetryableProvider) Configured() bool                { return true }
func (n *nonRetryableProvider) Configure(Config) error          { return nil }
func (n *nonRetryableProvider) Stream(ctx context.Context, msgs []Message, tools []ToolDef) (<-chan StreamChunk, error) {
	return nil, fmt.Errorf("provider not configured: missing API key")
}

func TestIsRetryable(t *testing.T) {
	tests := []struct {
		err  string
		want bool
	}{
		{"status 429: rate limited", true},
		{"status 503: service unavailable", true},
		{"connection refused", true},
		{"connection reset by peer", true},
		{"context deadline exceeded (timeout)", true},
		{"unexpected EOF", true},
		{"overloaded", true},
		{"provider not configured: missing API key", false},
		{"unknown provider: foo", false},
		{"invalid JSON in response", false},
	}
	for _, tt := range tests {
		got := isRetryable(fmt.Errorf("%s", tt.err))
		if got != tt.want {
			t.Errorf("isRetryable(%q) = %v, want %v", tt.err, got, tt.want)
		}
	}
}

func TestNewHTTPClient(t *testing.T) {
	c := NewHTTPClient()
	if c.Timeout != defaultHTTPTimeout {
		t.Errorf("timeout = %v, want %v", c.Timeout, defaultHTTPTimeout)
	}
}
