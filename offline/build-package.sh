#!/bin/bash
# ── Cap Offline — 构建打包脚本 ────────────────────────────
#
# 在有网络的环境中运行，构建 Docker 镜像并打包为离线部署包。
#
# 用法: bash build-package.sh [--skip-test]
# 参数:
#   --skip-test  跳过构建后冒烟测试（快速迭代时使用）
#
# 输出: cap-offline-{version}.tar.gz

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STANDALONE_DIR="$(cd "$SCRIPT_DIR/../standalone" && pwd)"

# ── 参数解析 ──────────────────────────────────────────────
SKIP_TEST=false
for arg in "$@"; do
  case "$arg" in
    --skip-test) SKIP_TEST=true ;;
    *) echo "未知参数: $arg"; exit 1 ;;
  esac
done

# ── 读取版本号 ────────────────────────────────────────────
VERSION=$(grep '"version"' "$STANDALONE_DIR/package.json" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')
if [ -z "$VERSION" ]; then
  echo "错误: 无法从 standalone/package.json 读取版本号"
  exit 1
fi

IMAGE_TAG="cap-offline:${VERSION}"
PACKAGE_NAME="cap-offline-${VERSION}"
OUTPUT_DIR="${REPO_ROOT}/${PACKAGE_NAME}"

echo ""
echo "══════════════════════════════════════════"
echo "  Cap Offline 构建打包"
echo "  版本: ${VERSION}"
echo "  镜像: ${IMAGE_TAG}"
echo "══════════════════════════════════════════"
echo ""

# ── 构建镜像 ──────────────────────────────────────────────
echo ""
echo "── 步骤 1/4: 构建 Docker 镜像 ─────────────────"
docker build \
  -f "$SCRIPT_DIR/Dockerfile.offline" \
  -t "$IMAGE_TAG" \
  --platform linux/amd64 \
  "$REPO_ROOT"

echo ""
echo "镜像构建完成: ${IMAGE_TAG}"
echo "镜像大小: $(docker images "$IMAGE_TAG" --format '{{.Size}}')"

# ── 冒烟测试 ──────────────────────────────────────────────
if [ "$SKIP_TEST" = false ]; then
  echo ""
  echo "── 步骤 2/4: 冒烟测试 ─────────────────────────"
  cd "$SCRIPT_DIR"
  VERSION="$VERSION" bash smoke-test.sh
  if [ $? -ne 0 ]; then
    echo ""
    echo "❌ 冒烟测试失败！请检查上述输出。"
    echo "   使用 --skip-test 跳过测试（不推荐）。"
    exit 1
  fi
else
  echo ""
  echo "── 步骤 2/4: 冒烟测试（已跳过）─────────────────"
fi

# ── 打包 ──────────────────────────────────────────────────
echo ""
echo "── 步骤 3/4: 打包 ─────────────────────────────"

# 清理旧包
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# 导出 Docker 镜像
echo "  导出 Docker 镜像..."
docker save "$IMAGE_TAG" -o "$OUTPUT_DIR/cap-image.tar"

# 复制部署文件
echo "  复制部署文件..."
cp "$SCRIPT_DIR/docker-compose.yml" "$OUTPUT_DIR/docker-compose.yml"
cp "$SCRIPT_DIR/.env.example" "$OUTPUT_DIR/.env.example"
cp "$SCRIPT_DIR/verify.sh" "$OUTPUT_DIR/verify.sh"
cp "$SCRIPT_DIR/deploy-guide.md" "$OUTPUT_DIR/deploy-guide.md"
cp "$SCRIPT_DIR/integration-guide.md" "$OUTPUT_DIR/integration-guide.md"

# 写入版本到 docker-compose.yml 中的默认版本
sed -i.bak -E "s/CAP_VERSION:-[0-9][^]}]*/CAP_VERSION:-${VERSION}/g" "$OUTPUT_DIR/docker-compose.yml" && rm -f "$OUTPUT_DIR/docker-compose.yml.bak"

# 复制 LICENSE
if [ -f "$REPO_ROOT/LICENSE" ]; then
  cp "$REPO_ROOT/LICENSE" "$OUTPUT_DIR/LICENSE"
fi

# 添加 README
cat > "$OUTPUT_DIR/README.txt" << EOF
Cap Offline 部署包 v${VERSION}
═══════════════════════════

文件说明:
  cap-image.tar        Docker 镜像文件
  docker-compose.yml   生产环境 Docker Compose 配置
  .env.example         环境变量模板（复制为 .env 后填写）
  verify.sh            部署验证脚本
  deploy-guide.md      部署指南（中文）
  integration-guide.md 网站集成指南（中文）
  LICENSE              开源许可证

快速开始:
  1. 阅读 deploy-guide.md
  2. 复制 .env.example 为 .env 并填写配置
  3. docker load < cap-image.tar
  4. docker compose up -d
  5. bash verify.sh

DB-IP 数据库许可:
  本镜像包含 DB-IP 免费版地理数据库 (CC-BY 4.0)。
  使用时需注明来源: https://db-ip.com

构建时间: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF

# 打包
echo "  创建压缩包..."
ARCHIVE="${REPO_ROOT}/${PACKAGE_NAME}.tar.gz"
tar -czf "$ARCHIVE" -C "$REPO_ROOT" "$PACKAGE_NAME"

# 清理临时目录
rm -rf "$OUTPUT_DIR"

# ── 完成 ──────────────────────────────────────────────────
ARCHIVE_SIZE=$(du -h "$ARCHIVE" | cut -f1)

echo ""
echo "── 步骤 4/4: 完成 ─────────────────────────────"
echo ""
echo "══════════════════════════════════════════"
echo "  构建完成！"
echo "══════════════════════════════════════════"
echo ""
echo "  版本:      ${VERSION}"
echo "  镜像:      ${IMAGE_TAG}"
echo "  架构:      linux/amd64"
echo "  输出文件:  ${ARCHIVE}"
echo "  文件大小:  ${ARCHIVE_SIZE}"
echo ""
echo "  传输到生产环境后，参考 deploy-guide.md 进行部署。"
echo ""
