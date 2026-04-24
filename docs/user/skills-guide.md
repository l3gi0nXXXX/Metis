# Skills 使用手册

本文档用于详细说明 Metis 中 Skills 的使用方式、全部命令、配置项与示例。

## 1. Skills 是什么

Skills 是基于 `SKILL.md` 的任务能力包。每个 skill 通常对应一个目录，目录下至少包含一个 `SKILL.md`。

系统会在运行时发现技能，并在对话中按规则选择使用：

- 显式触发：用户输入 `/<skillName> ...`
- 自然语言触发：系统根据输入语义匹配 skill
- 未匹配：走通用模型回答

## 2. Skills 目录与发现规则

默认会扫描以下目录（**同名 skill 后者覆盖前者**，即序号越大优先级越高）：

1. `skills.loadExtraDirs` 配置的额外目录（最低优先级）
2. bundled skills（当前源码运行时通常解析为 `<cjpmProjectRoot>/skills`）
3. `~/.metis/skills`
4. `~/.agents/skills`
5. `<workspace>/.agents/skills`
6. `<workspace>/skills`

补充说明：

- `workspace` 默认取当前进程工作目录；也可以通过 `agents.defaults.workspace` 显式覆盖。
- bundled skills 根目录会优先按 `METIS_CJPM_ROOT` 或从当前目录向上查找 `cjpm.toml` 来解析。
- 扫描前会按物理路径去重；若两个入口最终解析到同一路径，只会扫描一次。
- 覆盖规则是“按 skill 名称覆盖”，不是文件覆盖：后扫描到的同名 skill 会替换先前结果。
- 当多个扫描入口解析到同一路径（例如 workspace 本身就是源码根目录）时，来源标签以首次入队的根标签为准。

### 2.1 各目录的语义区别（来源标签）

运行时/`/skills` 输出会按路径映射来源标签（`source`）：

- `metis-extra`：来自 `skills.loadExtraDirs`
- `metis-bundled`：来自 bundled skills 根目录
- `metis-managed`：来自 `~/.metis/skills`
- `agents-skills-personal`：来自 `~/.agents/skills`
- `agents-skills-project`：来自 `<workspace>/.agents/skills`
- `metis-workspace`：来自 `<workspace>/skills`

### 2.2 Built-in / Extra / Other 的口径

这里分两层理解：

- **运行时真实来源（推荐以 source 为准）**
  - `metis-bundled`：项目内置目录
  - `metis-managed`：用户托管/共享技能目录
  - `metis-extra`：`skills.loadExtraDirs` 额外目录
  - `metis-workspace`：工作区技能目录
  - `agents-skills-project` / `agents-skills-personal`：agent 专属目录

- **Dashboard Skills 页当前分组（UI 口径）**
  - 按后端返回的 `category/source` 分组，不按名称启发式猜测：
  - `metis-bundled` → **Built-in**
  - `metis-managed` → **Managed**
  - `metis-extra` → **Extra**
  - `metis-workspace` → **Workspace**
  - `agents-skills-project` / `agents-skills-personal` → **Agent**

因此：若你关心“技能真正来自哪个目录”，请优先看 `/skills list` 的 `Source` 列，而不是仅看 Dashboard 分组标题。

### 2.3 同名 skill 冲突示例（最终哪个生效）

假设都存在同名 `weather`：

| 存在位置 | 扫描顺序位次 | 最终是否生效 | 原因 |
| --- | --- | --- | --- |
| `skills.loadExtraDirs[0]/weather/SKILL.md` | 1 | 否（通常） | 会被后续同名覆盖 |
| `~/.metis/skills/weather/SKILL.md` | 2 | 否（通常） | 会被后续同名覆盖 |
| `<cwd>/.agents/skills/weather/SKILL.md` | 3 | 否（通常） | 会被后续同名覆盖 |
| `~/.agents/skills/weather/SKILL.md` | 4 | 否（通常） | 会被后续同名覆盖 |
| `<projectRoot>/skills/weather/SKILL.md` | 6 | 否（若 cwd 有同名） | 仍可能被 `cwd/skills` 覆盖 |
| `<cwd>/skills/weather/SKILL.md` | 7 | 是（常见） | 顺序更靠后，优先级更高 |

如果 `cwd/skills` 不存在该 skill，则会回退到它之前最近的同名来源（例如 `projectRoot/skills` 或 `.agents/skills`）。

每个 skill 的结构示例：

```text
skills/
  weather/
    SKILL.md
  summarize/
    SKILL.md
```

## 3. 触发方式

### 3.1 自然语言触发

直接提问，系统自动选择最匹配的 skill。

示例：

```text
上海明天会下雨吗？
帮我总结这篇文章：https://example.com/a
```

### 3.2 显式斜杠触发（推荐）

格式：

```text
/<skillName> <参数或问题>
```

示例：

```text
/weather Shanghai
/summarize https://example.com/a
```

显式触发的特点：

