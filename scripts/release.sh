#!/bin/bash
# Build release AAB for Play Store upload
#
# Prerequisites:
#   1. Generate keystore:
#      keytool -genkey -v -keystore mocode-release.keystore -alias mocode \
#        -keyalg RSA -keysize 2048 -validity 10000
#   2. Create flutter/android/key.properties from key.properties.example
#   3. Flutter SDK installed

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FLUTTER_DIR="$PROJECT_DIR/flutter"
ANDROID_DIR="$FLUTTER_DIR/android"

echo "=== Mo-Code Release Build ==="
echo ""

# Pre-flight checks
ERRORS=0

if ! command -v flutter &> /dev/null; then
    echo "✗ Flutter SDK not found"
    ERRORS=$((ERRORS + 1))
else
    echo "✓ Flutter: $(flutter --version | head -1)"
fi

if [ ! -d "$FLUTTER_DIR" ]; then
    echo "✗ flutter/ directory not found"
    ERRORS=$((ERRORS + 1))
else
    echo "✓ Flutter project: $FLUTTER_DIR"
fi

if [ ! -f "$ANDROID_DIR/key.properties" ]; then
    echo "✗ key.properties not found at $ANDROID_DIR/key.properties"
    echo "  Copy from key.properties.example and fill in your keystore credentials"
    ERRORS=$((ERRORS + 1))
else
    echo "✓ key.properties found"
fi

# Check that keystore file referenced in key.properties exists
if [ -f "$ANDROID_DIR/key.properties" ]; then
    STORE_FILE=$(grep "storeFile" "$ANDROID_DIR/key.properties" | cut -d= -f2 | xargs)
    if [ -n "$STORE_FILE" ]; then
        # Resolve relative path from android/ directory
        STORE_PATH="$ANDROID_DIR/$STORE_FILE"
        if [ -f "$STORE_PATH" ]; then
            echo "✓ Keystore found: $STORE_PATH"
        else
            echo "✗ Keystore not found: $STORE_PATH"
            echo "  Generate with: keytool -genkey -v -keystore $STORE_PATH -alias mocode -keyalg RSA -keysize 2048 -validity 10000"
            ERRORS=$((ERRORS + 1))
        fi
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

# Clean previous build artifacts
echo "Cleaning previous builds..."
flutter clean
flutter pub get

# Run analysis before building
echo ""
echo "Running analysis..."
dart analyze lib/
echo ""

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
    echo "  4. Upload $AAB_PATH"
    echo "  5. Add release notes and roll out"
    echo "============================================"
else
    echo ""
    echo "Error: AAB not found at expected path: $AAB_PATH"
    echo "Check build output above for errors."
    exit 1
fi
