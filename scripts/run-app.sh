#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$ROOT/dist/Zero-K.app" || { echo "Run ./scripts/build-app.sh first." >&2; exit 1; }
exec open -n "$ROOT/dist/Zero-K.app" --args "$@"
