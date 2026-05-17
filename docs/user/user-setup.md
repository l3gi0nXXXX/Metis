# Magic CLI 使用指南

Magic CLI 是一个基于仓颉语言开发的智能代码助手工具，支持多种编程语言的代码分析、生成和优化功能。

本指南以 Windows 操作系统环境为例进行介绍。

## 第一步：安装仓颉 SDK 环境

### 1.1 下载和安装

访问仓颉官方网站下载最新版本的 Cangjie SDK：
https://cangjie-lang.cn/docs?url=%2F1.0.0%2Fuser_manual%2Fsource_zh_cn%2Ffirst_understanding%2Finstall_Community.html

### 1.2 设置环境变量

**方法一：永久设置 CANGJIE_HOME（推荐）**

将仓颉安装目录添加到系统环境变量：
1. 右键"此电脑" → "属性" → "高级系统设置" → "环境变量"
2. 在"系统变量"中点击"新建"
3. 变量名：`CANGJIE_HOME`
4. 变量值：仓颉SDK安装路径（如：`C:\Program Files\Cangjie`）

**方法二：临时设置（单次会话有效）**

在 PowerShell 中执行：
```powershell
"path\to\cangjie\envsetup.ps1"
```

### 1.3 验证安装

打开命令提示符或PowerShell，输入：
```cmd
cjc --version
```
如果显示版本信息，说明安装成功。

## 第二步：下载和配置 Magic CLI

### 2.1 下载 Magic CLI

将 Magic CLI 项目放置到您希望安装的目录，例如：
```
C:\Tools\magic-cli
```

### 2.2 设置执行权限，将 magic-cli 添加到 PATH 环境变量

由于 Windows 安全策略，可能需要临时允许 PowerShell 脚本执行。

```powershell
Set-ExecutionPolicy Bypass -Scope CurrentUser
.\add-to-path.ps1
```

脚本会自动将当前目录添加到用户的 PATH 环境变量中。


## 第三步：设置 API 密钥

推荐直接写入 `~/.metis/metis.json`，不要再使用 `.env` 文件或旧环境变量入口。

本例以火山引擎 ARK 上的 Kimi-K2 为例；如果你要继续生成 Cangjie 代码，也建议同时把 Context7 的密钥写入同一个配置文件。

```json
{
  "models": {
    "providers": {
      "volcengine": {
        "apiKey": "your_api_key_here",
        "baseUrl": "https://ark.cn-beijing.volces.com/api/coding/v3"
      }
    }
  },
  "tools": {
    "context7": {
      "apiKey": "your_context7_api_key_here"
    }
  }
}
```

说明：

- 火山引擎 ARK 凭据写入 `models.providers.volcengine`
- 月之暗面写入 `models.providers.moonshot`
- 智谱 GLM / Z.AI 写入 `models.providers.zai`
- 如需 fallback，可继续在同一个 `metis.json` 里配置多个 provider

Context7 用于查询仓颉语言文档，提供更准确的语法和功能参考。可在 https://context7.com/dashboard 获取 API KEY。

## 第四步：启动和使用

### 4.1 基本启动

重新打开命令提示符或PowerShell（以加载新的PATH），然后运行：
```cmd
magic-cli
```

### 4.2 命令行参数说明

Magic CLI 支持多种启动参数：

- `--auto`：启用自主模式，代理将自动处理任务
- `--language, -l`：指定编程语言模式
  - `cangjie`：仓颉语言专用模式（默认）
  - `general`：通用模式
- `--model <model>`：指定使用的AI模型
- `--fast-model <model>`：设置快速模型，启用混合模式
- `--temperature, -t <value>`：设置AI模型温度参数（默认：1.0）
- `--prompt, -p <prompt>`：非交互模式，直接执行指定提示
- `--log-level <level>`：设置日志级别（默认：DEBUG）
- `--help, -h`：显示帮助信息

### 4.3 使用示例
magic-cli 初次打开某个目录时会让用户选择语言模式，之后该目录下再次启动 magic-cli 会沿用初次配置的语言模式。
也可以通过 `--language` 参数选择语言模式，如：

**启动仓颉模式：**
```cmd
magic-cli --language cangjie
```

**自主模式运行：**
该模式无需用户手动批准工具调用。
```cmd
magic-cli --auto
```

**非交互模式执行任务：**
```cmd
magic-cli -p "帮我分析这个代码的性能问题"
```

**设置特定模型和温度：**
```cmd
magic-cli --model zhipuai:glm-4.5 --temperature 0.7
```

### 4.4 Skills 触发与斜杠命令（新增）

如需完整命令列表、配置字段、使用场景与排错说明，请查看独立文档：

- **[Skills 使用手册](./skills-guide.md)**

Magic CLI 支持两种 skill 触发方式：

1. **自然语言触发**（默认）：模型从已加载 skill 列表中选择最匹配 skill；若未匹配则直接按通用模型回答。
2. **显式斜杠触发**（推荐做确定性操作）：用户直接输入 `/skillName 参数`，跳过意图识别，强制按该 skill 执行。

