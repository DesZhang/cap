# Cap 离线部署指南

## 概述

本指南帮助你在**无互联网访问**的生产环境中部署 Cap 验证码服务。

Cap 是一个轻量级的 proof-of-work 验证码替代方案。本离线部署包包含：
- 预构建的 Docker 镜像（含所有前端资源和地理数据库）
- Docker Compose 生产配置
- 部署验证脚本

## 前置条件

| 项目 | 要求 |
|------|------|
| Docker | 20.10+ |
| Docker Compose | v2+ |
| Redis 集群 | 已部署且可达 |
| 系统架构 | linux/amd64 |
| 磁盘空间 | ≥ 500MB（镜像 + 运行时数据） |
| 内存 | ≥ 256MB |

## 部署步骤

### 1. 传输部署包

将 `cap-offline-{version}.tar.gz` 传输到生产服务器：

```bash
scp cap-offline-{version}.tar.gz user@production-server:~/
```

### 2. 解压

```bash
mkdir -p ~/cap && tar -xzf cap-offline-*.tar.gz -C ~/cap --strip-components=1
cd ~/cap
```

### 3. 加载 Docker 镜像

```bash
docker load < cap-image.tar
```

验证镜像已加载：
```bash
docker images | grep cap-offline
```

### 4. 配置环境变量

```bash
cp .env.example .env
```

编辑 `.env`，**必须填写**以下配置：

```bash
# 管理员密钥（至少 12 个字符，建议使用随机字符串）
ADMIN_KEY=your_secure_admin_key_here

# Redis 集群节点地址（多个节点用逗号分隔）
REDIS_CLUSTER_URLS=redis-node1:6379,redis-node2:6379,redis-node3:6379
```

可选配置：
```bash
# Redis 集群认证
REDIS_CLUSTER_PASSWORD=your_redis_password
REDIS_CLUSTER_USERNAME=

# Redis 键名前缀（默认 cap:）
REDIS_KEY_PREFIX=cap:

# 验证 token 有效期（毫秒，默认 7200000 = 2 小时）
TOKEN_TTL_MS=

# 客户端 IP 识别头（使用反向代理时保持默认）
RATELIMIT_IP_HEADER=X-Forwarded-For

# API 路径前缀（默认 /cap）
BASE_PATH=/cap

# 服务端口（默认 3000）
CAP_PORT=3000
```

### 5. 启动服务

```bash
docker compose up -d
```

查看启动日志：
```bash
docker compose logs -f cap
```

正常启动时会看到：
```
[entrypoint] Loading baked assets into Redis...
[load-assets] Loaded widget@0.1.50, wasm@0.0.7 into Redis
🧢 Cap running on http://0.0.0.0:3000
```

### 6. 验证部署

```bash
bash verify.sh
```

该脚本会自动检查以下项目：
1. Docker 镜像已加载
2. 环境变量已配置
3. 服务启动成功
4. 离线静态资源可访问（widget.js、WASM 等）
5. Challenge API 正常响应
6. 管理后台可登录
7. IP 地理数据库已加载

## API 访问边界

### 对外开放 API（供下游网站和用户浏览器访问）

这些 API 应通过反向代理对外暴露。

| 路径 | 方法 | 调用方 | 说明 |
|------|------|--------|------|
| `{BASE_PATH}/{siteKey}/challenge` | POST | 用户浏览器 | 获取验证挑战 |
| `{BASE_PATH}/{siteKey}/redeem` | POST | 用户浏览器 | 提交解题结果 |
| `{BASE_PATH}/{siteKey}/siteverify` | POST | 后端服务器 | 服务端验证 token |
| `{BASE_PATH}/assets/widget.js` | GET | 用户浏览器 | Widget 脚本 |
| `{BASE_PATH}/assets/floating.js` | GET | 用户浏览器 | 悬浮按钮脚本 |
| `{BASE_PATH}/assets/cap_wasm_bg.wasm` | GET | 用户浏览器 | WASM 验证模块 |
| `{BASE_PATH}/assets/cap_wasm.js` | GET | 用户浏览器 | WASM 加载器 |

> `BASE_PATH` 默认为 `/cap`，可通过 `.env` 修改。以下示例均使用 `/cap`。

**示例（BASE_PATH=/cap）**：
```
POST /cap/abc123/challenge     → 获取挑战
POST /cap/abc123/redeem        → 提交答案
POST /cap/abc123/siteverify    → 验证 token
GET  /cap/assets/widget.js     → 获取 Widget
```

