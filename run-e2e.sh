#!/usr/bin/env bash
#
# run-e2e.sh — End-to-end integration test runner for Cap
#
# Phases:
#   1. Bootstrap  — Start Redis, Cap container, backend(s), frontend
#   2. Playwright — Run 4 browser-based widget tests, harvest tokens
#   3. API tests  — Failure scenarios with harvested tokens
#   4. Infra tests — Cap-down and wrong-secret scenarios
#   5. Teardown   — Stop everything, flush Redis
#
# Usage: ./run-e2e.sh [--skip-build] [--keep]
#   --skip-build  Skip Docker image build (reuse previous)
#   --keep        Skip teardown (leave services running for debugging)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAP_ROOT="$SCRIPT_DIR"
E2E_DIR="$CAP_ROOT/e2e"
TOKEN_FILE="/tmp/cap-e2e-tokens.json"
PID_DIR="/tmp/cap-e2e-pids"

# Test configuration
REDIS_PORT=16379
CAP_PORT=3000
BACKEND_PORT=8080
BACKEND_WRONG_SECRET_PORT=8081
FRONTEND_PORT=5173
ADMIN_KEY="test-admin-key-12345"
TOKEN_TTL_MS=10000

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[e2e]${NC} $*"; }
warn() { echo -e "${YELLOW}[e2e]${NC} $*"; }
err()  { echo -e "${RED}[e2e]${NC} $*" >&2; }

die() { err "$*"; exit 1; }

# ── Parse args ──────────────────────────────────────────────────────────
SKIP_BUILD=false
KEEP=false
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=true ;;
    --keep)       KEEP=true ;;
    *)            die "Unknown argument: $arg" ;;
  esac
done

# ── Cleanup trap ────────────────────────────────────────────────────────
cleanup() {
  if [[ "$KEEP" == "true" ]]; then
    warn "Keeping services running (--keep). Manual cleanup:"
    warn "  redis-cli -p $REDIS_PORT shutdown"
    warn "  docker stop cap-e2e"
    warn "  kill \$(cat $PID_DIR/*)"
    exit 0
  fi

  log "Phase 5: Teardown"
  
  # Kill frontend
  if [[ -f "$PID_DIR/frontend.pid" ]]; then
    kill "$(cat "$PID_DIR/frontend.pid")" 2>/dev/null || true
    rm -f "$PID_DIR/frontend.pid"
  fi

  # Kill backends
  for pid_file in "$PID_DIR"/backend*.pid; do
    [[ -f "$pid_file" ]] || continue
    kill "$(cat "$pid_file")" 2>/dev/null || true
    rm -f "$pid_file"
  done

  # Stop Cap container
  docker stop cap-e2e 2>/dev/null || true
  docker rm cap-e2e 2>/dev/null || true

  # Flush and stop Redis
  redis-cli -p "$REDIS_PORT" FLUSHALL 2>/dev/null || true
  redis-cli -p "$REDIS_PORT" shutdown NOSAVE 2>/dev/null || true

  # Cleanup temp files
  rm -f "$TOKEN_FILE"
  rm -rf "$PID_DIR"

  log "Teardown complete"
}
trap cleanup EXIT

# ── Phase 1: Bootstrap ─────────────────────────────────────────────────
log "Phase 1: Bootstrap"

mkdir -p "$PID_DIR"
rm -f "$TOKEN_FILE"

# 1a. Start Redis
log "Starting Redis on port $REDIS_PORT..."
redis-server --port "$REDIS_PORT" --daemonize yes --save "" --appendonly no --loglevel warning
REDIS_PID=$(redis-cli -p "$REDIS_PORT" CLIENT LIST 2>/dev/null | head -1 | grep -o 'fd=[0-9]*' || true)
log "Redis started"

# Wait for Redis to be ready
for i in $(seq 1 10); do
  if redis-cli -p "$REDIS_PORT" ping 2>/dev/null | grep -q PONG; then
    break
  fi
  sleep 0.5
