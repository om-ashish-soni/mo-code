# Play Store Deployment Guide — mo-code

## Quick Reference

| Item | Value |
|------|-------|
| Package ID | `io.github.omashishsoni.mocode` |
| Current version | `1.1.0+2` (in `flutter/pubspec.yaml`) |
| Min SDK | 24 (Android 7.0) |
| Target SDK | 35 |
| Compile SDK | 36 |
| Build script | `./scripts/release.sh` |
| AAB output | `flutter/build/app/outputs/bundle/release/app-release.aab` |
| Store listing | `store-listing/listing.md` |
| Privacy policy | `PRIVACY_POLICY.md` |

---

## First-Time Setup (one-time)

### 1. Install prerequisites

```bash
# JDK 21 (must be full JDK, not just JRE)
sudo apt install openjdk-21-jdk

# Verify javac works
javac -version

# Flutter SDK (stable channel)
flutter doctor
```

### 2. Generate signing keystore

```bash
cd flutter
keytool -genkey -v \
  -keystore mocode-release.keystore \
  -alias mocode \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```

Keep the password safe — you'll need it for every release and cannot change it.

### 3. Create key.properties

Create `flutter/android/key.properties`:

```properties
storePassword=<your-password>
keyPassword=<your-password>
keyAlias=mocode
storeFile=../../mocode-release.keystore
```

**Path gotcha:** `storeFile` is resolved relative to `flutter/android/app/` (where `build.gradle.kts` lives), not relative to `flutter/android/`. That's why it's `../../` to reach `flutter/mocode-release.keystore`.

### 4. Verify Gradle can find JDK

`flutter/android/gradle.properties` should contain:

```properties
org.gradle.java.home=/usr/lib/jvm/java-21-openjdk-amd64
```

Without this, Gradle's auto-detection may fail with a "does not provide JAVA_COMPILER" error even when `javac` works fine.

### 5. Create Play Console app

1. Go to [Google Play Console](https://play.google.com/console)
2. Create app → name: **mo-code**, free, category: **Developer Tools**
3. Complete the required setup checklist:
   - **App access**: All functionality available without special access
   - **Ads**: No ads
   - **Content rating**: Complete the questionnaire → should get **Everyone**
   - **Target audience**: 18+ (developer tool)
   - **News app**: No
   - **Data safety**: See [Data Safety section](#data-safety-answers) below
   - **Government apps**: No
4. Set up store listing:
   - Copy text from `store-listing/listing.md`
   - Upload screenshots (phone + 7-inch tablet minimum)
   - Upload 512x512 icon and 1024x500 feature graphic
5. Set privacy policy URL (host `PRIVACY_POLICY.md` somewhere, e.g. GitHub Pages)

---

## Building a Release

### Option A: Use the script

```bash
./scripts/release.sh          # full clean build
./scripts/release.sh --quick  # skip clean + analysis
```

### Option B: Manual

```bash
cd flutter
flutter clean
flutter pub get
dart analyze lib/
flutter build appbundle --release
```

Output AAB: `flutter/build/app/outputs/bundle/release/app-release.aab`

---

## Uploading to Play Store

### Internal testing (recommended first)

1. Play Console → **Release** → **Testing** → **Internal testing**
2. Click **Create new release**
3. Upload the `.aab` file
4. Add release notes, e.g.:
   ```
   v1.1.0 — Full agent platform
   - 6 AI providers (Claude, Gemini, Copilot, OpenRouter, Ollama, Azure)
   - 16 coding tools (file edit, grep, glob, shell, git, subagent)
   - Session persistence and history
   - File browser, diff viewer, task panel
   - Android foreground service for background operation
   ```
5. **Review release** → **Start rollout to Internal testing**
6. Add testers by email under **Testers** tab (up to 100)
7. Share the opt-in link with testers

### Closed/Open testing

After internal testing is stable:
1. **Testing** → **Closed testing** → Create track
2. Upload same or newer AAB
3. Broader tester group (up to 2000 for closed)

### Production release

1. **Release** → **Production** → **Create new release**
2. Upload AAB
3. Fill in release notes
4. **Review release** → **Start rollout to Production**
5. Initial rollout: start with staged rollout (e.g., 20%) if cautious

---

## Bumping Version

Edit `flutter/pubspec.yaml`:

```yaml
version: 1.2.0+3
#         ^     ^
#         |     versionCode (must increment every upload)
#         versionName (shown to users)
```

- **versionCode** (`+N`): Must be strictly higher than the previous upload. Play Store rejects equal or lower.
- **versionName** (`X.Y.Z`): Shown to users. Follow semver.

---

## Data Safety Answers

For the Play Console data safety form:

| Question | Answer |
|----------|--------|
| Does your app collect or share user data? | Yes (see below) |
| **Data collected** | |
| Personal info | No |
| Financial info | No |
| Location | No |
| App activity (prompts sent to AI) | Yes — sent to user's chosen AI provider |
| Device or other IDs | No |
| **Data shared with third parties?** | No (only sent to provider user explicitly chose) |
| **Data encrypted in transit?** | Yes (HTTPS to AI providers) |
| **Can users request data deletion?** | Yes (all data is local, user can delete the app) |
| **Is data processing required for core functionality?** | Yes (AI chat requires sending prompts to provider) |

---

## Troubleshooting

### "does not provide JAVA_COMPILER"
Gradle can't find `javac`. Install full JDK (`openjdk-21-jdk`, not `openjdk-21-jre`) and set `org.gradle.java.home` in `gradle.properties`.

### Keystore not found
`storeFile` in `key.properties` resolves from `flutter/android/app/`. Use `../../mocode-release.keystore` to point to `flutter/mocode-release.keystore`.

### compileSdk version error
Some plugins (e.g., `speech_to_text`) require higher compileSdk. Currently set to 36 in `build.gradle.kts`.

### AAB too large
Current size: ~44MB. If it grows past 150MB, consider using `--split-per-abi` for APKs or asset delivery.

---

## Files Reference

```
flutter/
  pubspec.yaml                    # version lives here
  mocode-release.keystore         # signing key (gitignored)
  android/
    key.properties                # signing config (gitignored)
    gradle.properties             # JVM args + JAVA_HOME
    app/
      build.gradle.kts            # signing, SDK versions, package ID
scripts/
  release.sh                      # automated build script
store-listing/
  listing.md                      # Play Store description text
PRIVACY_POLICY.md                 # required for Play Store
```
