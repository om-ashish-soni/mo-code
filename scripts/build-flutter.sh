#!/bin/bash
# Build Flutter app for Android (debug APK)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FLUTTER_DIR="$PROJECT_DIR/flutter"

if ! command -v flutter &> /dev/null; then
    echo "Error: Flutter not found. Please install Flutter SDK."
    exit 1
fi

if [ ! -d "$FLUTTER_DIR" ]; then
    echo "Error: flutter/ directory not found at $FLUTTER_DIR"
    exit 1
fi

cd "$FLUTTER_DIR"

echo "=== Building Flutter debug APK ==="
echo "Project: $FLUTTER_DIR"
echo ""

echo "Running flutter pub get..."
flutter pub get

echo ""
echo "Running dart analyze..."
dart analyze lib/
echo ""

echo "Building debug APK..."
flutter build apk --debug

APK_PATH="$FLUTTER_DIR/build/app/outputs/flutter-apk/app-debug.apk"
if [ -f "$APK_PATH" ]; then
    echo ""
    echo "✓ Debug APK built: $APK_PATH"
    echo "  Size: $(du -h "$APK_PATH" | cut -f1)"
else
    echo "Error: APK not found at expected path"
    exit 1
fi