done
redis-cli -p "$REDIS_PORT" ping | grep -q PONG || die "Redis did not start"

# 1b. Build and start Cap Docker container
if [[ "$SKIP_BUILD" == "false" ]]; then
  log "Building Cap Docker image..."
  docker build \
    -t cap-e2e:latest \
    -f "$CAP_ROOT/standalone/Dockerfile" \
    --build-arg CAP_WIDGET_VERSION=0.1.50 \
    --build-arg CAP_WASM_VERSION=0.0.7 \
    "$CAP_ROOT" 2>&1 | tail -3
  log "Docker image built"
fi

log "Starting Cap container..."
docker run -d \
  --name cap-e2e \
  -p "$CAP_PORT:$CAP_PORT" \
  -e "ADMIN_KEY=$ADMIN_KEY" \
  -e "REDIS_URL=redis://host.docker.internal:$REDIS_PORT" \
  -e "REDIS_KEY_PREFIX=cap:e2e:" \
  -e "TOKEN_TTL_MS=$TOKEN_TTL_MS" \
  -e "SHOW_ERRORS=false" \
  -e "DISABLE_ERROR_LOGGING=false" \
  -e "DEMO_MODE=false" \
  -e "SERVER_PORT=$CAP_PORT" \
  --add-host=host.docker.internal:host-gateway \
  cap-e2e:latest

log "Waiting for Cap to be healthy..."
for i in $(seq 1 30); do
  if curl -sf "http://localhost:$CAP_PORT/assets/widget.js" > /dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -sf "http://localhost:$CAP_PORT/assets/widget.js" > /dev/null \
  || die "Cap container did not become healthy"

log "Cap container is healthy"

# 1c. Register site key via Cap admin API
log "Registering site key via admin API..."

# Login to get session token
LOGIN_RESPONSE=$(curl -sf \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{\"admin_key\":\"$ADMIN_KEY\"}" \
  "http://localhost:$CAP_PORT/auth/login") \
  || die "Admin login failed"

SESSION_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['session_token'])")
HASHED_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['hashed_token'])")

