#!/bin/bash
# ── Cap Offline — 本地部署清理脚本 ─────────────────────────
#
# 用法: bash cleanup-local.sh
# 说明:
#   停止并清理本地部署的所有资源：
#   - Cap Docker 容器
#   - 本地 Redis 集群（3 节点）
#   - 部署目录
#   - 临时文件
#   - Docker 网络
#
#   默认保留 Docker 镜像，如需删除请传 --prune-image

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOY_DIR="${REPO_ROOT}/cap-offline-local"
PRUNE_IMAGE=false

for arg in "$@"; do
  case "$arg" in
    --prune-image) PRUNE_IMAGE=true ;;
    *) echo "未知参数: $arg"; exit 1 ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info() { echo -e "${YELLOW}→ $1${NC}"; }
pass() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${RED}! $1${NC}"; }

echo ""
echo "══════════════════════════════════════════"
echo "  Cap Offline 本地清理"
echo "══════════════════════════════════════════"
echo ""

# ── 1. 停止 Cap 容器 ──────────────────────────────────────
if [ -d "$DEPLOY_DIR" ] && [ -f "${DEPLOY_DIR}/docker-compose.yml" ]; then
  info "停止 Cap Docker Compose..."
  cd "$DEPLOY_DIR"
  docker compose down --remove-orphans 2>/dev/null || true
  pass "Cap 容器已停止"
else
  info "未找到部署目录，尝试直接移除容器..."
  docker rm -f cap 2>/dev/null || true
fi

# ── 2. 停止 Redis 集群 ────────────────────────────────────
info "停止本地 Redis 集群..."
bash "${SCRIPT_DIR}/scripts/mock-redis-cluster.sh" stop 2>/dev/null || warn "Redis 集群停止脚本失败（可能已停止）"

# ── 3. 删除部署目录 ───────────────────────────────────────
if [ -d "$DEPLOY_DIR" ]; then
  info "删除部署目录 ${DEPLOY_DIR}..."
  rm -rf "$DEPLOY_DIR"
  pass "部署目录已删除"
fi

# ── 4. 清理临时文件 ───────────────────────────────────────
info "清理临时文件..."
rm -f /tmp/cap-cookies.txt /tmp/cap-smoke-cookies.txt
pass "临时文件已清理"

# ── 5. 可选：删除 Docker 镜像 ─────────────────────────────
if [ "$PRUNE_IMAGE" = true ]; then
  info "删除 Docker 镜像..."
  # 查找所有 cap-offline 镜像
  IMAGES=$(docker images "cap-offline" --format "{{.Repository}}:{{.Tag}}")
  if [ -n "$IMAGES" ]; then
    echo "$IMAGES" | xargs -r docker rmi -f 2>/dev/null || true
    pass "Docker 镜像已删除"
  else
    pass "未找到 cap-offline 镜像"
  fi
fi

# ── 完成 ──────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  清理完成 ✓${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo ""
if [ "$PRUNE_IMAGE" = false ]; then
  echo "  Docker 镜像已保留。如需删除，请运行:"
  echo "    bash ${SCRIPT_DIR}/cleanup-local.sh --prune-image"
  echo ""
fi
