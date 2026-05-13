#!/bin/bash
# ── Cap Offline — 构建时冒烟测试 ──────────────────────────
#
# 在 build-package.sh 中自动调用，验证构建产物基本可用。
# 使用 docker-compose.test.yml 启动 Cap 容器，连接宿主机本地 Redis 集群。
#
# 用法: VERSION=3.1.0 bash smoke-test.sh
# 环境变量:
#   VERSION            - Cap 版本号（默认读取 package.json）
#   TEST_PORT          - 映射到宿主机的测试端口（默认 13000）
#   REDIS_CLUSTER_HOST - Redis 集群宿主机 IP（默认自动检测）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${VERSION:-$(grep '"version"' "$SCRIPT_DIR/../../package.json" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')}"
TEST_PORT="${TEST_PORT:-13000}"
CAP_URL="http://localhost:${TEST_PORT}"
ADMIN_KEY="test_admin_key_for_smoke"
COMPOSE_PROJECT="cap-smoke-test"

# Detect host IP for Redis cluster (macOS / Linux)
HOST_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')"
export REDIS_CLUSTER_HOST="${REDIS_CLUSTER_HOST:-$HOST_IP}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓ $1${NC}"; }
fail() { echo -e "  ${RED}✗ $1${NC}"; FAILED=1; }
info() { echo -e "  ${YELLOW}→ $1${NC}"; }

FAILED=0

cleanup() {
  if [ "$FAILED" -eq 1 ] || [ "${CLEANUP:-1}" -eq 1 ]; then
    info "清理测试容器..."
    cd "$SCRIPT_DIR"
    docker compose -f docker-compose.test.yml -p "$COMPOSE_PROJECT" down --remove-orphans 2>/dev/null || true
    info "停止本地 Redis 集群..."
    bash "$SCRIPT_DIR/scripts/mock-redis-cluster.sh" stop 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo ""
echo "══════════════════════════════════════════"
echo "  Cap Offline 冒烟测试  v${VERSION}"
echo "══════════════════════════════════════════"
echo ""

# ── Step 0: 启动本地 Redis 集群 ───────────────────────────
info "[0/8] 启动本地 Redis 集群..."
bash "$SCRIPT_DIR/scripts/mock-redis-cluster.sh" start "$REDIS_CLUSTER_HOST"

# ── Step 1: 启动容器 ──────────────────────────────────────
info "[1/8] 启动测试容器..."
cd "$SCRIPT_DIR"
VERSION="$VERSION" docker compose -f docker-compose.test.yml -p "$COMPOSE_PROJECT" up -d --force-recreate --wait 2>/dev/null

# ── Step 2: 等待 Cap 服务就绪 ─────────────────────────────
info "[2/8] 等待 Cap 服务就绪..."
READY=false
for i in $(seq 1 30); do
  if curl -sf "${CAP_URL}/cap/" > /dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 1
done
if [ "$READY" = true ]; then
  pass "Cap 服务已就绪"
else
  fail "Cap 服务未在 30 秒内就绪"
  echo "  容器日志:"
  docker compose -f docker-compose.test.yml -p "$COMPOSE_PROJECT" logs cap --tail 30 2>/dev/null
  exit 1
fi

# ── Step 3: 测试离线静态资源 ──────────────────────────────
info "[3/8] 测试离线静态资源..."
ASSETS_OK=true
for asset in widget.js floating.js cap_wasm.js; do
  HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" "${CAP_URL}/cap/assets/${asset}" 2>/dev/null) || HTTP_CODE="000"
  if [ "$HTTP_CODE" = "200" ]; then
    pass "  ${asset} (${HTTP_CODE})"
  else
    fail "  ${asset} (${HTTP_CODE})"
    ASSETS_OK=false
  fi
done
# WASM (binary)
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" "${CAP_URL}/cap/assets/cap_wasm_bg.wasm" 2>/dev/null) || HTTP_CODE="000"
if [ "$HTTP_CODE" = "200" ]; then
  pass "  cap_wasm_bg.wasm (${HTTP_CODE})"
else
  fail "  cap_wasm_bg.wasm (${HTTP_CODE})"
  ASSETS_OK=false
fi

# ── Step 4: 测试前端静态资源 ──────────────────────────────
info "[4/8] 测试前端静态资源 (BASE_PATH=/cap)..."
FRONTEND_OK=true

# 无需认证的资源（字体）
for asset in assets/ibm-plex-sans.woff2 assets/lilex-regular.woff2; do
  HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" "${CAP_URL}/cap/public/${asset}" 2>/dev/null) || HTTP_CODE="000"
  if [ "$HTTP_CODE" = "200" ]; then
    pass "  ${asset} (${HTTP_CODE})"
  else
    fail "  ${asset} (${HTTP_CODE})"
    FRONTEND_OK=false
  fi
done

# 需要认证的资源：先登录获取 session cookie
LOGIN_RESP=$(curl -sf -X POST "${CAP_URL}/cap/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"admin_key\":\"${ADMIN_KEY}\"}" \
  -c /tmp/cap-smoke-cookies.txt 2>/dev/null) || LOGIN_RESP=""

if echo "$LOGIN_RESP" | grep -q '"success":true'; then
  for asset in assets/style.css js/dashboard.js assets/chart.js@4.5.0.min.js; do
    HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" -b /tmp/cap-smoke-cookies.txt "${CAP_URL}/cap/public/${asset}" 2>/dev/null) || HTTP_CODE="000"
    if [ "$HTTP_CODE" = "200" ]; then
      pass "  ${asset} (${HTTP_CODE})"
    else
      fail "  ${asset} (${HTTP_CODE})"
      FRONTEND_OK=false
    fi
  done
else
  fail "  无法登录以测试受保护的静态资源"
  FRONTEND_OK=false
fi

# ── Step 5: 测试管理员登录 ────────────────────────────────
info "[5/8] 测试管理员登录..."
if echo "$LOGIN_RESP" | grep -q '"success":true'; then
  pass "管理员登录成功"
else
  fail "管理员登录失败"
  echo "  响应: $LOGIN_RESP"
fi

# ── Step 6: 测试 Challenge API ────────────────────────────
info "[6/8] 测试 Challenge API..."
# 使用无效 siteKey，期望返回 404（证明路由正常工作）
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "${CAP_URL}/cap/nonexistent-sitekey/challenge" 2>/dev/null) || HTTP_CODE="000"
if [ "$HTTP_CODE" = "404" ]; then
  pass "Challenge API 正常响应 (404 for invalid siteKey)"