- 跳过语义猜测，确定性更高
- 对固定流程任务更稳定

## 4. 全部相关命令

### 4.0 命令速查表

| 命令 | 作用 | 示例 |
| --- | --- | --- |
| `/skills list` | 列出 skills：`status | name | description | source` | `/skills list` |
| `/skills info <name>` | 查看指定 skill 详情 | `/skills info weather` |
| `/skills check [--json]` | 检查 skills 生态状态，支持 JSON 报告 | `/skills check --json` |
| `/skills search [query]` | 搜索可安装 skill，支持 `--limit`、`--json`；不带 query 时浏览全部 | `/skills search --limit 20 --json weather` |
| `/skills install <pkg>` | 安装 skill 到当前工作区 skills 目录，支持 ClawHub slug、`owner/repo@skill`、`--version` 与 `--force` | `/skills install weather --version 1.0.0` |
| `/skills update [slug|--all]` | 更新已安装 skills；可更新全部或指定 tracked ClawHub skill | `/skills update --all` |
| `/<skillName> <args>` | 显式触发某个 skill | `/weather Shanghai` |

Gateway / Dashboard / Control UI 兼容面：

- `skills.compatibilityMatrix`
- `skills.compatibility`（alias 到 `skills.compatibilityMatrix`）
- `dashboard.skills.compatibility`
- `/api/skills/compatibility`

### 4.1 ` /skills list `

用途：查看当前已发现 skills 的运行状态与来源。

在 CLI 与 Gateway 会话中均可使用。

说明：支持 ANSI 颜色的终端中，`ready` 为绿色，`skill` 名称为橘色，`description` 为灰色。

示例：

```text
/skills list
```

输出示例（示意）：

```text
Skills (1/2 ready)
+-----------+-----------------------+-------------------------------------------------------------------------------------------+------------------------+
| Status    | Skill                 | Description                                                                               | Source                 |
+-----------+-----------------------+-------------------------------------------------------------------------------------------+------------------------+
| ✓ ready   | weather               | Get weather forecasts and current conditions for locations.                               | metis-workspace  |
| ✗ missing | summarize             | Summarize long text and produce concise takeaways.                                        | metis-bundled    |
+-----------+-----------------------+-------------------------------------------------------------------------------------------+------------------------+
```

### 4.2 ` /<skillName> `

用途：强制使用指定 skill。

示例：

```text
/weather 北京
/weather Shanghai tomorrow
/summarize "https://example.com/article"
```

### 4.3 ` /skills info <skillName> `

用途：查看某个 skill 的详细信息（标题状态 + Details + Requirements + Tip）。

说明：支持 ANSI 颜色的终端中，标题里的 skill 名称为橘色、`Ready` 为绿色（`Missing` 为红色），描述与 Tip 为灰色，`Details/Requirements` 标题为橙红色。

示例：

```text
/skills info weather
```

输出示例（示意）：

```text
❁ weather ✓ Ready

Get current weather and forecasts via wttr.in or Open-Meteo. Use when: user asks about weather, temperature, or forecasts for any location.

Details:
  Source: metis-workspace
  Path: C:\AI\code\Metis\skills\weather\SKILL.md
  Homepage: https://wttr.in/:help

Requirements:
  Binaries: ✓ curl

Tip: use `metis skills search`, `metis skills install`, and `metis skills update` for ClawHub-backed skills.
```

### 4.4 ` /skills check [--json] `

用途：输出本地技能状态检查报告（统计 + 可用列表 + 缺失原因列表）。

示例：

```text
/skills check
```

输出示例（示意）：

```text
Skills Status Check

Total: 12
✓ Eligible: 3
⚠ Disabled: 0
○ Blocked by allowlist: 0
✗ Missing requirements: 9

Ready to use:
  📦 weather
  🧾 summarize
  📦 clawhub

Missing requirements:
  🔐 1password (bins: op)
  📝 apple-notes (bins: memo; os: darwin)
```

### 4.5 ` /skills search [query] [--limit <n>] [--json] `

用途：搜索可安装 skill。当前会调用兼容的 skills CLI 查询 ClawHub skills 索引。

- 支持 `--limit <n>`
- 支持 `--json`
- 不带 query 时会浏览全部

示例：

```text
/skills search
/skills search weather
/skills search --json
/skills search --limit 20 weather
/skills search --limit 20 --json weather
/skills search react performance
```

### 4.6 ` /skills install <slug | owner/repo@skill> [--version <version>] [--force] `

用途：安装 skill。当前实现支持两种标识：

- ClawHub slug，例如 `weather`
- 兼容包标识，例如 `bys_skills/skills@find-skills`
- 支持 `--version <version>`
- 安装器透传的 `--force`

安装会落到当前工作区 `skills/` 目录；如果是 ClawHub slug，还会写入本地 `.clawhub` 跟踪元数据，供后续 update/info 使用。

示例：

