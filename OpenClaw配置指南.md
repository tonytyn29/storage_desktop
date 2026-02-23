# OpenClaw + devaicode.dev 中转站配置指南

> 作者：tonyt | 日期：2026-02-21 | 环境：WSL2 + Node.js 22 + OpenClaw 2026.2.19-2

## 背景

在 WSL2 上配置 OpenClaw（开源个人 AI 助手）使用 devaicode.dev 中转站访问 Claude 模型。
中转站提供 Anthropic API 兼容的接口，但背后有 Cloudflare WAF 保护。

---

## 遇到的所有问题及解决方案

### 问题 1：Telegram Bot 无法连接

**症状**：Bot 在 Telegram 中不回复消息。
**原因**：WSL2 通过 Windows 宿主的 Clash 代理（`172.26.144.1:7890`）上网。Node.js 内置 `fetch` 默认不读取 `http_proxy` 环境变量，无法连接 Telegram API。
**解决**：在 systemd service 文件中添加代理环境变量：

```ini
# ~/.config/systemd/user/openclaw-gateway.service
Environment="http_proxy=http://172.26.144.1:7890"
Environment="https_proxy=http://172.26.144.1:7890"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
```

> **注意**：OpenClaw 内部使用 `@mariozechner/pi-ai` 库，该库会自动执行
> `undici.setGlobalDispatcher(new EnvHttpProxyAgent())`，全局劫持 Node.js 的 `fetch`，
> 使其读取 `http_proxy`/`https_proxy`/`NO_PROXY`。这是后续很多问题的隐含根源。

---

### 问题 2：Telegram 需要配对

**症状**：Bot 回复 "access not configured"，附带 Pairing code。
**解决**：运行 `openclaw pairing approve telegram <code>` 完成配对。

---

### 问题 3：Cloudflare 403 拦截

**症状**：直接将 `ANTHROPIC_BASE_URL` 设为 `https://devaicode.dev` 后，API 调用返回 403 HTML 页面。
**原因**：Cloudflare WAF 检测到请求的 `User-Agent` 头包含 SDK 特征（如 `Anthropic/Node` 或 `OpenAI/Node`），自动拦截。
**验证方法**：

```bash
# curl 可以正常访问（User-Agent: curl/x.x.x）
curl -s https://devaicode.dev/v1/models -H "Authorization: Bearer sk-xxx" # ✅ 200

# Node.js SDK 被拦截
node -e "fetch('https://devaicode.dev/v1/models').then(r=>console.log(r.status))" # ❌ 403
```

**解决**：创建本地 curl 反向代理，过滤掉 SDK 的 User-Agent 头。

---

### 问题 4：本地 Proxy 不支持 SSE 流式响应

**症状**：通过 proxy 的请求"成功"但返回空内容（`isError=false` 但无文本）。
**原因**：初版 proxy 使用 `execSync(curl)` 同步执行，无法处理 Server-Sent Events 流式响应。
OpenClaw 的 OpenAI SDK 始终以 `stream: true` 发送请求，期望 SSE 格式的分块响应。
**解决**：重写 proxy，对 `stream: true` 的请求使用 `child_process.spawn` + `pipe`：

```javascript
// 检测是否需要流式
let isStreaming = false;
try { isStreaming = JSON.parse(body).stream === true; } catch {}

if (isStreaming) {
  res.writeHead(200, { 'Content-Type': 'text/event-stream' });
  const curl = spawn('curl', ['-s', '-N', ...args]); // -N 禁用缓冲
  curl.stdout.pipe(res);
}
```

---

### 问题 5：Proxy 转发了 SDK 的 User-Agent

**症状**：直接 curl 测试 proxy 正常，但通过 OpenAI SDK 调用 proxy 仍被 Cloudflare 拦截。
**原因**：proxy 转发了所有请求头（包括 `user-agent: OpenAI/Node ...`），curl 携带此头发给 devaicode.dev，Cloudflare 仍然拦截。
**解决**：在 proxy 中过滤 `user-agent` 头：

```javascript
for (const [key, value] of Object.entries(req.headers)) {
  if (key === 'host' || key === 'user-agent' || ...) continue; // 关键：过滤 user-agent
  curlArgs.push('-H', `${key}: ${value}`);
}
```

---

### 问题 6：`openai-completions` API 格式的工具 Schema 不兼容

