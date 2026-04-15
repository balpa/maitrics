#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Maitrics"

# Kill running instance if any
pkill -x "$APP_NAME" 2>/dev/null || true

"$SCRIPT_DIR/build-app.sh" "${1:-debug}"
open "$ROOT_DIR/dist/$APP_NAME.app"
