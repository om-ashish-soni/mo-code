# ISSUE-004: Missing Tests for Backend Entrypoint

## Status
Low

## Description
The main entrypoint package `backend/cmd/mocode` contains `main.go` but has no corresponding test files.

## Evidence
- `ls backend/cmd/mocode/` only shows `main.go`.
- `scripts/test.sh` output shows `? mo-code/backend/cmd/mocode [no test files]`.

## Impact
Key logic in the daemon startup sequence (port selection, signal handling) is not covered by automated tests.
