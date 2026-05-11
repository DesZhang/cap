#!/bin/sh
set -e

echo "[entrypoint] Loading baked assets into Redis..."
bun run /usr/src/app/scripts/load-assets.js

echo "[entrypoint] Starting Cap server..."
exec bun run /usr/src/app/src/index.js
