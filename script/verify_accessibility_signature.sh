#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:-dist/Codex Touch Bar.app}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "app bundle not found: $APP_BUNDLE" >&2
  exit 2
fi

SIGNING_DETAILS="$(codesign -d --verbose=4 --requirements - "$APP_BUNDLE" 2>&1)"

if [[ "$SIGNING_DETAILS" == *"Signature=adhoc"* ]]; then
  echo "accessibility identity is unstable: app is ad-hoc signed" >&2
  exit 1
fi

if [[ "$SIGNING_DETAILS" == *"TeamIdentifier=not set"* ]]; then
  echo "accessibility identity is unstable: signing team is missing" >&2
  exit 1
fi

if [[ "$SIGNING_DETAILS" == *'designated => cdhash '* ]]; then
  echo "accessibility identity is unstable: requirement is tied to one build hash" >&2
  exit 1
fi

echo "accessibility identity is stable"