# Construct Bearer token: base64 of {"token":"...","hash":"..."}
BEARER_PAYLOAD=$(python3 -c "
import json, base64
payload = json.dumps({'token': '$SESSION_TOKEN', 'hash': '$HASHED_TOKEN'})
print(base64.b64encode(payload.encode()).decode())
")

# Create site key
KEY_RESPONSE=$(curl -sf \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $BEARER_PAYLOAD" \
  -d '{"name":"e2e-test"}' \
  "http://localhost:$CAP_PORT/server/keys") \
  || die "Site key registration failed"

SITE_KEY=$(echo "$KEY_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['siteKey'])")
SECRET_KEY=$(echo "$KEY_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['secretKey'])")

log "Site key registered: $SITE_KEY"

# 1d. Build backend (if not already built)
BACKEND_JAR="$CAP_ROOT/backend/target/backend-0.0.1-SNAPSHOT.jar"
if [[ ! -f "$BACKEND_JAR" ]]; then
  log "Building backend..."
  mvn -f "$CAP_ROOT/backend/pom.xml" package -DskipTests -q 2>&1 | tail -3
  log "Backend built"
fi

# 1e. Start backend on :8080 (correct secret)
log "Starting backend on port $BACKEND_PORT..."
java -jar "$BACKEND_JAR" \
  --server.port="$BACKEND_PORT" \
  --cap.instance-url="http://localhost:$CAP_PORT" \
  --cap.site-key="$SITE_KEY" \
  --cap.secret-key="$SECRET_KEY" \
  --cap.cors-origins="http://localhost:$FRONTEND_PORT" \
  > /tmp/cap-e2e-backend.log 2>&1 &
echo $! > "$PID_DIR/backend.pid"

# 1f. Start second backend on :8081 (wrong secret for wrong-secret test)
log "Starting wrong-secret backend on port $BACKEND_WRONG_SECRET_PORT..."
java -jar "$BACKEND_JAR" \
  --server.port="$BACKEND_WRONG_SECRET_PORT" \
  --cap.instance-url="http://localhost:$CAP_PORT" \
  --cap.site-key="$SITE_KEY" \
  --cap.secret-key="sk-wrong-secret-key-for-testing" \
  --cap.cors-origins="http://localhost:$FRONTEND_PORT" \
  > /tmp/cap-e2e-backend-wrong.log 2>&1 &
echo $! > "$PID_DIR/backend-wrong.pid"

# Wait for backends to be healthy
log "Waiting for backends to be healthy..."
for i in $(seq 1 30); do
  STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" -d '{}' \
    "http://localhost:$BACKEND_PORT/api/cap/verify" 2>/dev/null || echo "000")
  if [[ "$STATUS" == "400" ]]; then
    break
  fi
  sleep 1
done
[[ "$STATUS" == "400" ]] || die "Backend on :$BACKEND_PORT did not start"

for i in $(seq 1 30); do
  STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" -d '{}' \
    "http://localhost:$BACKEND_WRONG_SECRET_PORT/api/cap/verify" 2>/dev/null || echo "000")
  if [[ "$STATUS" == "400" ]]; then
    break
  fi
  sleep 1
done
[[ "$STATUS" == "400" ]] || die "Wrong-secret backend on :$BACKEND_WRONG_SECRET_PORT did not start"

log "Backends are healthy"

# 1g. Start frontend
log "Starting frontend on port $FRONTEND_PORT..."
cd "$CAP_ROOT/frontend"
VITE_CAP_SITE_KEY="$SITE_KEY" npx vite --port "$FRONTEND_PORT" > /tmp/cap-e2e-frontend.log 2>&1 &
echo $! > "$PID_DIR/frontend.pid"
cd "$CAP_ROOT"

# Wait for frontend to be ready
for i in $(seq 1 20); do
  if curl -sf "http://localhost:$FRONTEND_PORT" > /dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -sf "http://localhost:$FRONTEND_PORT" > /dev/null \
  || die "Frontend did not start"

log "Frontend is healthy"
log "Phase 1 complete — all services running"

# ── Phase 2: Playwright tests ──────────────────────────────────────────
log "Phase 2: Playwright tests (4 widget modes)"

cd "$E2E_DIR"
npx playwright test --reporter=list 2>&1
PLAYWRIGHT_EXIT=$?
cd "$CAP_ROOT"

if [[ "$PLAYWRIGHT_EXIT" -ne 0 ]]; then
  err "Playwright tests failed (exit $PLAYWRIGHT_EXIT)"
  exit "$PLAYWRIGHT_EXIT"
fi

log "Phase 2 complete — all Playwright tests passed"

# Check that we harvested tokens
if [[ ! -f "$TOKEN_FILE" ]]; then
  die "No tokens harvested from Playwright tests"
fi

TOKEN_COUNT=$(python3 -c "import json; print(len(json.load(open('$TOKEN_FILE'))))")
log "Harvested $TOKEN_COUNT tokens"
[[ "$TOKEN_COUNT" -ge 1 ]] || die "Need at least 1 harvested token for failure tests"

# ── Phase 3: API failure tests ─────────────────────────────────────────
log "Phase 3: API failure tests"

BACKEND_URL="http://localhost:$BACKEND_PORT/api/cap/verify"
PASS=0
FAIL=0

assert_status() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    log "  ✓ $description → $actual"
    ((PASS++))
  else
    err "  ✗ $description → expected $expected, got $actual"
    ((FAIL++))
  fi
}

# 3a. Empty token → 400
STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -X POST -H "Content-Type: application/json" \
  -d '{"token":""}' \
  "$BACKEND_URL" 2>/dev/null || true)
assert_status "Empty token" "400" "$STATUS"

# 3b. Null/missing token → 400
STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -X POST -H "Content-Type: application/json" \
  -d '{}' \
  "$BACKEND_URL" 2>/dev/null || true)