### 仅内部访问 API（管理后台，需 ADMIN_KEY 认证）

这些 API **不应**对外暴露，仅限运维人员通过内网访问。

| 路径前缀 | 说明 |
|----------|------|
| `{BASE_PATH}/auth/*` | 管理员登录/会话管理 |
| `{BASE_PATH}/server/keys` | 站点密钥列表（GET）、创建密钥（POST） |
| `{BASE_PATH}/server/keys/:siteKey` | 查看/修改/删除密钥 |
| `{BASE_PATH}/server/keys/:siteKey/stats` | 密钥统计数据 |
| `{BASE_PATH}/server/keys/:siteKey/geo-stats` | 地理分布统计 |
| `{BASE_PATH}/server/keys/:siteKey/blocked-ips` | IP/ASN/国家封禁规则 |
| `{BASE_PATH}/server/settings/*` | 全局配置（限流、CORS、过滤规则、请求头） |
| `{BASE_PATH}/server/settings/ipdb` | IP 地理数据库管理 |
| `{BASE_PATH}/server/sessions` | 会话管理 |
| `{BASE_PATH}/server/apikeys` | API 密钥管理 |

### 网络配置建议

在反向代理（如 Nginx）中，建议按以下方式配置：

```nginx
# 对外暴露 — Cap 验证服务
location /cap/ {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
}

# 限制内部访问 — 管理后台（仅允许内网 IP）
location /cap/auth/ {
    allow 10.0.0.0/8;
    allow 172.16.0.0/12;
    allow 192.168.0.0/16;
    deny all;
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}

# 限制内部访问 — 服务管理 API
location /cap/server/ {
    allow 10.0.0.0/8;
    allow 172.16.0.0/12;
    allow 192.168.0.0/16;
    deny all;
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

> **注意**：如果你的管理后台需要通过外网访问，请配置额外的认证层（如 VPN、IP 白名单、基础认证等）。

## 管理后台

启动服务后，通过浏览器访问管理后台：

```
http://<服务器IP>:<CAP_PORT>/cap/
```

使用 `.env` 中配置的 `ADMIN_KEY` 登录。

管理后台功能：
- 创建和管理站点密钥（Site Key）
- 查看验证统计数据和地理分布
- 配置 IP/ASN/国家封禁规则
- 管理全局设置（限流、CORS、过滤等）

## 升级流程

当收到新版本的离线部署包时：

```bash
# 1. 停止当前服务
docker compose down

# 2. 加载新镜像
docker load < cap-image.tar

# 3. 更新 .env 中的版本号（如有变化）
# CAP_VERSION=x.x.x

# 4. 启动新版本
docker compose up -d

# 5. 验证
bash verify.sh

# 6. （可选）清理旧镜像
docker image prune -f
```

> 配置数据（站点密钥、设置等）存储在 Redis 集群中，升级不会丢失。

## 故障排查

### 服务无法启动

```bash
# 查看容器日志
docker compose logs cap --tail 100

# 检查端口是否被占用
ss -tlnp | grep 3000
```

### Redis 连接失败

```
Error: connect ECONNREFUSED
```

排查步骤：
1. 确认 Redis 集群节点地址正确：`echo $REDIS_CLUSTER_URLS`
2. 确认网络连通性：`nc -zv redis-node1 6379`
3. 如需认证，确认 `REDIS_CLUSTER_PASSWORD` 已设置
4. 确认 Redis 集群允许来自 Cap 容器的连接

### 静态资源返回 503

```
Asset not cached yet
```

说明 Widget/WASM 资源未正确加载到 Redis。查看入口脚本日志：
```bash
docker compose logs cap | grep "load-assets"
```

正常应显示：
```
[load-assets] Loaded widget@0.1.50, wasm@0.0.7 into Redis
```

### IP 地理数据库未加载

```bash
docker compose logs cap | grep ipdb
```

如果显示警告或错误，说明 `.mmdb` 文件可能未正确打包。请重新构建镜像。

### IP 封禁规则不生效

确认 `RATELIMIT_IP_HEADER` 配置正确。使用反向代理时，通常设置为 `X-Forwarded-For`。

## 许可证说明

- **Cap**: Apache-2.0 License
- **DB-IP 地理数据库**: CC-BY 4.0（使用时需注明来源 https://db-ip.com）
