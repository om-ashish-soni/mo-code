# ISSUE-008: Missing Assets (Fonts)

## Status
Medium

## Description
The `pubspec.yaml` references `assets/fonts/JetBrainsMono-Regular.ttf` and `assets/fonts/JetBrainsMono-Bold.ttf`, but the `assets/` directory is missing from the repository.

## Evidence
- `ls -R assets/` in the flutter directory returns "No such file or directory".

## Impact
The Flutter app will fail to load or crash when trying to render text with the missing fonts.
