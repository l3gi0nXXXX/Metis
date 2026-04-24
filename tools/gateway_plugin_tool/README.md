# Gateway Plugin Tool

将当前项目兼容的网关插件运行时安装到 `~/.metis/gateway-plugins/<plugin-id>`。

**用户向完整说明（钉钉安装、参数、排错）见：** [`docs/user/gateway-im-plugins.md`](../../docs/user/gateway-im-plugins.md)。

安装时会复制整个 `runtime/` 目录（`adapter.py`、兼容辅助模块、`channels/`），与「单文件 adapter」相比更易按渠道扩展。

## Python 依赖（分渠道 / 一次性装全）

各渠道可选依赖拆在 `requirements/` 下（`dingtalk.txt`、`feishu.txt`、`qq.txt`、`wechat.txt`、`wecom.txt`、`wechat-mp.txt`），并由 `requirements/requirements-all.txt` 聚合。

**只装某一渠道：**

```bash
python tools/gateway_plugin_tool/install.py deps dingtalk
# 或
pip install -r tools/gateway_plugin_tool/requirements/dingtalk.txt
```

**一次性安装全部登记依赖：**

```bash
python tools/gateway_plugin_tool/install.py deps all
# 或
pip install -r tools/gateway_plugin_tool/requirements.txt
```

脚本封装（可选）：

- Windows: `tools/gateway_plugin_tool/install_deps.ps1`（默认 `all`，可传渠道名）
- Linux/macOS: `tools/gateway_plugin_tool/install_deps.sh [dingtalk|all|...]`

钉钉 **默认 Stream 模式**（**无需**在开放平台配置公网 HTTP 回调）。未安装 `dingtalk-stream` 时，侧车无法正常连接；请查看 `~/.metis/gateway-plugins/dingtalk/.runtime/dingtalk.log`。

## 支持的平台

- dingtalk（默认 **Stream** 侧车 + `channels.dingtalk`；可选 `transport: webhook`）
- wechat / wecom / wechat-mp / qq / feishu（共用运行时骨架，可在 `channels/<id>.py` 中按需实现）

## 用法

在项目根目录执行：

```bash
python tools/gateway_plugin_tool/install.py list
python tools/gateway_plugin_tool/install.py install dingtalk
python tools/gateway_plugin_tool/install.py install all
python tools/gateway_plugin_tool/install.py deps feishu
python tools/gateway_plugin_tool/install.py deps all
python tools/gateway_plugin_tool/install.py --help
python tools/gateway_plugin_tool/install.py install --help
```

- **`install <name>`**：只向 `~/.metis/gateway-plugins/<name>` 复制一份运行时。
- **`install all`**：对上述所有支持渠道各安装一遍（已存在 `adapter.py` 且未加 `--force` 时跳过该渠道）。
- **`deps <name>|all`**：对应当前 Python 解释器执行 `pip install -r requirements/<name>.txt` 或聚合文件。

可选参数：

```bash
python tools/gateway_plugin_tool/install.py install wechat --state-root C:/Users/example
python tools/gateway_plugin_tool/install.py install qq --force
python tools/gateway_plugin_tool/install.py install all --force
python tools/gateway_plugin_tool/install.py install dingtalk --app-id dingxxxx --app-secret xxxxx
```

## 兼容钉钉配置（钉钉）

推荐在 `plugin-config.json` 或 `gateway.channelsExtra.dingtalk` 中使用嵌套结构：

- `clientId` / `clientSecret`（钉钉应用 AppKey / AppSecret；CLI 的 `app-id` / `app-secret` 会归一化到此）
- **`transport`**（可选）：
  - **`stream`**（默认）：使用官方 `dingtalk-stream` 长连接收消息，**不需要**配置回调 URL；钉钉控制台机器人消息接收选 **Stream 模式**。
  - **`webhook`**：本地 HTTP 侧车 + 控制台 **HTTP 回调** + 公网 URL（或内网穿透）。

其他可选字段（仅 Webhook）：`webhookHost` / `webhookPort` / `webhookPath`。

### 发送（单聊优先）

- Stream 入站时会将 `sessionWebhook` 写入 `.runtime/dingtalk_reply_context.json`（按 `peerId`）。网关 `send` 时**优先**用该 Webhook 回复，适合与拉取式网关异步配合。
- 若无有效 Webhook，则使用 OpenAPI `POST /v1.0/robot/oToMessages/batchSend`（`msgKey: sampleText`），`userIds` 来自入站上下文中的 `staffId`，或 `peerId` 形如 `user:<钉钉用户ID>`。
- 需在开放平台为应用开通**企业内机器人发送单聊消息**等相关权限；`userIds` 须与钉钉侧用户标识一致（常见为管理后台可见的 userid）。

### `gateway.http.endpoints.chatCompletions.enabled`

这是网关本机上的 HTTP 能力开关，与钉钉 Stream/Webhook 选型无关；某些插件链路需要打开它来打通「插件 → 网关 → 模型」调用。

### 加密回调（仅 Webhook 模式）

若使用 HTTP 回调且开启加密体，需额外接入解密逻辑；Stream 模式一般不涉及该路径。

## 扩展其他 IM

1. 在 `tools/gateway_plugin_tool/runtime/channels/` 下新增 `<channelId>.py`。
2. 在模块末尾调用 `register_channel("<channelId>", start_hook, stop_hook)`（参考 `dingtalk.py`）。
3. 在 `channels/__init__.py` 的 `import_builtin_channels()` 中 `import channels.<channelId>`。
4. 入站写入 **`.runtime/inbox.jsonl`**，每行一个 JSON，字段需满足网关 `CommandPluginAdapter` 约定：`peerId`、`senderId`、`text` 必填；`messageId`、`chatType`、`mentioned` 可选。

## 设计说明

1. 安装时**不要求**必须提供凭证；可在安装后通过 CLI 或编辑 `plugin-config.json` 填写。
2. `gateway plugin enable <id>`、`gateway restart` 等与现有 CLI 一致。
3. `--force` 会覆盖已安装的运行时文件，**不会**删除已有 `plugin-config.json`（避免冲掉凭证）。
4. 本地开发可直接运行仓库内 `tools/gateway_plugin_tool/adapter.py`（会转发到 `runtime/adapter.py`）。
