# 网关即时通讯（IM）插件

本文说明如何通过 **网关插件** 将第三方 IM 接入 Metis（采用当前仓库的 command-adapter 形态）。当前详写 **钉钉**；其他渠道（企业微信、飞书插件形态等）将在此文档后续增补独立小节。

---

## 1. 工作原理（简要）

- 主程序 **`gateway serve`** 轮询各渠道的 **command-adapter**：对插件执行 `python adapter.py pull …`，从插件目录下 **`.runtime/inbox.jsonl`** 读取并清空队列；入站 JSON 解析成功后才会出现主日志中的 **`Gateway.inbound`**。
- 钉钉默认由 **Stream 侧车进程**（`dingtalk-stream`）长连接收消息，将标准化后的行写入 `inbox.jsonl`；回复时优先使用会话 **sessionWebhook**，失败时再尝试 OpenAPI **单聊批量发送**。
- 配置合并顺序：**`~/.metis/metis.json` 的 `gateway.channelsExtra.<插件 id>`** 若为非空对象，则**仅使用该对象**作为传给适配器的配置；否则回退到 **`~/.metis/gateway-plugins/<id>/plugin-config.json`** 全文。

---

## 2. 钉钉（DingTalk）

### 2.1 前提条件

| 项目 | 说明 |
|------|------|
| 网关总开关 | `~/.metis/metis.json` 中 `gateway.enabled = true`，或执行 `gateway master on` |
| Python | 已安装 **Python 3**，且 `python` 在 PATH 中（与启动侧车一致） |
| 钉钉应用 | 开放平台创建应用，取得 **AppKey / AppSecret**（对应下文 `clientId` / `clientSecret`）；机器人消息接收选择 **Stream 模式**（默认，无需公网回调 URL） |
| 权限 | 按需开通「机器人收消息」「企业内机器人发送单聊消息」等；单聊兜底发送依赖 OpenAPI 时须保证 `userIds` 与钉钉侧用户标识一致 |

### 2.2 安装 Python 依赖

钉钉 Stream 依赖 **`dingtalk-stream`**。推荐用安装工具，避免手写路径：

```bash
# 仅钉钉
python tools/gateway_plugin_tool/install.py deps dingtalk

# 或一次性安装「当前工具登记的全部渠道」可选依赖（含飞书 SDK、微信 wechatpy、QQ 侧车常用 requests/websocket 等）
python tools/gateway_plugin_tool/install.py deps all
```

等价于：

```bash
pip install -r tools/gateway_plugin_tool/requirements/dingtalk.txt
pip install -r tools/gateway_plugin_tool/requirements.txt
```

分渠道清单见 `tools/gateway_plugin_tool/requirements/*.txt`；聚合文件为 `requirements/requirements-all.txt`。也可使用脚本 `install_deps.ps1`（Windows）或 `install_deps.sh`（类 Unix），默认安装全部依赖。

### 2.3 安装插件到项目

在 **Metis 项目根目录** 执行：

```bash
python tools/gateway_plugin_tool/install.py list
python tools/gateway_plugin_tool/install.py install dingtalk
# 一次性为所有支持渠道各生成一套插件目录（已安装且未 --force 则跳过）
python tools/gateway_plugin_tool/install.py install all
```

常用可选参数：

| 参数 | 含义 |
|------|------|
| `--project-root <路径>` | 指定项目根（默认：install.py 所在仓库根的上两级） |
| `--force` | 覆盖已存在的 `adapter.py`、manifest 等（**不会**删除已有 `plugin-config.json`，避免冲掉凭证） |
| `--app-id` / `--app-secret` | 安装时直接写入新建的 `plugin-config.json`（仅当该文件尚不存在时创建模板） |

安装结果目录：`~/.metis/gateway-plugins/dingtalk/`（含 `adapter.py`、插件 manifest、`channels/`、兼容辅助脚本等）。

升级插件运行时（保留凭证）：使用 **`--force`** 重新 `install dingtalk`。

### 2.4 启用插件与填写凭证

**方式 A：CLI（写入 `gateway.channelsExtra.dingtalk`）**

```text
gateway plugin list
gateway plugin enable dingtalk
gateway plugin set dingtalk app-id <钉钉 AppKey>
gateway plugin set dingtalk app-secret <钉钉 AppSecret>
```

说明：`channelsExtra` 下只要出现**非空**配置对象，装配时会**优先于** `plugin-config.json`，请保证 `app-id` / `app-secret` 成对正确。

**方式 B：仅编辑 `plugin-config.json`**

在未使用 `channelsExtra` 覆盖时，使用安装时生成的嵌套结构，例如：

```json
{
  "channels": {
    "dingtalk": {
      "enabled": true,
      "transport": "stream",
      "clientId": "dingxxxxxxxx",
      "clientSecret": "your_app_secret",
      "webhookHost": "0.0.0.0",
      "webhookPort": 8890,
      "webhookPath": "/dingtalk/callback"
    }
  }
}
```

扁平键 **`app-id` / `app-secret`** 与 **`clientId` / `clientSecret`** 等价（运行时由 Python 归一化到 `channels.dingtalk`）。

**在 `metis.json` 中登记插件（必须）**

确保存在启用的插件项，例如：

```json
"gateway": {
  "enabled": true,
  "gatewayPlugins": [
    { "id": "dingtalk", "enabled": true }
  ]
}
```

