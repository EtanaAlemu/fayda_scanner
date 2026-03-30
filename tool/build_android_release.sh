#!/usr/bin/env bash
# Release builds with Dart obfuscation + split debug info + smallest APKs (per-ABI).
# Symbols go to ./symbols — back up for crash de-obfuscation; do not commit.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYMBOLS="${SYMBOLS_DIR:-$ROOT/symbols}"
mkdir -p "$SYMBOLS"
cd "$ROOT"

echo "==> Symbols directory: $SYMBOLS"
echo "==> Building App Bundle (Play Store)..."
flutter build appbundle \
  --release \
  --obfuscate \
  --split-debug-info="$SYMBOLS" \
  --tree-shake-icons

echo "==> Building split APKs (one ABI per file — smallest install size)..."
flutter build apk \
  --release \
  --obfuscate \
  --split-debug-info="$SYMBOLS" \
  --split-per-abi \
  --tree-shake-icons

echo "Done."
echo "  AAB: build/app/outputs/bundle/release/app-release.aab"
echo "  APK: build/app/outputs/flutter-apk/app-*-release.apk"