**症状**：proxy 收到请求并转发，但 API 返回错误：`input_schema: JSON schema is invalid. It must match JSON Schema draft 2020-12`。
**原因**：devaicode.dev 中转站内部使用 Anthropic API。当以 OpenAI 格式（`/v1/chat/completions`）发送工具定义时，中转站需要将 OpenAI 的 `tools[].function.parameters` 转换为 Anthropic 的 `tools[].input_schema`。OpenClaw 使用 TypeBox 生成的 JSON Schema 包含 Anthropic 不接受的字段，转换后验证失败。
**解决**：改用 `anthropic-messages` API 格式。OpenClaw 的 Anthropic SDK 直接生成合规的 `input_schema`，无需转换。

---

### 问题 7：`EnvHttpProxyAgent` 劫持 127.0.0.1 请求

**症状**：proxy baseUrl 设为 `http://127.0.0.1:18800`，但 proxy 未收到请求。OpenClaw 的网络连接显示请求发往 Clash 代理（`172.26.144.1:7890`）。
**原因**：`pi-ai` 库设置了全局 `EnvHttpProxyAgent`，所有 `fetch` 请求都经过 HTTP 代理。虽然 `NO_PROXY=127.0.0.1` 应该排除本地地址，但如果 `NO_PROXY` 未正确设置或被覆盖，请求会被路由到 Windows 的 Clash。在 Windows 上，`127.0.0.1` 指向 Windows 本机，而不是 WSL2。
**解决**：确保 `NO_PROXY=localhost,127.0.0.1,::1` 正确设置在 systemd service 中。

---

### 问题 8（误导性）：`ANTHROPIC_BASE_URL` 环境变量无效

**症状**：在 `openclaw.json` 的 `env` 段设置了 `ANTHROPIC_BASE_URL`，但 OpenClaw 仍连接官方 API。
**原因**：OpenClaw 不直接使用 `ANTHROPIC_BASE_URL` 环境变量来路由请求。模型的 `baseUrl` 必须通过 `models.providers` 配置项设置，并且要选择正确的 `api` 类型。
**教训**：不要依赖环境变量，要在 config 的 provider 定义中明确设置 `baseUrl`。

---

## 最终正确配置

### 架构

```
Telegram 用户
  ↓ (通过 Clash 代理)
OpenClaw Gateway (WSL2, port 18789)
  ↓ Anthropic SDK (anthropic-messages 格式)
本地 curl Proxy (WSL2, 127.0.0.1:18800)
  ↓ curl (自动使用 curl 的 User-Agent)
devaicode.dev (Cloudflare ✅ 放行)
  ↓
Anthropic API
```

### 文件清单

| 文件 | 用途 |
|------|------|
| `~/.openclaw/openclaw.json` | OpenClaw 主配置 |
| `~/.openclaw/agents/main/agent/models.json` | Agent 模型注册表（**会被 `openclaw onboard` 覆盖**） |
| `~/.openclaw/devaicode-proxy.js` | 本地 curl 反向代理脚本 |
| `~/.config/systemd/user/openclaw-gateway.service` | OpenClaw systemd 服务 |
| `~/.config/systemd/user/devaicode-proxy.service` | Proxy systemd 服务 |

### openclaw.json 关键配置

```json
{
  "models": {
    "providers": {
      "devaicode": {
        "baseUrl": "http://127.0.0.1:18800",
        "apiKey": "sk-你的API密钥",
        "api": "anthropic-messages",
        "models": [
          { "id": "claude-opus-4-6", "contextWindow": 200000, "maxTokens": 16384, ... },
          { "id": "claude-sonnet-4-6", "contextWindow": 200000, "maxTokens": 8192, ... }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "devaicode/claude-opus-4-6" }
    }
  }
}
```

> **关键**：`baseUrl` 是 `http://127.0.0.1:18800`（不带 `/v1`），因为 Anthropic SDK 会自动追加 `/v1/messages`。
> **关键**：`api` 必须是 `anthropic-messages`，不能用 `openai-completions`。

### devaicode-proxy.js 关键逻辑

```javascript
// 过滤 user-agent 防止 Cloudflare 拦截
if (key === 'user-agent') continue;

// 流式请求用 spawn + pipe
if (isStreaming) {
  const curl = spawn('curl', ['-s', '-N', ...args]);
  curl.stdout.on('data', data => res.write(data));
}

// 客户端断开时用 res.on('close')，不要用 req.on('close')
res.on('close', () => { if (!curl.killed) curl.kill('SIGTERM'); });
```

---

## 常见操作

