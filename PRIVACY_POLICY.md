# Privacy Policy — mo-code

**Last updated:** April 12, 2026

## Overview

mo-code is a mobile AI coding agent that runs locally on your device. We are committed to protecting your privacy. This policy explains what data mo-code handles and how.

## Data Collection

mo-code does **not** collect, store, or transmit any personal data to our servers. We do not operate any backend servers — the app runs entirely on your device.

## How the App Works

mo-code runs a local agent runtime on your Android device. The app communicates with this local runtime over localhost (127.0.0.1). No data leaves your device except for API calls to your chosen AI provider.

## Third-Party AI Providers

When you use mo-code, your prompts and code context are sent to the AI provider you configure:

- **Anthropic (Claude)** — Subject to [Anthropic's Privacy Policy](https://www.anthropic.com/privacy)
- **Google (Gemini)** — Subject to [Google's Privacy Policy](https://policies.google.com/privacy)
- **GitHub Copilot** — Subject to [GitHub's Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)

You choose which provider to use and provide your own API keys or authentication. mo-code does not intermediate, log, or store these API communications.

## Data Stored on Device

mo-code stores the following data locally on your device:

- **API keys** — Stored in the app's private storage (shared_preferences). These never leave your device except when sent to the respective AI provider API.
- **Session history** — Past conversations and coding sessions are stored locally.
- **Configuration** — Your preferences, working directory, and provider settings.

All local data is stored in the app's private directory (`~/.mocode/`) and is not accessible to other apps.

## Permissions

mo-code requests the following Android permissions:

- **Internet** — To communicate with AI provider APIs.
- **Microphone** — For optional voice input (speech-to-text). Audio is processed on-device and is not recorded or transmitted.
- **Storage** — To read and write code files in your project directory.

## Children's Privacy

mo-code is not directed at children under 13. We do not knowingly collect information from children.

## Changes to This Policy

We may update this policy from time to time. Changes will be posted in the app's repository.

## Contact

For questions about this privacy policy, open an issue at: https://github.com/om-ashish-soni/mo-code/issues
