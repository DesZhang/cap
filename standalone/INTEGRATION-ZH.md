# Cap 独立部署 — 网站集成指南

本文档说明如何在你的网站中集成 Cap 验证码服务。

## 概述

Cap 服务已部署在你的内网环境中，所有前端资源（Widget JS、WASM）均由 Cap 服务器直接提供，**无需访问外部 CDN**。

## 快速开始

### 1. 引入 Widget 脚本

将以下代码添加到你网站的 HTML 中（放在 `</body>` 之前）：

```html
<script src="https://cap.example.com/assets/widget.js"></script>
<script>
  // 指定 WASM 文件的加载地址（由你的 Cap 服务器提供，无需外部 CDN）
  window.CAP_CUSTOM_WASM_URL = "https://cap.example.com/assets/cap_wasm_bg.wasm";
</script>
```

> **重要：** 将 `cap.example.com` 替换为你实际的 Cap 服务器地址。

### 2. 添加验证码组件

在需要显示验证码的位置添加：

```html
<cap-widget data-cap-api-endpoint="https://cap.example.com" data-cap-hide-log></cap-widget>
```

### 3. 后端验证

用户完成验证后，前端会获得一个 token。在你的后端将该 token 发送到 Cap 服务器进行验证：

```
POST https://cap.example.com/{siteKey}/siteverify
Content-Type: application/json

{
  "secret": "你的站点密钥",
  "response": "用户提交的 token"
}
```

成功响应：
```json
{ "success": true }
```

失败响应：
```json
{ "success": false, "error": "Token not found" }
```

## 完整示例

### 基本集成

```html
<!DOCTYPE html>
<html>
<head>
  <title>Cap 验证码示例</title>
</head>
<body>
  <!-- 第一步：加载 Widget 脚本和 WASM 配置 -->
  <script src="https://cap.example.com/assets/widget.js"></script>
  <script>
    window.CAP_CUSTOM_WASM_URL = "https://cap.example.com/assets/cap_wasm_bg.wasm";
  </script>

  <!-- 第二步：放置验证码组件 -->
  <form action="/submit" method="POST">
    <cap-widget
      data-cap-api-endpoint="https://cap.example.com"
      data-cap-hide-log
    ></cap-widget>
    <button type="submit">提交</button>
  </form>
</body>
</html>
```

### 悬浮按钮模式

如果你希望验证码以悬浮按钮的形式出现在页面角落：

```html
<script src="https://cap.example.com/assets/widget.js"></script>
<script>
  window.CAP_CUSTOM_WASM_URL = "https://cap.example.com/assets/cap_wasm_bg.wasm";
</script>

<link rel="stylesheet" href="https://cap.example.com/assets/floating.js">
<cap-floating data-cap-floating="[cap-widget]"></cap-floating>
```

## 配置参数

### `<cap-widget>` 属性

| 属性 | 说明 | 默认值 |
|------|------|--------|
| `data-cap-api-endpoint` | Cap 服务器地址（**必填**） | 无 |
| `data-cap-hide-log` | 隐藏控制台日志 | 不设置 |
| `data-cap-disable-haptics` | 禁用触觉反馈 | 不设置 |
| `data-cap-i18n-complete` | 验证完成后的文案 | "I am human" |
| `data-cap-i18n-error` | 验证失败时的文案 | "Verification failed" |
| `data-cap-i18n-expired` | 验证过期时的文案 | "Verification expired" |
| `data-cap-i18n-label` | 验证按钮的标签 | "Verify" |
| `data-cap-i18n-retrieving` | 正在获取挑战的文案 | "Retrieving challenge" |
| `data-cap-i18n-waiting` | 等待验证的文案 | "Waiting" |

### `window.CAP_CUSTOM_WASM_URL`

指定 WASM 文件的加载地址。**必须设置**，否则 Widget 将尝试从外部 CDN 加载 WASM 文件（在你的网络环境中可能不可达）。

```javascript
window.CAP_CUSTOM_WASM_URL = "https://cap.example.com/assets/cap_wasm_bg.wasm";
```

## 升级说明

当 Cap Docker 镜像更新时，Widget 和 WASM 的版本也随之更新。你**不需要修改网站代码**——服务器会自动提供新版本的资源文件。

如果需要强制客户端刷新缓存，可以在 URL 后添加版本号查询参数：

```html
<script src="https://cap.example.com/assets/widget.js?v=2"></script>
```

## 常见问题

### Q: 用户浏览器是否需要访问外部网络？
**不需要。** 所有资源（JS、WASM）均由你的 Cap 服务器提供，验证请求也发送到你的服务器。唯一的例外是非常旧的浏览器可能需要加载 `pako` 库——所有现代浏览器均不受影响。

### Q: 可以在多个网站使用同一个 Cap 服务吗？
**可以。** 为每个网站创建不同的 Site Key，使用不同的 `data-cap-api-endpoint` 路径即可。

### Q: 验证 token 的有效期是多久？
验证 token 有效期为 2 小时。Challenge（挑战）有效期为 15 分钟。

### Q: 如何处理验证失败？
验证失败时 Widget 会自动显示重试按钮。你也可以监听自定义事件来处理异常情况。
