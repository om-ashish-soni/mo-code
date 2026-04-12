package context

import (
	"context"
	"fmt"
	"strings"

	"mo-code/backend/provider"
)

const (
	// compactionThreshold is the fraction of maxTokens at which compaction triggers.
	compactionThreshold = 0.80
	// compactionProtectRecent is how many recent messages to preserve verbatim.
	compactionProtectRecent = 4
)

// compactionPrompt is the system prompt for the compaction agent.
const compactionPrompt = `You are a summarization assistant. Your job is to provide a detailed summary of a conversation for continuing in a new context window.

Provide a detailed prompt for continuing the conversation. Focus on:
- What was accomplished so far
- What is currently being worked on
- Which files were read, modified, or created
- Any errors encountered and how they were resolved
- What the next steps should be

Be specific about file paths, function names, and technical details. The summary should allow someone to seamlessly continue the work.

Do NOT include tool calls or code blocks — just a concise narrative summary.`

// Compactor handles conversation compaction when context grows too large.
type Compactor struct {
	provider provider.Provider
}

// NewCompactor creates a Compactor that uses the given provider for summarization.
func NewCompactor(p provider.Provider) *Compactor {
	return &Compactor{provider: p}
}

// ShouldCompact returns true if the manager's context exceeds the compaction threshold.
func (c *Compactor) ShouldCompact(mgr *Manager) bool {
	mgr.mu.RLock()
	defer mgr.mu.RUnlock()
	threshold := int(float64(mgr.maxTokens) * compactionThreshold)
	return mgr.usedTokens+systemPromptReserve > threshold
}

// Compact summarizes older messages and replaces them with a summary,
// preserving the most recent messages verbatim.
func (c *Compactor) Compact(ctx context.Context, mgr *Manager) error {
	mgr.mu.Lock()
	msgCount := len(mgr.messages)
	if msgCount <= compactionProtectRecent {
		mgr.mu.Unlock()
		return nil // Nothing to compact.
	}

	// Split: older messages to summarize, recent to keep.
	older := make([]provider.Message, len(mgr.messages[:msgCount-compactionProtectRecent]))
	copy(older, mgr.messages[:msgCount-compactionProtectRecent])
	recent := make([]provider.Message, len(mgr.messages[msgCount-compactionProtectRecent:]))
	copy(recent, mgr.messages[msgCount-compactionProtectRecent:])
	mgr.mu.Unlock()

	// Build a conversation transcript for summarization.
	var transcript strings.Builder
	for _, msg := range older {
		role := string(msg.Role)
		transcript.WriteString(fmt.Sprintf("[%s]: %s\n", role, truncateForSummary(msg.Content, 500)))
		for _, tc := range msg.ToolCalls {
			transcript.WriteString(fmt.Sprintf("  tool_call: %s(%s)\n", tc.Name, truncateForSummary(tc.Args, 100)))
		}
	}

	// Ask the LLM to summarize.
	summaryMsgs := []provider.Message{
		{Role: provider.RoleSystem, Content: compactionPrompt},
		{Role: provider.RoleUser, Content: fmt.Sprintf("Summarize this conversation:\n\n%s", transcript.String())},
	}

	streamCh, err := c.provider.Stream(ctx, summaryMsgs, nil)
	if err != nil {
		return fmt.Errorf("compaction stream: %w", err)
	}

	var summary strings.Builder
	for chunk := range streamCh {
		if chunk.Text != "" {
			summary.WriteString(chunk.Text)
		}
	}

	if summary.Len() == 0 {
		return fmt.Errorf("compaction produced empty summary")
	}

	// Replace older messages with the summary + continuation preamble.
	continuationMsg := provider.Message{
		Role: provider.RoleUser,
		Content: fmt.Sprintf(`This session is being continued from a previous conversation that ran out of context. The summary below covers the earlier portion of the conversation.

%s

Continue the conversation from where it left off without asking the user any further questions. Resume directly — do not acknowledge the summary, do not recap what was happening.`, summary.String()),
	}

	mgr.mu.Lock()
	defer mgr.mu.Unlock()

	// Recalculate tokens.
	newMessages := append([]provider.Message{continuationMsg}, recent...)
	var newUsed int
	for _, msg := range newMessages {
		newUsed += mgr.estimateTokens(msg)
	}
	mgr.messages = newMessages
	mgr.usedTokens = newUsed

	return nil
}

// truncateForSummary truncates a string to maxChars for the compaction transcript.
func truncateForSummary(s string, maxChars int) string {
	if len(s) <= maxChars {
		return s
	}
	return s[:maxChars] + "..."
}
