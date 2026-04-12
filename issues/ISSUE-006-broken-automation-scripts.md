# ISSUE-006: Broken Automation Scripts

## Status
Critical

## Description
The script `scripts/build-flutter.sh` is broken because it assumes a `flutter/` directory exists.

## Evidence
- Line 20 of `scripts/build-flutter.sh`: `cd flutter`
- Running the script results in `No such file or directory`.

## Impact
Automated builds are impossible in the current state of the repository.
