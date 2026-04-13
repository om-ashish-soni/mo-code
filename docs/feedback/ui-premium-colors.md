# UI Premium Color Palette — Observations

**Date:** 2026-04-13  
**Branch:** feat/ui-premium  
**File:** `flutter/lib/theme/colors.dart`

---

## What works well

1. **Background layering (0F0F1A → 161625 → 1E1E32 → 272742)** — the 4-step depth system gives clean visual separation between panels without harsh edges. The blue undertone in the darks (1A, 25, 32, 42) feels modern vs pure-black (#000) or neutral-grey apps.

2. **Purple accent (8B7FFF)** — saturated enough to pop on the dark backgrounds, but not neon. The dim variant (3D3670) as indicator/pill background is well balanced — visible without competing with the full accent.

3. **Text hierarchy (E8E6DF → B4B2A9 → 6E6E8A → 454560)** — the warm-tinted whites (DF, A9) avoid the clinical feel of pure #CCC/#888 greys. 4 levels is the right number — primary, secondary, muted, disabled covers all cases.

4. **Semantic dim variants (greenDim, amberDim, redDim, blueDim)** — these are great for status badges and tag backgrounds. Low saturation, high readability. Follows the iOS/macOS pattern of tinted backgrounds behind colored text.

5. **Inter + JetBrains Mono pairing** — clean separation between UI and code. Inter's x-height matches well with JetBrains Mono at 13px/14px.

## Potential improvements

1. **Green (5EE0A0) might be too minty** — on the 0F0F1A background, it can feel slightly "terminal green." Consider shifting toward a warmer green like `#4ADE80` (Tailwind green-400) or `#66E0A3` for a more premium feel. Minor nit.

2. **No mid-tone surface** — the jump from `surface` (1E1E32) to `surfaceHigh` (272742) is ~9 lightness steps. If we ever need a hover state between them, there's no in-between. Could add a `surfaceMid` (~232340) later if needed.

3. **Amber (FFBE4D) reads slightly orange** on some Linux displays with default color profiles. On calibrated screens and mobile it's fine. Worth checking on target Android devices.

4. **Border colors (2A2A45, 363658)** — these are subtle, which is correct. But on some screens the `border` color almost disappears against `surface`. Could bump to ~2E2E4A if feedback says cards feel "flat."

5. **No explicit success/warning/info mapping** — green is success, amber is warning, red is error, blue is info by convention but it's not documented. Worth adding a comment block in colors.dart mapping semantic roles.

## Copilot model dropdown (provider_switcher.dart)

- Verified 7 working model keys against real API (2026-04-13)
- Removed 4 broken keys (o4-mini, o3-mini, claude-sonnet-4, claude-3.5-sonnet, gemini-2.0-flash)
- Added: gpt-5-mini, gpt-4o-mini, claude-haiku-4.5, grok-code-fast-1

## Known issue

- Linux desktop app crashes ~5s after launch ("Lost connection to device"). Backend daemon is healthy and processes WebSocket messages fine. Likely a Flutter engine/rendering issue on Linux, not a color/theme problem. Needs separate investigation.
