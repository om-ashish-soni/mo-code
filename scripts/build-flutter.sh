#!/bin/bash
# Build Flutter app for Android

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "Building Flutter app..."

# Check if Flutter is available
if ! command -v flutter &> /dev/null; then
    echo "Flutter not found. Please install Flutter SDK."
    exit 1
fi

cd flutter

# Get dependencies
echo "Running flutter pub get..."
flutter pub get

# Build debug APK
echo "Building debug APK..."
flutter build apk --debug

echo "Done! APK location: build/app/outputs/flutter-apk/app-debug.apk"
