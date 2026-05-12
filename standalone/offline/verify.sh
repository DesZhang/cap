#!/bin/bash
# ── Cap Offline — 生产环境部署验证脚本 ────────────────────
#
# 在生产环境部署后运行，验证 Cap 服务各项功能是否正常。
# 使用前请确保已配置 .env 文件。
#
# 用法: bash verify.sh
# 环境变量: 从 .env 文件读取

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 加载 .env
if [ -f "$SCRIPT_DIR/.env" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
elif [ -f "$SCRIPT_DIR/../.env" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/../.env"
fi

# 从 docker-compose.yml 读取版本
CAP_VERSION="${CAP_VERSION:-$(grep 'cap-offline:' "$SCRIPT_DIR/docker-compose.yml" | sed 's/.*cap-offline:\([^"]*\).*/\1/' | head -1)}"
BASE_PATH="${BASE_PATH:-/cap}"
CAP_PORT="${CAP_PORT:-3000}"
CAP_URL="http://localhost:${CAP_PORT}"
ADMIN_KEY="${ADMIN_KEY:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓ $1${NC}"; }
fail() { echo -e "  ${RED}✗ $1${NC}"; FAILED=1; }
info() { echo -e "  ${BLUE}→ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠ $1${NC}"; }

FAILED=0
TOTAL=0
PASSED=0

check() {
  TOTAL=$((TOTAL + 1))
}

echo ""
echo "══════════════════════════════════════════"
echo "  Cap Offline 部署验证  v${CAP_VERSION}"
echo "══════════════════════════════════════════"
echo ""

# ── Step 1: 检查 Docker 镜像 ──────────────────────────────
info "[1/7] 检查 Docker 镜像..."
check
if docker images "cap-offline:${CAP_VERSION}" --format "{{.Repository}}:{{.Tag}}" | grep -q "cap-offline" 2>/dev/null; then
  pass "镜像 cap-offline:${CAP_VERSION} 已加载"
  PASSED=$((PASSED + 1))
else
  fail "镜像 cap-offline:${CAP_VERSION} 未找到"
  echo "  请先运行: docker load < cap-image.tar"
fi

# ── Step 2: 检查环境配置 ──────────────────────────────────
info "[2/7] 检查环境配置..."
check
if [ -z "$ADMIN_KEY" ]; then
  fail "ADMIN_KEY 未配置"
else
  pass "ADMIN_KEY 已配置"
  PASSED=$((PASSED + 1))
fi
check
if [ -z "${REDIS_CLUSTER_URLS:-}" ]; then
  fail "REDIS_CLUSTER_URLS 未配置"
else
  pass "REDIS_CLUSTER_URLS 已配置 (${REDIS_CLUSTER_URLS%%,*}...)"
  PASSED=$((PASSED + 1))
fi

# ── Step 3: 启动服务 ──────────────────────────────────────
info "[3/7] 启动 Cap 服务..."
check
cd "$SCRIPT_DIR"
if docker compose ps cap 2>/dev/null | grep -q "Up\|running"; then
  pass "Cap 服务已在运行"
  PASSED=$((PASSED + 1))
else
  docker compose up -d 2>&1
  # 等待就绪
  READY=false
  for i in $(seq 1 30); do
    if curl -sf "${CAP_URL}${BASE_PATH}/" > /dev/null 2>&1; then
      READY=true
      break
    fi
    sleep 1
  done
  if [ "$READY" = true ]; then
    pass "Cap 服务启动成功"
    PASSED=$((PASSED + 1))
  else
    fail "Cap 服务未在 30 秒内就绪"
    echo "  查看日志: docker compose logs cap --tail 50"
  fi
fi

# ── Step 4: 测试离线静态资源 ──────────────────────────────
info "[4/7] 测试离线静态资源（确认无 CDN 依赖）..."
for asset in widget.js floating.js cap_wasm.js cap_wasm_bg.wasm; do
  check
  HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" "${CAP_URL}${BASE_PATH}/assets/${asset}" 2>/dev/null) || HTTP_CODE="000"
  if [ "$HTTP_CODE" = "200" ]; then
    pass "  ${asset}"
    PASSED=$((PASSED + 1))
  else
    fail "  ${asset} (HTTP ${HTTP_CODE})"
  fi
done

# ── Step 5: 测试 Challenge API ────────────────────────────
info "[5/7] 测试 Challenge API..."
check
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "${CAP_URL}${BASE_PATH}/nonexistent-sitekey/challenge" 2>/dev/null) || HTTP_CODE="000"
if [ "$HTTP_CODE" = "404" ]; then
  pass "Challenge API 正常 (404 for invalid siteKey)"
  PASSED=$((PASSED + 1))
else
  fail "Challenge API 异常 (HTTP ${HTTP_CODE})"
fi

# ── Step 6: 测试管理员登录 ────────────────────────────────
info "[6/7] 测试管理后台..."
check
LOGIN_RESP=$(curl -sf -X POST "${CAP_URL}${BASE_PATH}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"admin_key\":\"${ADMIN_KEY}\"}" 2>/dev/null) || LOGIN_RESP=""
if echo "$LOGIN_RESP" | grep -q '"success":true'; then
  pass "管理后台登录成功"
  PASSED=$((PASSED + 1))
else
  fail "管理后台登录失败"
  echo "  请检查 .env 中 ADMIN_KEY 是否正确"
fi

# ── Step 7: 检查 Geo DB ──────────────────────────────────
info "[7/7] 检查 IP 地理数据库..."
check
LOGS=$(docker compose logs cap 2>/dev/null) || LOGS=""
if echo "$LOGS" | grep -q "\[ipdb\]" 2>/dev/null; then
  pass "IP 地理数据库已加载"
  PASSED=$((PASSED + 1))
elif echo "$LOGS" | grep -q "ipdb" 2>/dev/null; then
  warn "IP 地理数据库状态不确定，请检查日志"
  PASSED=$((PASSED + 1))
else
  fail "未检测到 IP 地理数据库加载记录"
  echo "  查看日志: docker compose logs cap | grep ipdb"
fi

# ── 结果 ──────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo "  验证结果: ${PASSED}/${TOTAL} 通过"
echo "══════════════════════════════════════════"
echo ""

if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}所有检查通过，Cap 服务部署成功！${NC}"
  echo ""
  echo "下一步："
  echo "  1. 参考 integration-guide.md 集成到网站"
  echo "  2. 配置反向代理（参考 deploy-guide.md）"
  echo "  3. 访问管理后台: ${CAP_URL}${BASE_PATH}/"
  echo ""
  exit 0
else
  echo -e "${RED}部分检查未通过，请根据上述提示排查。${NC}"
  echo ""
  echo "常见问题："
  echo "  - 镜像未加载: docker load < cap-image.tar"
  echo "  - Redis 不可达: 检查 REDIS_CLUSTER_URLS 配置和网络连通性"
  echo "  - 端口冲突: 修改 .env 中 CAP_PORT"
  echo "  - 查看完整日志: docker compose logs cap"
  echo ""
  exit 1
fi