```text
/skills install weather
/skills install weather --version 1.0.0
/skills install bys_skills/skills@find-skills
```

### 4.7 ` /skills update [slug | --all] `

用途：更新已安装 skill。

- 不带参数：更新已安装 skills，并刷新 tracked ClawHub skills 的本地版本元数据
- `--all`：与不带参数等价，显式更新全部 tracked ClawHub skills
- 带 `slug`：更新指定 tracked ClawHub skill

示例：

```text
/skills update
/skills update --all
/skills update weather
```

### 4.8 网关相关命令（配合 skills 场景常用）

```text
/dashboard
/cron ...
```

说明：

- `/dashboard`：打开 Dashboard，便于图形化查看/修改技能启用状态
- `/cron`：定时任务命令，与 skills 可组合使用（例如定时天气播报）

### 4.9 组合命令示例（可直接复制）

```text
# 1) 查看已有技能
/skills list

# 2) 看某个技能详情（含 location/frontmatter）
/skills info weather

# 3) 搜索新技能
/skills search summarize

# 4) 安装技能
/skills install weather
/skills install bys_skills/skills@find-skills

# 5) 检查生态状态
/skills check

# 6) 更新已安装技能
/skills update
/skills update weather

# 7) 显式触发技能
/weather Shanghai
```

## 5. 配置项说明

Skills 主要配置位于 `metis.json` 的 `skills` 节点：

```json
{
  "skills": {
    "enabled": true,
    "loadExtraDirs": [],
    "entries": {
      "weather": { "enabled": true },
      "summarize": { "enabled": false }
    }
  }
}
```

字段说明：

- `skills.enabled`
  - `true`：启用 skills 机制
  - `false`：关闭 skills 机制
- `skills.loadExtraDirs`
  - 额外扫描的 skill 根目录列表
- `skills.entries.<skillName>.enabled`
  - 单个 skill 开关
  - 仅当值明确为 `false` 时禁用，其它情况视为启用

## 6. SKILL.md 建议写法

`SKILL.md` 建议包含 frontmatter：

```yaml
---
name: weather
description: 获取天气与预报，适用于天气相关问题
---
```

可选字段（运行态会读取）：

- `requires_env`：依赖的环境变量，缺失时该 skill 会被跳过
- `homepage`：skill 主页（用于 `/skills info` 展示）

说明：

- `model`、`api_key`、`api_key_env` 不参与运行时模型/API Key 选择
- 即使写在 `SKILL.md` 中，也会被技能运行时忽略

## 7. 使用示例（按场景）

### 场景 A：查询天气

```text
/weather Shanghai
```

预期：强制命中 `weather`，执行天气工具链路并返回结果。

### 场景 B：自动技能匹配

```text
上海这周末天气怎么样？
```

预期：自动匹配 `weather`。

### 场景 C：技能禁用回退

配置：

```json
"entries": {
  "weather": { "enabled": false }
}
```

输入：

```text
/weather 上海
```

预期：不执行被禁用 skill 的工具路径，回退到通用回答策略。

### 场景 D：查看技能状态

```text
/skills
```

预期：按 `status | name | description | source` 展示每个 skill。

### 场景 E：搜索并安装 skill

```text
/skills search changelog
/skills install bys_skills/skills@find-skills
/skills check
```

预期：返回搜索结果、完成安装并可看到检查输出。

### 场景 F：Gateway 会话中使用 skills 命令

```text
/skills list
/skills info weather
/weather Beijing
```

预期：Gateway 与 CLI 命令语义一致，均可执行。

## 8. Dashboard 中的 Skills

在 Dashboard 的 Skills 页面可进行：

- 搜索 skill
- 查看描述
- 开关启用状态

推荐流程：

1. 启动网关：`cjpm run -- gateway serve`
2. CLI 输入：`/dashboard`
3. 在 Skills 页修改开关
4. 返回会话中用 `/skills list` 验证结果

## 9. 常见问题与排错

### 9.1 `/skills list` 看不到任何技能

检查：

- skill 目录是否存在
- 目录下是否有 `SKILL.md`
- `skills.enabled` 是否为 `true`
- `requires_env` 依赖环境变量是否已设置

### 9.2 明明有 skill，但没有被自动触发

建议：

- 优先使用显式触发：`/<skillName> ...`
- 检查 `SKILL.md` 的 `name`、`description` 是否清晰
- 检查该 skill 是否被 `entries` 禁用

### 9.3 指定 skill 后行为不符合预期

排查：

- skill 是否被禁用
- `requires_env` 依赖是否满足
- `SKILL.md` 中 `name/description` 是否清晰且可匹配

## 10. 最佳实践

- 对关键任务使用显式触发：`/<skillName> ...`
- 为每个 skill 编写清晰的 `description`
- 使用 `entries` 做分环境开关（开发/生产）
- 定期用 `/skills list` 检查发现与启用状态
- 将通用能力和专用能力拆成多个 skill，避免单 skill 过于臃肿