assert_status "Null token (missing field)" "400" "$STATUS"

# 3c. Fabricated token → 401
STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -X POST -H "Content-Type: application/json" \
  -d '{"token":"fake-token-12345:not-real:abc"}' \
  "$BACKEND_URL" 2>/dev/null || true)
assert_status "Fabricated token" "401" "$STATUS"

# 3d. Replay harvested token → 401
FIRST_TOKEN=$(python3 -c "import json; print(json.load(open('$TOKEN_FILE'))[0]['token'])")
STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -X POST -H "Content-Type: application/json" \
  -d "{\"token\":\"$FIRST_TOKEN\"}" \
  "$BACKEND_URL" 2>/dev/null || true)
assert_status "Replayed token" "401" "$STATUS"

# 3e. Expired token → 401
# Use an unconsumed token (never sent to backend verify, so still in Redis).
# With TOKEN_TTL_MS=10000 (10s), waiting 12s ensures it's expired in Redis.
EXPIRED_TOKEN=$(python3 -c "
import json
tokens = json.load(open('$TOKEN_FILE'))
unconsumed = [t for t in tokens if not t.get('consumed', True)]
if unconsumed:
    print(unconsumed[0]['token'])
else:
    print('')
" 2>/dev/null || echo '')

if [[ -n "$EXPIRED_TOKEN" ]]; then
  log "  Waiting 12s for token expiry (TTL=${TOKEN_TTL_MS}ms)..."
  sleep 12
  STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    -d "{\"token\":\"$EXPIRED_TOKEN\"}" \
    "$BACKEND_URL" 2>/dev/null || true)
  assert_status "Expired token" "401" "$STATUS"
else
  warn "  Skipping expiry test — no unconsumed token harvested"
fi

log "Phase 3 complete: $PASS passed, $FAIL failed"

# ── Phase 4: Infrastructure failure tests ───────────────────────────────
log "Phase 4: Infrastructure failure tests"

# 4a. Cap service down → 503
log "  Stopping Cap container..."
docker stop cap-e2e > /dev/null 2>&1

# Send a real-format token to backend — backend will retry and fail
STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -X POST -H "Content-Type: application/json" \
  -d "{\"token\":\"$SITE_KEY:aaaaaaaaaaaaaaaa:bbbbbbbbbbbbbbbbbbbbbbb\"}" \
  "$BACKEND_URL" 2>/dev/null || true)
assert_status "Cap service down" "503" "$STATUS"

# Restart Cap for cleanup (even though teardown will stop it)
docker start cap-e2e > /dev/null 2>&1 || true

# 4b. Wrong secret → 401
# Cap validates the secret BEFORE checking the token.
# A wrong secret will fail even with a real-format token.
# No need for Cap to be running for this — actually we DO need Cap since the backend calls it.
# Restart Cap.
log "  Restarting Cap for wrong-secret test..."
docker start cap-e2e > /dev/null 2>&1
for i in $(seq 1 30); do
  if curl -sf "http://localhost:$CAP_PORT/assets/widget.js" > /dev/null 2>&1; then
    break
  fi
  sleep 1
done

STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -X POST -H "Content-Type: application/json" \
  -d "{\"token\":\"$SITE_KEY:aaaaaaaaaaaaaaaa:bbbbbbbbbbbbbbbbbbbbbbb\"}" \
  "http://localhost:$BACKEND_WRONG_SECRET_PORT/api/cap/verify" 2>/dev/null || true)
assert_status "Wrong secret" "401" "$STATUS"

log "Phase 4 complete: $PASS passed, $FAIL failed"

# ── Summary ─────────────────────────────────────────────────────────────
log ""
log "========================================="
log "  E2E Test Results"
log "========================================="
log "  Playwright: 4/4 modes passed"
log "  API tests:  $PASS passed, $FAIL failed"
log "========================================="

if [[ "$FAIL" -gt 0 ]]; then
  err "$FAIL test(s) failed"
  exit 1
fi

log "All tests passed!"
exit 0