```bash
# 重启服务（WSL2）
systemctl --user restart devaicode-proxy.service openclaw-gateway.service

# 查看日志
journalctl --user -u openclaw-gateway.service -f
cat /tmp/devaicode-proxy.log

# 测试 proxy 是否正常
curl -s http://127.0.0.1:18800/v1/messages \
  -H "x-api-key: sk-你的KEY" -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-opus-4-6","max_tokens":50,"messages":[{"role":"user","content":"Hi"}]}'

# 测试 OpenClaw 端到端
openclaw agent --agent main --channel telegram --deliver -m "测试" --json

# 切换模型（修改 openclaw.json 中 agents.defaults.model.primary）
# 同时更新 models.json，然后 systemctl --user restart openclaw-gateway.service
```

---

## Windows 端配置

### 前提条件
- WSL2 必须先启动，且 devaicode-proxy 服务正在运行
- Windows OpenClaw 复用 WSL2 的 curl proxy（通过 localhost 端口转发）
- **不需要**在 Windows 上单独启动 proxy

### 启动 Windows OpenClaw Gateway（PowerShell）

```powershell
# 设置代理（Telegram 需要通过 Clash 访问）
$env:http_proxy = "http://127.0.0.1:7890"
$env:https_proxy = "http://127.0.0.1:7890"
$env:NO_PROXY = "localhost,127.0.0.1,::1"

# 启动 gateway
openclaw gateway --port 19000
```

> **关键**：`NO_PROXY` 必须包含 `127.0.0.1`，否则发往 proxy 的 API 请求也会被路由到 Clash。

### Windows 端配置文件

| 文件 | 说明 |
|------|------|
| `%USERPROFILE%\.openclaw\openclaw.json` | 主配置，`baseUrl` 设为 `http://127.0.0.1:18800` |
| `%USERPROFILE%\.openclaw\agents\main\agent\models.json` | 模型注册表，同上 |

### 问题 9（新）：`spawn E2BIG` — 请求体太大导致 proxy 崩溃

**症状**：proxy 不断崩溃重启，OpenClaw 返回 "Connection error."。
**原因**：OpenClaw 的请求体很大（系统提示 + 工具定义 + 会话历史 > 100KB），proxy 通过 `spawn('curl', ['-d', body])` 把请求体作为命令行参数传递，超出了 Linux 的 `ARG_MAX` 限制（约 128KB）。
**解决**：改用 `-d @-` 让 curl 从 stdin 读取请求体：

```javascript
// 旧写法（崩溃）：
curlArgs.push('-d', body);  // body 太大时 E2BIG
const curl = spawn('curl', curlArgs);

// 新写法（正确）：
curlArgs.push('-d', '@-');  // 从 stdin 读取
const curl = spawn('curl', curlArgs);
curl.stdin.write(body);     // 通过 stdin 传递，无大小限制
curl.stdin.end();
```

### 问题 10（新）：Windows 端口 18800 被占用（EADDRINUSE）

**症状**：Windows 上启动 proxy 报 `EADDRINUSE: address already in use 127.0.0.1:18800`。
**原因**：WSL2 的 localhost 端口转发机制让 WSL2 的 `127.0.0.1:18800` 在 Windows 上也可访问。Windows 的 Node.js 无法再绑定同一端口。
**解决**：不需要在 Windows 上启动单独的 proxy。直接复用 WSL2 的 proxy，在 Windows OpenClaw 配置中设 `baseUrl: "http://127.0.0.1:18800"`。

---

## 踩坑总结（速查表）

| 现象 | 根因 | 解法 |
|------|------|------|
| Cloudflare 403 | Node.js SDK 的 User-Agent 被 WAF 拦截 | 用 curl proxy 过滤 User-Agent |
| 请求成功但内容为空 | proxy 不支持 SSE 流式 | spawn + pipe 替代 execSync |
| `input_schema` invalid | openai-completions 格式工具 schema 不兼容 | 改用 anthropic-messages |
| proxy 没收到请求 | EnvHttpProxyAgent 把 127.0.0.1 路由到 Clash | 确保 NO_PROXY 包含 127.0.0.1 |
| `openclaw onboard` 后配置丢失 | onboard 会重写 models.json 和 gateway token | 手动恢复 models.json 和 token |
| Telegram 不回复 | WSL2 无法直连 Telegram API | systemd 中设置 http_proxy |
| `ANTHROPIC_BASE_URL` 无效 | OpenClaw 不用这个环境变量路由 | 在 provider config 中设置 baseUrl |
| `spawn E2BIG` proxy 崩溃 | 请求体太大超出 ARG_MAX | 改用 `-d @-` 从 stdin 传递 |
| Windows EADDRINUSE 18800 | WSL2 端口转发占用 | 不起 Windows proxy，复用 WSL2 的 |