elif [ "$HTTP_CODE" = "000" ]; then
  fail "Challenge API 无响应"
else
  fail "Challenge API 异常响应 (HTTP ${HTTP_CODE})"
fi

# ── Step 7: 检查前端页面路径正确性 ────────────────────────
info "[7/8] 检查前端页面路径正确性..."

# 辅助函数：下载到临时文件后搜索内容，避免大文件管道 broken pipe
_tmpfile=""
_fetch_and_grep() {
  local url="$1"
  local pattern="$2"
  local cookie_args="${3:-}"
  _tmpfile=$(mktemp)
  if [ -n "$cookie_args" ]; then
    curl -sf "$url" -b "$cookie_args" > "$_tmpfile" 2>/dev/null || true
  else
    curl -sf "$url" > "$_tmpfile" 2>/dev/null || true
  fi
  grep -q "$pattern" "$_tmpfile"
  local rc=$?
  rm -f "$_tmpfile"
  return $rc
}

# 验证 login.html 使用相对路径而非绝对路径
if _fetch_and_grep "${CAP_URL}/cap/" 'fetch("auth/login"'; then
  pass "login.html 使用相对路径 fetch(\"auth/login\")"
else
  fail "login.html 仍使用绝对路径 (应为 fetch(\"auth/login\"))"
fi

# 验证 index.html 使用相对路径
if _fetch_and_grep "${CAP_URL}/cap/" 'src="public/assets/chart.js@4.5.0.min.js"' /tmp/cap-smoke-cookies.txt; then
  pass "index.html 使用相对路径加载 chart.js"
else
  fail "index.html 仍使用绝对路径加载 chart.js"
fi

# 验证 dashboard.js 使用相对 API 路径
if _fetch_and_grep "${CAP_URL}/cap/public/js/dashboard.js" 'fetch("server/about")' /tmp/cap-smoke-cookies.txt; then
  pass "dashboard.js 使用相对路径 fetch(\"server/about\")"
else
  fail "dashboard.js 仍使用绝对路径 (应为 fetch(\"server/about\"))"
fi

# 验证 style.css 使用相对字体路径
if _fetch_and_grep "${CAP_URL}/cap/public/assets/style.css" 'url("ibm-plex-sans.woff2")' /tmp/cap-smoke-cookies.txt; then
  pass "style.css 使用相对路径加载字体"
else
  fail "style.css 仍使用绝对路径加载字体"
fi

# ── Step 8: 检查 Geo DB 加载 ─────────────────────────────
info "[8/8] 检查 Geo DB..."
LOGS=$(docker compose -f docker-compose.test.yml -p "$COMPOSE_PROJECT" logs cap 2>/dev/null) || LOGS=""
if echo "$LOGS" | grep -q "\[ipdb\]" 2>/dev/null; then
  pass "IP 地理数据库已加载"
else
  # ipdb might not log if auto-detection hasn't triggered yet
  info "未检测到 ipdb 日志，可能需要确认 .mmdb 文件是否正确打包"
fi

# ── 结果 ──────────────────────────────────────────────────
echo ""
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}══════════════════════════════════════════"
  echo -e "  冒烟测试全部通过 ✓"
  echo -e "══════════════════════════════════════════${NC}"
  echo ""
  exit 0
else
  echo -e "${RED}══════════════════════════════════════════"
  echo -e "  冒烟测试存在失败项 ✗"
  echo -e "══════════════════════════════════════════${NC}"
  echo ""
  exit 1
fi
