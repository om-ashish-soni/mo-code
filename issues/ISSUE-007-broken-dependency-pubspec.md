# ISSUE-007: Broken Dependency in pubspec.yaml

## Status
RESOLVED (2026-04-12)

## Description
The `pubspec.yaml` file in the `flutter/` directory used an incorrect package name `flutter_speech_to_text` which does not exist on pub.dev. The correct package is `speech_to_text`.

## Evidence
- `flutter pub get` failed with: "Because mo_code depends on flutter_speech_to_text ^6.6.0 which doesn't match any versions, version solving failed."

## Impact
Initial project setup and dependency resolution fail out of the box.
