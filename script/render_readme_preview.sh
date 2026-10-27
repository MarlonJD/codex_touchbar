#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREVIEW_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-touchbar-preview.XXXXXX")"
trap 'rm -rf "$PREVIEW_DIR"' EXIT

swiftc -parse-as-library -module-cache-path "$ROOT_DIR/.build/module-cache" \
  "$ROOT_DIR/Sources/CodexTouchBar/TouchBarImageRenderer.swift" \
  "$ROOT_DIR/script/render_readme_preview.swift" \
  -o "$PREVIEW_DIR/render-preview"
"$PREVIEW_DIR/render-preview" "$ROOT_DIR/docs/images/touchbar-preview.png"
