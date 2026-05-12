# Cap 离线部署 — 网站集成指南

本文档说明如何将 Cap 验证码服务集成到你的网站中。

## 概述

Cap 服务部署在你的内网环境中，所有前端资源（Widget JS、WASM）均由 Cap 服务器直接提供，**无需访问外部 CDN**。

所有 API 路径均以 `/cap` 为前缀（可通过 `BASE_PATH` 配置修改）。

## 快速开始

### 1. 引入 Widget 脚本

将以下代码添加到你网站的 HTML 中（放在 `</body>` 之前）：

```html
<script src="https://cap.example.com/cap/assets/widget.js"></script>
<script>
  // 指定 WASM 文件的加载地址（由 Cap 服务器提供，无需外部 CDN）
  window.CAP_CUSTOM_WASM_URL = "https://cap.example.com/cap/assets/cap_wasm_bg.wasm";
</script>
```

> **重要：** 将 `cap.example.com` 替换为你实际的 Cap 服务器地址。如果你的 `BASE_PATH` 不是 `/cap`，请相应修改路径。

### 2. 添加验证码组件

在需要显示验证码的位置添加：

```html
<cap-widget data-cap-api-endpoint="https://cap.example.com/cap" data-cap-hide-log></cap-widget>
```

### 3. 后端验证

用户完成验证后，前端会获得一个 token。在你的后端将该 token 发送到 Cap 服务器进行验证：

```
POST https://cap.example.com/cap/{siteKey}/siteverify
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
  <script src="https://cap.example.com/cap/assets/widget.js"></script>
  <script>
    window.CAP_CUSTOM_WASM_URL = "https://cap.example.com/cap/assets/cap_wasm_bg.wasm";
  </script>

  <!-- 第二步：放置验证码组件 -->
  <form action="/submit" method="POST">
    <cap-widget
      data-cap-api-endpoint="https://cap.example.com/cap"
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
<script src="https://cap.example.com/cap/assets/widget.js"></script>
<script>
  window.CAP_CUSTOM_WASM_URL = "https://cap.example.com/cap/assets/cap_wasm_bg.wasm";
</script>

<link rel="stylesheet" href="https://cap.example.com/cap/assets/floating.js">
<cap-floating data-cap-floating="[cap-widget]"></cap-floating>
```

### 后端验证示例（Python）

```python
import requests

def verify_cap_token(site_key, secret, token):
    response = requests.post(
        f"https://cap.example.com/cap/{site_key}/siteverify",
        json={"secret": secret, "response": token}
    )
    return response.json().get("success", False)

# 使用
if verify_cap_token("your_site_key", "your_secret", user_token):
    print("验证通过")
else:
    print("验证失败")
```

### 后端验证示例（Java）

```java
import java.net.http.*;
import java.net.URI;

public class CapVerifier {
    private static final String CAP_SERVER = "https://cap.example.com/cap";

    public static boolean verify(String siteKey, String secret, String token) throws Exception {
        HttpClient client = HttpClient.newHttpClient();
        String body = String.format(
            "{\"secret\":\"%s\",\"response\":\"%s\"}", secret, token
        );
        HttpRequest request = HttpRequest.newBuilder()
            .uri(URI.create(CAP_SERVER + "/" + siteKey + "/siteverify"))
            .header("Content-Type", "application/json")
            .POST(HttpRequest.BodyPublishers.ofString(body))
            .build();
        HttpResponse<String> response = client.send(request,
            HttpResponse.BodyHandlers.ofString());
        return response.body().contains("\"success\":true");
    }
}
```

## 获取站点密钥

在集成之前，需要在 Cap 管理后台创建站点密钥：

1. 访问 `https://cap.example.com/cap/`
2. 使用管理员密钥登录
3. 点击"Create Key"创建新密钥
4. 记录 **Site Key**（前端使用）和 **Secret**（后端验证使用）

每个网站（域名）应使用独立的站点密钥。

## 配置参数

### `<cap-widget>` 属性

