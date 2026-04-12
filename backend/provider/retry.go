package provider

import (
	"context"
	"fmt"
	"math"
	"net/http"
	"strings"
	"time"
)

const (
	defaultMaxRetries   = 3
	defaultBaseDelay    = 1 * time.Second
	defaultMaxDelay     = 30 * time.Second
	defaultHTTPTimeout  = 120 * time.Second
)

// RetryProvider wraps a Provider with automatic retry on transient errors.
// It uses exponential backoff with jitter.
type RetryProvider struct {
	inner      Provider
	maxRetries int
	baseDelay  time.Duration
	maxDelay   time.Duration
}

// WrapWithRetry wraps a provider with retry logic.
func WrapWithRetry(p Provider) *RetryProvider {
	return &RetryProvider{
		inner:      p,
		maxRetries: defaultMaxRetries,
		baseDelay:  defaultBaseDelay,
		maxDelay:   defaultMaxDelay,
	}
}

func (r *RetryProvider) Name() string                    { return r.inner.Name() }
func (r *RetryProvider) Configure(cfg Config) error      { return r.inner.Configure(cfg) }
func (r *RetryProvider) Configured() bool                { return r.inner.Configured() }

func (r *RetryProvider) Stream(ctx context.Context, messages []Message, tools []ToolDef) (<-chan StreamChunk, error) {
	var lastErr error

	for attempt := 0; attempt <= r.maxRetries; attempt++ {
		if attempt > 0 {
			delay := r.backoffDelay(attempt)
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(delay):
			}
		}

		ch, err := r.inner.Stream(ctx, messages, tools)
		if err == nil {
			return ch, nil
		}

		lastErr = err
		if !isRetryable(err) {
			return nil, err
		}
	}

	return nil, fmt.Errorf("after %d retries: %w", r.maxRetries, lastErr)
}

func (r *RetryProvider) backoffDelay(attempt int) time.Duration {
	delay := time.Duration(float64(r.baseDelay) * math.Pow(2, float64(attempt-1)))
	if delay > r.maxDelay {
		delay = r.maxDelay
	}
	return delay
}

// isRetryable returns true for transient errors that are worth retrying.
func isRetryable(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()

	// Rate limiting.
	if strings.Contains(msg, "429") || strings.Contains(msg, "rate") {
		return true
	}
	// Server errors.
	if strings.Contains(msg, "500") || strings.Contains(msg, "502") ||
		strings.Contains(msg, "503") || strings.Contains(msg, "504") {
		return true
	}
	// Network errors.
	if strings.Contains(msg, "connection refused") || strings.Contains(msg, "connection reset") ||
		strings.Contains(msg, "timeout") || strings.Contains(msg, "EOF") {
		return true
	}
	// Overloaded.
	if strings.Contains(msg, "overloaded") || strings.Contains(msg, "capacity") {
		return true
	}

	return false
}

// NewHTTPClient creates an http.Client with appropriate timeouts for LLM streaming.
func NewHTTPClient() *http.Client {
	return &http.Client{
		Timeout: defaultHTTPTimeout,
		Transport: &http.Transport{
			MaxIdleConns:        10,
			MaxIdleConnsPerHost: 5,
			IdleConnTimeout:     90 * time.Second,
		},
	}
}
