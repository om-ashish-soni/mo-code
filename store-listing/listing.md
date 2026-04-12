# Google Play Store Listing — mo-code

## App name
mo-code

## Short description (80 chars max)
AI coding agent in your pocket — write, debug, and ship code from your phone.

## Full description (4000 chars max)
mo-code is a mobile AI coding agent that lets you write, debug, and ship code directly from your phone. Powered by Claude, Gemini, or GitHub Copilot — your choice.

Unlike cloud-based mobile code editors, mo-code runs a real coding agent runtime locally on your device. It reads your files, runs shell commands, uses git, and writes code — just like a desktop AI coding tool, but in your pocket.

KEY FEATURES

• Multi-provider AI — Switch between Claude (Anthropic), Gemini (Google), and GitHub Copilot. Use whichever model fits your task.

• GitHub Copilot without API keys — Authenticate with your GitHub account using device auth flow. No API keys or subscriptions beyond what you already have.

• Terminal-style UI — Familiar command-line interface with syntax-highlighted output. JetBrains Mono font for readable code.

• Slash commands — /model, /provider, /stop, /clear, /session and more for quick control without leaving the conversation.

• File browser — Browse and navigate your project files directly in the app.

• Task history — Review past coding sessions and pick up where you left off.

• Stop button — Interrupt long-running agent tasks instantly.

• Local-first architecture — The agent runtime runs on localhost. Your code stays on your device. No files are sent to external servers beyond the AI provider API calls.

ARCHITECTURE

mo-code pairs a Flutter mobile frontend with a Go-based agent runtime (powered by OpenCode). Communication happens over HTTP and SSE on localhost. The agent has access to your local filesystem, shell, and git — enabling real coding workflows, not just chat.

IDEAL FOR

• Reviewing and fixing code on the go
• Quick bug fixes from your phone
• Prototyping ideas when away from your desk
• Learning to code with AI assistance

SUPPORTED AI PROVIDERS

• Anthropic Claude (API key required)
• Google Gemini (API key required)
• GitHub Copilot (free with GitHub account)

## Category
Developer Tools

## Tags
coding, AI, developer tools, terminal, code editor, programming, GitHub Copilot, Claude, Gemini

## Content rating
Everyone
