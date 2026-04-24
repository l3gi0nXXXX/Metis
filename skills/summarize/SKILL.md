---
name: summarize
description: Summarize or extract text/transcripts from URLs, podcasts, and local files (great fallback for “transcribe this YouTube/video”).
homepage: https://summarize.sh
metadata:
  {
    "metis":
      {
        "emoji": "🧾",
        "requires": { "bins": ["summarize"] },
        "install":
          [
            {
              "id": "brew",
              "kind": "brew",
              "formula": "steipete/tap/summarize",
              "bins": ["summarize"],
              "label": "Install summarize (brew)",
            },
          ],
      },
  }
---

# Summarize

Fast CLI to summarize URLs, local files, and YouTube links.

## Metis / magic-cli（必读）

- **不要默认用 Shell 执行本页中的 bash 示例。** 在 Windows 上 Shell 往往会落到 PowerShell/CMD，与 bash 的引号、管道、`|` 重定向等语义不一致，容易误触发 `curl`/`Invoke-WebRequest` 或解析失败。
- **Windows：禁止用 Shell 跑 `curl` 抓网页。** 在 PowerShell 里 `curl` 常是 **`Invoke-WebRequest` 的别名**，会出现 `Supply values for the following parameters: Uri:` 等**交互式**提示，自动化会卡死；与「用 summarize 拉 URL」无关时也不要用 `curl` 凑合。
- **`summarize` 未安装 / 提示 “not recognized” 时**：**不要**反复用 Shell 调 `summarize` 或假定 PATH 已有。应：说明需先安装并把可执行文件加入 PATH（见 summarize.sh）；**对 URL 摘要**：请用户**复制页面正文**到对话、或导出为本地文件后用 **读文件** 工具；若环境提供 **网页抓取 / MCP fetch**（非 Shell），可用其拉取后再由模型总结。**不要**因缺 CLI 就改用 `curl`。
- **优先顺序（在 CLI / 网关里）：**
  1. **本地文件**：先用内置 **读文件** 能力（如 `read_file` / 工作区文件工具）把正文读入，再由模型做摘要或抽取；**不要为了「走 summarize CLI」而先开 Shell。**
  2. **URL / YouTube**：仅当已确认本机存在 `summarize`（如用户说明已装，或你先说明风险后用户同意执行）再用 CLI；命令写成 **单行**，路径与引号按 **CMD 或当前 Shell** 规则，**不要**假设存在 `bash`。
  3. **仍缺工具时**：说明限制并建议用户在 **本机独立终端**（已配置好 `summarize` 与 PATH）中自行运行下方示例，而不是在代理里反复试 Shell。
- 下列 `bash` 代码块仅作 **参考** 与 **非 Metis 环境** 下使用；在本仓库交互中 **不** 将其当作首选执行方式。

## When to use (trigger phrases)

Use this skill immediately when the user asks any of:

- “use summarize.sh”
- “what’s this link/video about?”
- “summarize this URL/article”
- “transcribe this YouTube/video” (best-effort transcript extraction; no `yt-dlp` needed)

## 若无法使用 summarize CLI（尤其 Windows）

1. **先说明**：本机未安装或不在 PATH 时，不要继续用 Shell 调 `summarize`。
2. **URL 摘要**：请用户**粘贴页面正文**到对话，或保存为本地文件后走 **读文件**；若 IDE/环境提供 **非 Shell 的网页/MCP 获取**，可用之，再由模型归纳（勿用 Shell `curl`）。
3. **华为开发者等文档站**：同样适用；**禁止**用 `curl` 在 PowerShell 里硬拉以免卡在 `Uri:` 交互。

## Quick start

```bash
summarize "https://example.com" --model google/gemini-3-flash-preview
summarize "/path/to/file.pdf" --model google/gemini-3-flash-preview
summarize "https://youtu.be/dQw4w9WgXcQ" --youtube auto
```

## YouTube: summary vs transcript

Best-effort transcript (URLs only):

```bash
summarize "https://youtu.be/dQw4w9WgXcQ" --youtube auto --extract-only
```

If the user asked for a transcript but it’s huge, return a tight summary first, then ask which section/time range to expand.

## Model + keys

Set the API key for your chosen provider:

- OpenAI: `OPENAI_API_KEY`
- Anthropic: `ANTHROPIC_API_KEY`
- Deepseek: `DEEPSEEK_API_KEY`

Default model is `deepseek/deepseek-chat` if none is set.

## Useful flags

- `--length short|medium|long|xl|xxl|<chars>`
- `--max-output-tokens <count>`
- `--extract-only` (URLs only)
- `--json` (machine readable)
- `--firecrawl auto|off|always` (fallback extraction)
- `--youtube auto` (Apify fallback if `APIFY_API_TOKEN` set)

## Config

Optional config file: `~/.summarize/config.json`

```json
{ "model": "deepseek/deepseek-chat" }
```

Optional services:

- `FIRECRAWL_API_KEY` for blocked sites
- `APIFY_API_TOKEN` for YouTube fallback
