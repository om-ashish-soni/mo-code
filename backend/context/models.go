package context

// ModelContextLimits maps model IDs to their actual context window sizes.
// Used to set per-model token budgets instead of a flat 100K default.
var ModelContextLimits = map[string]int{
	// Claude models
	"claude-sonnet-4-20250514":    200_000,
	"claude-opus-4-20250514":      200_000,
	"claude-3-5-sonnet-20241022":  200_000,
	"claude-3-5-haiku-20241022":   200_000,

	// OpenAI / Copilot models
	"gpt-4o":                      128_000,
	"gpt-4o-mini":                 128_000,
	"gpt-4-turbo":                 128_000,
	"gpt-4":                       8_192,
	"gpt-3.5-turbo":               16_385,
	"o1":                          200_000,
	"o1-mini":                     128_000,
	"o3":                          200_000,
	"o3-mini":                     200_000,

	// Gemini models
	"gemini-2.5-pro-preview-05-06": 1_000_000,
	"gemini-2.0-flash":             1_000_000,
	"gemini-1.5-pro":               2_000_000,
	"gemini-1.5-flash":             1_000_000,
}

// DefaultModelForProvider returns the default model ID for a provider name.
// This is used to set per-model context limits when the exact model isn't known.
func DefaultModelForProvider(providerName string) string {
	switch providerName {
	case "claude":
		return "claude-sonnet-4-20250514"
	case "gemini":
		return "gemini-2.0-flash"
	case "copilot":
		return "gpt-4o"
	default:
		return ""
	}
}

// ContextLimitForModel returns the context window size for a given model ID.
// Falls back to DefaultMaxTokens if the model is not recognized.
// Returns the input budget (context limit minus a reserve for output tokens).
func ContextLimitForModel(modelID string) int {
	if limit, ok := ModelContextLimits[modelID]; ok {
		// Reserve ~20% for output tokens, matching opencode's approach.
		inputBudget := int(float64(limit) * 0.80)
		return inputBudget
	}
	return DefaultMaxTokens
}