常见示例：

```cmd
/skills
/weather 上海
/summarize "https://example.com/article"
```

说明：

- `/skills`：显示当前发现的 skills 及 enabled 状态。
- `/weather 上海`：显式触发 `weather` skill，不再依赖模型意图判断。
- 当显式指定 `/skillName` 时，系统会优先按该 skill 处理，行为更快、可预期。
- 若该 skill 在 `~/.metis/metis.json` 中被禁用（`skills.entries.<skill>.enabled=false`），则不会执行该 skill 逻辑，会回退到通用模型直答。
- 对于显式指定 skill 的场景，系统会限制跨 skill 工具串用（例如 `/summarize ...` 不应调用 `weather` 工具）。

### 4.5 网关按渠道绑定模型（新增）

如果你同时接入多个 IM 渠道（例如飞书、QQ），可为不同渠道设置不同主模型。

在 `~/.metis/metis.json` 中配置：

```json
"gateway": {
  "channelModels": {
    "feishu": "deepseek:deepseek-chat",
    "qq": "qwen:qwen-plus"
  }
}
```

说明：

- `channelModels` 的 key 为渠道名（当前内置：`feishu`、`qq`），value 为模型全名。
- 渠道命中后，该模型会作为本轮优先模型；仍保留全局 fallback 链路。
- 若渠道模型配置错误（模型名无效、API key 无效、网络/鉴权失败等），系统会自动回退到全局模型配置继续回答。
- 可在网关日志中查看 `Gateway pre-call` 与 `Gateway channel-bound model ... failed` 等信息验证是否生效。

### 4.6 网关 IM 插件（钉钉等）

Telegram 内置 channel 的配置、DM/群聊策略、图片/文件/语音收发、Webhook、proxy 和排障说明见独立文档：

- **[Telegram 配置与使用说明](./telegram.md)**

多账号 IM 配置需要同时闭合 config、route binding 和 Gateway runtime 三段链路；如果配置与 binding 已存在但对应 account runtime 未启动，消息不会进入该账号的会话。排查和 OpenClaw 对齐依据见 `develop_steps/metis-im-multi-account-runtime-autostart-openclaw-source-backed-landing-plan-2026-05-17.md`。

通过 **command-adapter** 可接入钉钉等第三方 IM（默认钉钉使用 **Stream 模式**，无需公网回调 URL）。安装步骤、凭证配置、`metis.json` 与 `plugin-config.json` 优先级、日志排错等见独立文档：

- **[网关即时通讯（IM）插件说明](./gateway-im-plugins.md)**

（文档内后续会补充其他 IM 平台章节。）

### 4.7 Dashboard 网页使用（新增）

Dashboard 用于在浏览器里查看和操作会话（Chat / Sessions / Skills / Gateway / Logs / Appearance）。

**前置条件（必须）**：

在使用 `/dashboard` 之前，需先启动网关服务：

```cmd
cjpm run -- gateway serve
```

如果网关未启动，Dashboard 会提示“gateway 未运行”，无法正常进行网页聊天与会话同步。

**打开方式**：

在 `magic-cli` 交互窗口输入：

```cmd
/dashboard
```

默认会打开本地地址（示例）：`http://127.0.0.1:18800/chat`

**UI 版本切换（用于评审对比）**：

- `?ui=v2`：新版布局（默认）
- `?ui=v1`：旧版布局（保留）

例如：

- `http://127.0.0.1:18800/chat?ui=v2`
- `http://127.0.0.1:18800/chat?ui=v1`

**常用说明**：

- Chat 页可发送消息并显示时间戳；
- Sessions 页支持按来源筛选（qq/feishu/cli）与按最近更新时间倒序查看；
- Skills 页支持搜索、显示描述，并可直接开关 enabled；
- Appearance 页可切换主题色，浏览器会记住用户选择。

## 故障排除

### 常见问题

1. **配置后执行magic-cli 无反应直接结束**：
    - 检查 是否设置好 cangjie 环境，如是否已执行 envsetup.ps1，当前启动窗口是否可以正确执行 cjc 命令。

2. **"无法识别 magic-cli 命令"**
   - 确认已正确运行 `add-to-path.ps1`
   - 重新打开命令提示符/PowerShell
   - 检查 PATH 环境变量是否包含 Magic CLI 目录

3. **"无法加载文件，因为在此系统上禁止运行脚本"**
   - 以管理员身份运行PowerShell
   - 执行：`Set-ExecutionPolicy Bypass -Scope CurrentUser`

4. **API 调用失败**
   - 检查 `~/.metis/metis.json` 中对应 provider 的 `apiKey` 是否正确配置
   - 确认API密钥有效且有足够配额
   - 检查网络连接

### 获取帮助

如果遇到其他问题，可以：
1. 运行 `magic-cli --help` 查看完整参数说明
2. 查看 `~/.metis/logs/` 下的日志文件了解详细错误信息
3. 确保所有依赖环境正确安装

---

🎉 **安装完成！** Enjoy ~
