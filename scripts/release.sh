#!/bin/bash
# Build release AAB for Play Store upload
#
# Prerequisites:
#   1. JDK 21 installed (openjdk-21-jdk, not just JRE)
#   2. Flutter SDK installed and on PATH
#   3. Keystore generated (one-time):
#        cd flutter
#        keytool -genkey -v -keystore mocode-release.keystore -alias mocode \
#          -keyalg RSA -keysize 2048 -validity 10000
#   4. flutter/android/key.properties created with:
#        storePassword=<password>
#        keyPassword=<password>
#        keyAlias=mocode
#        storeFile=../../mocode-release.keystore
#      NOTE: storeFile is relative to flutter/android/app/ (where build.gradle.kts lives),
#            so ../../ points back to flutter/ where the keystore lives.
#
# Output:
#   flutter/build/app/outputs/bundle/release/app-release.aab
#
# Usage:
#   ./scripts/release.sh           # full clean build
#   ./scripts/release.sh --quick   # skip clean + analysis

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FLUTTER_DIR="$PROJECT_DIR/flutter"
ANDROID_DIR="$FLUTTER_DIR/android"
QUICK=false

if [ "$1" = "--quick" ]; then
    QUICK=true
fi

echo "=== Mo-Code Release Build ==="
echo ""

# Pre-flight checks
ERRORS=0

if ! command -v flutter &> /dev/null; then
    echo "✗ Flutter SDK not found"
    ERRORS=$((ERRORS + 1))
else
    echo "✓ Flutter: $(flutter --version 2>&1 | head -1)"
fi

if ! command -v javac &> /dev/null; then
    echo "✗ javac not found — install openjdk-21-jdk (not just JRE)"
    ERRORS=$((ERRORS + 1))
else
    echo "✓ javac: $(javac -version 2>&1)"
fi

if [ ! -d "$FLUTTER_DIR" ]; then
    echo "✗ flutter/ directory not found"
    ERRORS=$((ERRORS + 1))
else
    echo "✓ Flutter project: $FLUTTER_DIR"
fi

if [ ! -f "$ANDROID_DIR/key.properties" ]; then
    echo "✗ key.properties not found at $ANDROID_DIR/key.properties"
    echo "  Create it with storePassword, keyPassword, keyAlias, storeFile fields"
    ERRORS=$((ERRORS + 1))
else
    echo "✓ key.properties found"
fi

# Check that keystore file referenced in key.properties exists
if [ -f "$ANDROID_DIR/key.properties" ]; then
    STORE_FILE=$(grep "storeFile" "$ANDROID_DIR/key.properties" | cut -d= -f2 | xargs)
    if [ -n "$STORE_FILE" ]; then
        # storeFile is relative to android/app/ (where build.gradle.kts resolves it)
        STORE_PATH="$ANDROID_DIR/app/$STORE_FILE"
        if [ -f "$STORE_PATH" ]; then
            echo "✓ Keystore found: $(realpath "$STORE_PATH")"
        else
            echo "✗ Keystore not found: $STORE_PATH (resolved from storeFile=$STORE_FILE)"
            echo "  storeFile in key.properties is relative to flutter/android/app/"
            echo "  Generate keystore: cd flutter && keytool -genkey -v -keystore mocode-release.keystore -alias mocode -keyalg RSA -keysize 2048 -validity 10000"
            ERRORS=$((ERRORS + 1))
        fi
    fi
fi

# Check org.gradle.java.home is set (avoids Gradle toolchain detection bugs)
if [ -f "$ANDROID_DIR/gradle.properties" ]; then
    if grep -q "org.gradle.java.home" "$ANDROID_DIR/gradle.properties"; then
        JAVA_HOME_GRADLE=$(grep "org.gradle.java.home" "$ANDROID_DIR/gradle.properties" | cut -d= -f2 | xargs)
        if [ -d "$JAVA_HOME_GRADLE" ]; then
            echo "✓ Gradle JAVA_HOME: $JAVA_HOME_GRADLE"
        else
            echo "✗ Gradle JAVA_HOME points to missing dir: $JAVA_HOME_GRADLE"
            ERRORS=$((ERRORS + 1))
        fi
    else
        echo "⚠ org.gradle.java.home not set in gradle.properties — Gradle may fail to detect JDK"
    fi
fi

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "Fix the above $ERRORS error(s) before building."
    exit 1
fi

echo ""
cd "$FLUTTER_DIR"

# Show version being built
VERSION=$(grep "^version:" pubspec.yaml | head -1 | awk '{print $2}')
echo "Building version: $VERSION"
echo ""

if [ "$QUICK" = false ]; then
    # Clean previous build artifacts
    echo "Cleaning previous builds..."
    flutter clean
    flutter pub get

    # Run analysis before building
    echo ""
    echo "Running analysis..."
    dart analyze lib/
    echo ""
else
    echo "Quick mode — skipping clean + analysis"
    flutter pub get --offline 2>/dev/null || flutter pub get
    echo ""
fi

# Build release AAB
echo "Building release AAB..."
flutter build appbundle --release

AAB_PATH="$FLUTTER_DIR/build/app/outputs/bundle/release/app-release.aab"
if [ -f "$AAB_PATH" ]; then
    echo ""
    echo "============================================"
    echo "✓ Release AAB built successfully!"
    echo "  Path: $AAB_PATH"
    echo "  Size: $(du -h "$AAB_PATH" | cut -f1)"
    echo "  Version: $VERSION"
    echo ""
    echo "Next steps:"
    echo "  1. Go to https://play.google.com/console"
    echo "  2. Select 'mo-code' app"
    echo "  3. Release > Internal testing > Create new release"
    echo "  4. Upload the AAB file above"
    echo "  5. Add release notes and roll out"
    echo "============================================"
else
    echo ""
    echo "Error: AAB not found at expected path: $AAB_PATH"
    echo "Check build output above for errors."
    exit 1
fi