修改后执行 **`gateway restart`**，或关闭旧窗口后重新 **`gateway serve`**。

### 2.5 配置参数说明（钉钉）

| 键名 | 必填 | 说明 |
|------|------|------|
| `clientId` / `app-id` | 是 | 钉钉应用 AppKey |
| `clientSecret` / `app-secret` | 是 | 钉钉应用 AppSecret |
| `transport` / `mode` | 否 | **`stream`**（默认）：长连接，无需配置回调 URL；**`webhook`** / **`http`** / **`callback`**：本地 HTTP 侧车，需在开放平台配置可访问的回调 URL |
| `webhookHost` | 否 | Webhook 监听地址，默认 `0.0.0.0` |
| `webhookPort` | 否 | Webhook 端口，默认 `8890` |
| `webhookPath` | 否 | Webhook 路径，默认 `/dingtalk/callback` |

联调可选（`adapter.py pull` 在队列为空时注入一条假消息，需设置环境变量）：

| 环境变量 | 说明 |
|----------|------|
| `GATEWAY_PLUGIN_FAKE_PULL=1` | 队列空时输出一条测试 JSON（`testPeerId` / `testSenderId` / `testText` 可配在插件配置中） |

### 2.6 按渠道绑定模型（可选）

在 `metis.json` 的 `gateway.channelModels` 中为扩展渠道指定模型（与飞书、QQ 相同机制），例如：

```json
"gateway": {
  "channelModels": {
    "dingtalk": "deepseek:deepseek-chat"
  }
}
```

渠道名与适配器名一致，钉钉为 **`dingtalk`**。

### 2.7 启动与验证

```bash
cjpm run -- gateway serve
```

或使用已安装的 `magic-cli gateway serve`。

- 控制台会提示 **LogUtils 日志文件路径**（每次启动新建带时间戳的文件，与交互式 CLI 日志不同）。
- 正常时每隔约 10 秒可出现 **`Gateway.serve: heartbeat`**。
- 向机器人发一条单聊后，日志中应出现 **`Gateway.inbound: channel=dingtalk`**，随后有路由与 **`Gateway.send`** 结果。

### 2.8 日志与排错

通用日志命令见 [日志与排障](logging.md)。排查 IM 无回复时，先用 `metis logs tail --limit 200` 看主日志是否已经出现 inbound，再继续区分路由、模型回复和发送路径。

| 位置 | 内容 |
|------|------|
| `~/.metis/logs/*.log` | 网关主日志：`Gateway.serve` / `Gateway.inbound` / `Gateway.reply` / `Gateway.send` 等 |
| `~/.metis/gateway-plugins/dingtalk/.runtime/dingtalk.log` | Stream 侧车：连接、`[stream] -> inbox`、SDK 日志 |
| `~/.metis/gateway-plugins/dingtalk/.runtime/adapter.log` | `adapter.py` 的 start/send 等简要记录 |
| `~/.metis/gateway-plugins/dingtalk/.runtime/inbox.jsonl` | 入站队列（由 `pull` 读取并清空，勿手工依赖其持久存在） |

常见现象：

- **钉钉显示「已读」但无回复**：Stream 侧车仍会 ACK；若主日志无 `Gateway.inbound`，说明消息未进网关（检查插件是否启用、`pull` 是否成功、凭证与 Stream 是否连上）。
- **侧车有 `-> inbox` 但网关无 inbound**：确认已使用最新插件运行时与主程序（Windows 上管道换行等问题已在适配层修复）；确认 **`gateway serve`** 与侧车使用同一份 `~/.metis/gateway-plugins/dingtalk`。

### 2.9 回复路径说明

- **优先**：入站时把 `sessionWebhook` 按 `peerId` 写入 `.runtime/dingtalk_reply_context.json`，出站 **send** 优先走会话 Webhook（会话内回复，无需额外 `@` 块）。
- **兜底**：无有效 Webhook 时尝试 OpenAPI **`/v1.0/robot/oToMessages/batchSend`**，需应用权限与正确的用户 ID。

---

## 3. 其他 IM 平台（预留）

后续将在此文档增加各渠道小节，形态与钉钉类似：

- 使用 `tools/gateway_plugin_tool/install.py install <渠道名>` 安装；
- 在 `runtime/channels/` 实现 `register_channel`，入站写入 **`.runtime/inbox.jsonl`**（每行 JSON 需含 **`peerId`、`senderId`、`text`**）；
- 在 `metis.json` 的 `gateway.gatewayPlugins` 中启用对应 `id`。

开发细节可参考 `tools/gateway_plugin_tool/README.md`。

---

## 4. 相关文件索引

| 路径 | 说明 |
|------|------|
| `tools/gateway_plugin_tool/install.py` | `install` / `install all`、`deps` / `deps all`、`list` |
| `tools/gateway_plugin_tool/requirements/` | 分渠道 `*.txt` 与 `requirements-all.txt` |
| `tools/gateway_plugin_tool/install_deps.ps1` / `install_deps.sh` | 仅安装 Python 依赖的便捷封装 |
| `tools/gateway_plugin_tool/runtime/` | 运行时源码（安装时复制到 `gateway-plugins/<id>/`） |
| `tools/gateway_plugin_tool/runtime/channels/dingtalk.py` | 钉钉 Stream/Webhook/send |
| `examples/gateway-plugins/dingtalk/` | 历史模板目录，推荐以 install 工具为准 |