| 属性 | 说明 | 默认值 |
|------|------|--------|
| `data-cap-api-endpoint` | Cap 服务器地址（**必填**，含 BASE_PATH） | 无 |
| `data-cap-hide-log` | 隐藏控制台日志 | 不设置 |
| `data-cap-disable-haptics` | 禁用触觉反馈 | 不设置 |
| `data-cap-i18n-complete` | 验证完成后的文案 | "I am human" |
| `data-cap-i18n-error` | 验证失败时的文案 | "Verification failed" |
| `data-cap-i18n-expired` | 验证过期时的文案 | "Verification expired" |
| `data-cap-i18n-label` | 验证按钮的标签 | "Verify" |
| `data-cap-i18n-retrieving` | 正在获取挑战的文案 | "Retrieving challenge" |
| `data-cap-i18n-waiting` | 等待验证的文案 | "Waiting" |

### `window.CAP_CUSTOM_WASM_URL`

指定 WASM 文件的加载地址。**必须设置**，否则 Widget 将尝试从外部 CDN 加载 WASM 文件（在你的内网环境中不可达）。

```javascript
window.CAP_CUSTOM_WASM_URL = "https://cap.example.com/cap/assets/cap_wasm_bg.wasm";
```

### `data-cap-api-endpoint`

Cap 服务的 API 端点地址。注意需要包含 `BASE_PATH` 前缀（默认 `/cap`）。

```html
<!-- 正确：包含 /cap 前缀 -->
<cap-widget data-cap-api-endpoint="https://cap.example.com/cap"></cap-widget>

<!-- 错误：缺少 /cap 前缀 -->
<cap-widget data-cap-api-endpoint="https://cap.example.com"></cap-widget>
```

## API 路径汇总

所有路径均基于 `data-cap-api-endpoint` 的值（即 `https://cap.example.com/cap`）：

| 操作 | 路径 | 方法 | 调用方 |
|------|------|------|--------|
| 获取验证挑战 | `/{siteKey}/challenge` | POST | 浏览器（Widget 自动调用） |
| 提交解题结果 | `/{siteKey}/redeem` | POST | 浏览器（Widget 自动调用） |
| 验证 token | `/{siteKey}/siteverify` | POST | 后端服务器 |
| Widget 脚本 | `/assets/widget.js` | GET | 浏览器 |
| 悬浮按钮脚本 | `/assets/floating.js` | GET | 浏览器 |
| WASM 模块 | `/assets/cap_wasm_bg.wasm` | GET | 浏览器 |
| WASM 加载器 | `/assets/cap_wasm.js` | GET | 浏览器 |

> 前两个操作（challenge、redeem）由 Widget 自动调用，你无需手动处理。

## 升级说明

当 Cap Docker 镜像更新时，Widget 和 WASM 的版本也随之更新。你**不需要修改网站代码**——服务器会自动提供新版本的资源文件。

如果需要强制客户端刷新缓存，可以在 URL 后添加版本号查询参数：

```html
<script src="https://cap.example.com/cap/assets/widget.js?v=3.1.0"></script>
```

## 常见问题

### Q: 用户浏览器是否需要访问外部网络？

**不需要。** 所有资源（JS、WASM）均由你的 Cap 服务器提供，验证请求也发送到你的服务器。唯一例外是非常旧的浏览器可能需要加载 `pako` 库——所有现代浏览器均不受影响。

### Q: 可以在多个网站使用同一个 Cap 服务吗？

**可以。** 为每个网站创建不同的 Site Key，使用相同的 `data-cap-api-endpoint` 即可。

### Q: 验证 token 的有效期是多久？

验证 token 有效期默认 2 小时（可通过 `TOKEN_TTL_MS` 配置）。Challenge（挑战）有效期为 15 分钟。

### Q: 如何处理验证失败？

验证失败时 Widget 会自动显示重试按钮。你也可以监听自定义事件来处理异常情况。

### Q: 如何修改验证难度？

在管理后台编辑站点密钥的配置（difficulty、challengeCount 等参数）。数值越高，客户端计算时间越长，安全性越高。
