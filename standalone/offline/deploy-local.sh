#!/bin/bash
# ── Cap Offline — 本地一键部署脚本 ─────────────────────────
#
# 用法: bash deploy-local.sh [ADMIN_KEY]
# 说明:
#   1. 查找并解压 cap-offline-*.tar.gz
#   2. 加载 Docker 镜像
#   3. 启动本地 Redis 集群（3 节点）
#   4. 生成 .env 配置
#   5. 启动 Cap 服务
#
# 前置条件:
#   - Docker 已安装并运行
#   - redis-server / redis-cli 已安装
#   - 已执行过 build-package.sh 生成离线包

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOY_DIR="${REPO_ROOT}/cap-offline-local"
ADMIN_KEY="${1:-correct-horse-battery-staple}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${YELLOW}→ $1${NC}"; }
pass()  { echo -e "${GREEN}✓ $1${NC}"; }
fail()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

# ── 1. 查找离线包 ─────────────────────────────────────────
info "查找离线包..."
PACKAGE=$(ls -t "${REPO_ROOT}"/cap-offline-*.tar.gz 2>/dev/null | head -1)
if [ -z "$PACKAGE" ]; then
  fail "未找到 cap-offline-*.tar.gz，请先运行: bash standalone/offline/build-package.sh"
fi
VERSION=$(basename "$PACKAGE" | sed 's/cap-offline-\(.*\)\.tar\.gz/\1/')
pass "找到离线包: $(basename "$PACKAGE") (版本 ${VERSION})"

# ── 2. 清理旧部署 ─────────────────────────────────────────
if [ -d "$DEPLOY_DIR" ]; then
  info "清理旧部署目录..."
  rm -rf "$DEPLOY_DIR"
fi

# ── 3. 解压离线包 ─────────────────────────────────────────
info "解压离线包到 ${DEPLOY_DIR}..."
mkdir -p "$DEPLOY_DIR"
tar -xzf "$PACKAGE" -C "$DEPLOY_DIR" --strip-components=1
pass "解压完成"

# ── 4. 加载 Docker 镜像 ───────────────────────────────────
info "加载 Docker 镜像..."
if docker images "cap-offline:${VERSION}" --format '{{.Repository}}:{{.Tag}}' | grep -q "cap-offline:${VERSION}"; then
  pass "镜像 cap-offline:${VERSION} 已存在，跳过加载"
else
  docker load < "${DEPLOY_DIR}/cap-image.tar"
  pass "镜像加载完成"
fi

# ── 5. 启动 Redis 集群 ────────────────────────────────────
info "启动本地 Redis 集群..."
bash "${SCRIPT_DIR}/scripts/mock-redis-cluster.sh" start

# ── 6. 检测宿主机 IP ──────────────────────────────────────
HOST_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')"
pass "宿主机 IP: ${HOST_IP}"

# ── 7. 生成 .env ──────────────────────────────────────────
info "生成 .env 配置..."
cat > "${DEPLOY_DIR}/.env" << EOF
# Cap Offline — 本地测试部署配置
# 自动生成于 $(date -u +"%Y-%m-%d %H:%M:%S UTC")

ADMIN_KEY=${ADMIN_KEY}
REDIS_CLUSTER_URLS=redis://${HOST_IP}:17000,redis://${HOST_IP}:17001,redis://${HOST_IP}:17002
REDIS_CLUSTER_PASSWORD=
REDIS_CLUSTER_USERNAME=
REDIS_KEY_PREFIX=cap:
RATELIMIT_IP_HEADER=X-Forwarded-For
BASE_PATH=/cap
CAP_PORT=3000
EOF
pass ".env 已生成"

# ── 8. 启动 Cap 服务 ──────────────────────────────────────
info "启动 Cap 服务..."
cd "$DEPLOY_DIR"
docker compose up -d

# ── 9. 等待就绪 ───────────────────────────────────────────
info "等待服务就绪..."
READY=false
for i in $(seq 1 30); do
  if curl -sf "http://localhost:3000/cap/" > /dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 1
done

if [ "$READY" = false ]; then
  fail "Cap 服务未在 30 秒内就绪，请检查日志: cd ${DEPLOY_DIR} && docker compose logs"
fi

# ── 完成 ──────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Cap Offline 本地部署完成 ✓${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo ""
echo -e "  版本:      ${VERSION}"
echo -e "  管理后台:  ${BLUE}http://localhost:3000/cap/${NC}"
echo -e "  测试页面:  ${BLUE}http://localhost:3000/cap/public/tester.html${NC}"
echo -e "  Admin key: ${ADMIN_KEY}"
echo ""
echo -e "  部署目录:  ${DEPLOY_DIR}"
echo -e "  查看日志:  ${YELLOW}cd ${DEPLOY_DIR} && docker compose logs -f${NC}"
echo -e "  停止服务:  ${YELLOW}cd ${DEPLOY_DIR} && docker compose down${NC}"
echo -e "  完全清理:  ${YELLOW}bash ${SCRIPT_DIR}/cleanup-local.sh${NC}"
echo ""
