# OpenClaw Plugin Compatibility Matrix

Generated: 2026-05-08T08:23:58.309Z

## Summary

- Plugins: 104
- Diagnostics: 1
- Release blockers: 105
- Release ready: no

### By Status

- `missing`: 104

### By Kind

- `browser`: 21
- `channel`: 32
- `cli`: 9
- `command`: 6
- `gateway-method`: 3
- `hook`: 1
- `http-route`: 8
- `media`: 59
- `memory`: 21
- `process`: 18
- `provider`: 53
- `realtime`: 64
- `service`: 7
- `setup`: 23
- `tool`: 15

## Plugins

| Plugin | Source | Source Ref | Entry | Version | Kinds | Runtime Facets | APIs | Smoke | Behavior | Status | Blockers | Gap |
|---|---|---|---|---:|---|---|---|---|---|---|---:|---|
| clawmate-companion | clawmate | 580e011 | packages/clawmate-companion/index.ts | 0.3.1 | media, realtime, tool | media, realtime, tool | registerTool | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, realtime, tool. |
| channels | openclaw-china | a36d023 | packages/channels/src/index.ts | 2026.3.9-1 | channel, cli | channel, cli | registerChannel, registerCli | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, cli. |
| dingtalk | openclaw-china | a36d023 | extensions/dingtalk/index.ts | 2026.3.9-1 | channel, media, realtime | channel, media, realtime | registerChannel | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, media, realtime. |
| feishu-china | openclaw-china | a36d023 | extensions/feishu/index.ts | 2026.3.9-1 | channel, media, realtime | channel, media, realtime | registerChannel | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, media, realtime. |
| qqbot | openclaw-china | a36d023 | extensions/qqbot/index.ts | 2026.3.9-1 | channel, media, memory, process, realtime | channel, media, memory, process, realtime | registerChannel | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, media, memory, process, realtime. |
| wechat-mp | openclaw-china | a36d023 | extensions/wechat-mp/index.ts | 0.1.0 | channel, cli, http-route, media, realtime | channel, cli, http-route, media, realtime | registerChannel, registerCli, registerHttpHandler, registerHttpRoute | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, cli, http-route, media, realtime. |
| wecom | openclaw-china | a36d023 | extensions/wecom/index.ts | 2026.3.9-1 | channel, http-route, media, realtime | channel, http-route, media, realtime | registerChannel, registerHttpHandler, registerHttpRoute | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, http-route, media, realtime. |
| wecom-app | openclaw-china | a36d023 | extensions/wecom-app/index.ts | 2026.3.9-1 | channel, http-route, media, process, realtime | channel, http-route, media, process, realtime | registerChannel, registerHttpHandler, registerHttpRoute | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, http-route, media, process, realtime. |
| wecom-kf | openclaw-china | a36d023 | extensions/wecom-kf/index.ts | 2026.3.9-1 | channel, cli, http-route, media | channel, cli, http-route, media | registerChannel, registerCli, registerHttpHandler, registerHttpRoute | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, cli, http-route, media. |
| openclaw-weixin | openclaw-weixin | archive-sha256:a7244892b3eca2abf1ca76879b4fc71e7f3090a68cbac888baa41b9e6e25e912 | index.ts | 2.1.7 | browser, channel, media, memory, realtime | browser, channel, media, memory, realtime | registerChannel | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, channel, media, memory, realtime. |
| acpx | openclaw | 3e72c0352d | extensions/acpx/index.ts | 2026.4.5 | process, realtime, service | process, realtime, service | registerService | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: process, realtime, service. |
| alibaba | openclaw | 3e72c0352d | extensions/alibaba/index.ts | 2026.4.5 | media, provider | media, provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider. |
| amazon-bedrock | openclaw | 3e72c0352d | extensions/amazon-bedrock/index.ts | 2026.4.5 | memory, provider, realtime | memory, provider, realtime | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: memory, provider, realtime. |
| amazon-bedrock-mantle | openclaw | 3e72c0352d | extensions/amazon-bedrock-mantle/index.ts | 2026.4.5 | provider, realtime | provider, realtime | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider, realtime. |
| anthropic | openclaw | 3e72c0352d | extensions/anthropic/index.ts | 2026.4.5 | media, provider | media, provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider. |
| anthropic-vertex | openclaw | 3e72c0352d | extensions/anthropic-vertex/index.ts | 2026.4.5 | provider | provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| bluebubbles | openclaw | 3e72c0352d | extensions/bluebubbles/index.ts | 2026.4.5 | browser, channel, media, memory, process, realtime, setup | browser, channel, media, memory, process, realtime, setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, channel, media, memory, process, realtime, setup. |
| brave | openclaw | 3e72c0352d | extensions/brave/index.ts | 2026.4.5 | provider, realtime | provider, realtime | registerWebSearchProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider, realtime. |
| browser | openclaw | 3e72c0352d | extensions/browser/index.ts | 2026.4.5 | browser, cli, gateway-method, media, memory, process, realtime, service, tool | browser, cli, gateway-method, media, memory, process, realtime, service, tool | registerCli, registerGatewayMethod, registerService, registerTool | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, cli, gateway-method, media, memory, process, realtime, service, tool. |
| byteplus | openclaw | 3e72c0352d | extensions/byteplus/index.ts | 2026.4.5 | media, provider | media, provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider. |
| chutes | openclaw | 3e72c0352d | extensions/chutes/index.ts | 2026.4.5 | browser, provider | browser, provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, provider. |
| cloudflare-ai-gateway | openclaw | 3e72c0352d | extensions/cloudflare-ai-gateway/index.ts | 2026.4.5 | provider | provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| comfy | openclaw | 3e72c0352d | extensions/comfy/index.ts | 2026.4.5 | media, provider, realtime | media, provider, realtime | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider, realtime. |
| copilot-proxy | openclaw | 3e72c0352d | extensions/copilot-proxy/index.ts | 2026.4.5 | provider | provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| deepgram | openclaw | 3e72c0352d | extensions/deepgram/index.ts | 2026.4.5 | media, provider, realtime | media, provider, realtime |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider, realtime. |
| deepseek | openclaw | 3e72c0352d | extensions/deepseek/index.ts | 2026.4.5 | provider | provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| device-pair | openclaw | 3e72c0352d | extensions/device-pair/index.ts |  | command, media, realtime, service | command, media, realtime, service | registerCommand, registerService | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: command, media, realtime, service. |
| diagnostics-otel | openclaw | 3e72c0352d | extensions/diagnostics-otel/index.ts | 2026.4.5 | service | service | registerService | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: service. |
| diffs | openclaw | 3e72c0352d | extensions/diffs/index.ts | 2026.4.5 | browser, http-route, media, realtime, tool | browser, http-route, media, realtime, tool | registerHttpRoute, registerTool | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, http-route, media, realtime, tool. |
| discord | openclaw | 3e72c0352d | extensions/discord/index.ts | 2026.4.5 | browser, channel, media, memory, realtime, setup | browser, channel, media, memory, realtime, setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, channel, media, memory, realtime, setup. |
| duckduckgo | openclaw | 3e72c0352d | extensions/duckduckgo/index.ts | 2026.4.5 | provider | provider | registerWebSearchProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| elevenlabs | openclaw | 3e72c0352d | extensions/elevenlabs/index.ts | 2026.4.5 | media, realtime | media, realtime |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, realtime. |
| exa | openclaw | 3e72c0352d | extensions/exa/index.ts | 2026.4.5 | provider, realtime | provider, realtime | registerWebSearchProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider, realtime. |
| fal | openclaw | 3e72c0352d | extensions/fal/index.ts | 2026.4.5 | media, provider | media, provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider. |
| feishu | openclaw | 3e72c0352d | extensions/feishu/index.ts | 2026.4.5 | browser, channel, media, memory, realtime, setup, tool | browser, channel, media, memory, realtime, setup, tool | registerTool | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, channel, media, memory, realtime, setup, tool. |
| firecrawl | openclaw | 3e72c0352d | extensions/firecrawl/index.ts | 2026.4.5 | provider, realtime, tool | provider, realtime, tool | registerTool, registerWebSearchProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider, realtime, tool. |
| fireworks | openclaw | 3e72c0352d | extensions/fireworks/index.ts | 2026.4.5 | provider | provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| github-copilot | openclaw | 3e72c0352d | extensions/github-copilot/index.ts | 2026.4.5 | browser, provider, realtime | browser, provider, realtime | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, provider, realtime. |
| google | openclaw | 3e72c0352d | extensions/google/index.ts | 2026.4.5 | browser, media, provider, realtime | browser, media, provider, realtime | registerProvider, registerWebSearchProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, media, provider, realtime. |
| googlechat | openclaw | 3e72c0352d | extensions/googlechat/index.ts | 2026.4.5 | channel, media, realtime, setup | channel, media, realtime, setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, media, realtime, setup. |
| groq | openclaw | 3e72c0352d | extensions/groq/index.ts | 2026.4.5 | media, provider | media, provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider. |
| huggingface | openclaw | 3e72c0352d | extensions/huggingface/index.ts | 2026.4.5 | provider | provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| imessage | openclaw | 3e72c0352d | extensions/imessage/index.ts | 2026.4.5 | channel, media, memory, process, realtime, setup | channel, media, memory, process, realtime, setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, media, memory, process, realtime, setup. |
| irc | openclaw | 3e72c0352d | extensions/irc/index.ts | 2026.4.5 | channel, media, process, realtime, setup | channel, media, process, realtime, setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, media, process, realtime, setup. |
| kilocode | openclaw | 3e72c0352d | extensions/kilocode/index.ts | 2026.4.5 | provider | provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| kimi | openclaw | 3e72c0352d | extensions/kimi-coding/index.ts | 2026.4.5 | provider | provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| line | openclaw | 3e72c0352d | extensions/line/index.ts | 2026.4.5 | channel, command, media, realtime, setup | channel, command, media, realtime, setup | registerCommand | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, command, media, realtime, setup. |
| litellm | openclaw | 3e72c0352d | extensions/litellm/index.ts | 2026.4.5 | provider | provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| llm-task | openclaw | 3e72c0352d | extensions/llm-task/index.ts | 2026.4.5 | realtime, tool | realtime, tool | registerTool | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: realtime, tool. |
| lobster | openclaw | 3e72c0352d | extensions/lobster/index.ts | 2026.4.5 | realtime, tool | realtime, tool | registerTool | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: realtime, tool. |
| matrix | openclaw | 3e72c0352d | extensions/matrix/index.ts | 2026.4.5 | channel, cli, gateway-method, media, memory, process, realtime, setup | channel, cli, gateway-method, media, memory, process, realtime, setup | registerCli, registerGatewayMethod | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, cli, gateway-method, media, memory, process, realtime, setup. |
| mattermost | openclaw | 3e72c0352d | extensions/mattermost/index.ts | 2026.4.5 | browser, channel, http-route, media, memory, realtime, setup | browser, channel, http-route, media, memory, realtime, setup | registerHttpRoute | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, channel, http-route, media, memory, realtime, setup. |
| memory-core | openclaw | 3e72c0352d | extensions/memory-core/index.ts | 2026.4.5 | cli, command, hook, media, memory, process, realtime, tool | cli, command, hook, media, memory, process, realtime, tool | registerCli, registerCommand, registerHook, registerMemoryEmbeddingProvider, registerTool | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: cli, command, hook, media, memory, process, realtime, tool. |
| memory-lancedb | openclaw | 3e72c0352d | extensions/memory-lancedb/index.ts | 2026.4.5 | cli, memory, process, realtime, service, tool | cli, memory, process, realtime, service, tool | registerCli, registerService, registerTool | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: cli, memory, process, realtime, service, tool. |
| microsoft | openclaw | 3e72c0352d | extensions/microsoft/index.ts | 2026.4.5 | media, realtime | media, realtime |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, realtime. |
| microsoft-foundry | openclaw | 3e72c0352d | extensions/microsoft-foundry/index.ts | 2026.4.5 | process, provider, realtime | process, provider, realtime | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: process, provider, realtime. |
| minimax | openclaw | 3e72c0352d | extensions/minimax/index.ts | 2026.4.5 | browser, media, provider, realtime | browser, media, provider, realtime | registerProvider, registerWebSearchProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, media, provider, realtime. |
| mistral | openclaw | 3e72c0352d | extensions/mistral/index.ts | 2026.4.5 | media, provider, realtime | media, provider, realtime | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider, realtime. |
| moonshot | openclaw | 3e72c0352d | extensions/moonshot/index.ts | 2026.4.5 | media, provider | media, provider | registerWebSearchProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider. |
| msteams | openclaw | 3e72c0352d | extensions/msteams/index.ts | 2026.4.5 | channel, media, memory, realtime, setup | channel, media, memory, realtime, setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, media, memory, realtime, setup. |
| nextcloud-talk | openclaw | 3e72c0352d | extensions/nextcloud-talk/index.ts | 2026.4.5 | channel, media, realtime, setup | channel, media, realtime, setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, media, realtime, setup. |
| nostr | openclaw | 3e72c0352d | extensions/nostr/index.ts | 2026.4.5 | channel, http-route, media, memory, realtime, setup | channel, http-route, media, memory, realtime, setup | registerHttpRoute | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, http-route, media, memory, realtime, setup. |
| nvidia | openclaw | 3e72c0352d | extensions/nvidia/index.ts | 2026.4.5 | provider | provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| ollama | openclaw | 3e72c0352d | extensions/ollama/index.ts | 2026.4.5 | browser, memory, provider, realtime | browser, memory, provider, realtime | registerMemoryEmbeddingProvider, registerProvider, registerWebSearchProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, memory, provider, realtime. |
| open-prose | openclaw | 3e72c0352d | extensions/open-prose/index.ts | 2026.4.5 | setup | setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: setup. |
| openai | openclaw | 3e72c0352d | extensions/openai/index.ts | 2026.4.5 | browser, media, memory, provider, realtime | browser, media, memory, provider, realtime | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, media, memory, provider, realtime. |
| opencode | openclaw | 3e72c0352d | extensions/opencode/index.ts | 2026.4.5 | provider | provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| opencode-go | openclaw | 3e72c0352d | extensions/opencode-go/index.ts | 2026.4.5 | provider | provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| openrouter | openclaw | 3e72c0352d | extensions/openrouter/index.ts | 2026.4.5 | media, provider | media, provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider. |
| openshell | openclaw | 3e72c0352d | extensions/openshell/index.ts | 2026.4.5 | browser, process | browser, process |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, process. |
| perplexity | openclaw | 3e72c0352d | extensions/perplexity/index.ts | 2026.4.5 | provider | provider | registerWebSearchProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| phone-control | openclaw | 3e72c0352d | extensions/phone-control/index.ts |  | command, realtime, service | command, realtime, service | registerCommand, registerService | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: command, realtime, service. |
| qa-channel | openclaw | 3e72c0352d | extensions/qa-channel/index.ts | 2026.4.4 | channel, realtime, setup | channel, realtime, setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, realtime, setup. |
| qa-lab | openclaw | 3e72c0352d | extensions/qa-lab/index.ts | 2026.4.4 | cli, media, memory, process, realtime | cli, media, memory, process, realtime | registerCli | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: cli, media, memory, process, realtime. |
| qianfan | openclaw | 3e72c0352d | extensions/qianfan/index.ts | 2026.4.5 | provider | provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| qqbot | openclaw | 3e72c0352d | extensions/qqbot/index.ts | 2026.4.5 | channel, command, media, memory, process, realtime, setup, tool | channel, command, media, memory, process, realtime, setup, tool | registerCommand, registerTool | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, command, media, memory, process, realtime, setup, tool. |
| qwen | openclaw | 3e72c0352d | extensions/qwen/index.ts | 2026.4.5 | media, provider | media, provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider. |
| runway | openclaw | 3e72c0352d | extensions/runway/index.ts | 2026.4.5 | media, provider | media, provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider. |
| searxng | openclaw | 3e72c0352d | extensions/searxng/index.ts | 2026.4.5 | provider, realtime | provider, realtime | registerWebSearchProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider, realtime. |
| sglang | openclaw | 3e72c0352d | extensions/sglang/index.ts | 2026.4.5 | provider | provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| signal | openclaw | 3e72c0352d | extensions/signal/index.ts | 2026.4.5 | channel, media, process, realtime, setup | channel, media, process, realtime, setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, media, process, realtime, setup. |
| slack | openclaw | 3e72c0352d | extensions/slack/index.ts | 2026.4.5 | channel, http-route, media, memory, realtime, setup | channel, http-route, media, memory, realtime, setup | registerHttpRoute | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, http-route, media, memory, realtime, setup. |
| stepfun | openclaw | 3e72c0352d | extensions/stepfun/index.ts | 2026.4.5 | provider | provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| synology-chat | openclaw | 3e72c0352d | extensions/synology-chat/index.ts | 2026.4.5 | browser, channel, media, realtime, setup | browser, channel, media, realtime, setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, channel, media, realtime, setup. |
| synthetic | openclaw | 3e72c0352d | extensions/synthetic/index.ts | 2026.4.5 | provider | provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| talk-voice | openclaw | 3e72c0352d | extensions/talk-voice/index.ts |  | command, media, realtime | command, media, realtime | registerCommand | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: command, media, realtime. |
| tavily | openclaw | 3e72c0352d | extensions/tavily/index.ts | 2026.4.5 | provider, realtime, tool | provider, realtime, tool | registerTool, registerWebSearchProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider, realtime, tool. |
| telegram | openclaw | 3e72c0352d | extensions/telegram/index.ts | 2026.4.5 | browser, channel, media, realtime, setup | browser, channel, media, realtime, setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, channel, media, realtime, setup. |
| thread-ownership | openclaw | 3e72c0352d | extensions/thread-ownership/index.ts |  | memory, realtime | memory, realtime |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: memory, realtime. |
| tlon | openclaw | 3e72c0352d | extensions/tlon/index.ts | 2026.4.5 | browser, channel, media, process, realtime, setup, tool | browser, channel, media, process, realtime, setup, tool | registerTool | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, channel, media, process, realtime, setup, tool. |
| together | openclaw | 3e72c0352d | extensions/together/index.ts | 2026.4.5 | media, provider | media, provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider. |
| twitch | openclaw | 3e72c0352d | extensions/twitch/index.ts | 2026.4.5 | channel, media, realtime | channel, media, realtime |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: channel, media, realtime. |
| venice | openclaw | 3e72c0352d | extensions/venice/index.ts | 2026.4.5 | provider | provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| vercel-ai-gateway | openclaw | 3e72c0352d | extensions/vercel-ai-gateway/index.ts | 2026.4.5 | provider | provider |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| vllm | openclaw | 3e72c0352d | extensions/vllm/index.ts | 2026.4.5 | provider | provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| voice-call | openclaw | 3e72c0352d | extensions/voice-call/index.ts | 2026.4.5 | browser, cli, gateway-method, media, memory, process, realtime, service, tool | browser, cli, gateway-method, media, memory, process, realtime, service, tool | registerCli, registerGatewayMethod, registerService, registerTool | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, cli, gateway-method, media, memory, process, realtime, service, tool. |
| volcengine | openclaw | 3e72c0352d | extensions/volcengine/index.ts | 2026.4.5 | provider | provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider. |
| vydra | openclaw | 3e72c0352d | extensions/vydra/index.ts | 2026.4.6 | media, provider | media, provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider. |
| whatsapp | openclaw | 3e72c0352d | extensions/whatsapp/index.ts | 2026.4.5 | browser, channel, media, realtime, setup | browser, channel, media, realtime, setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, channel, media, realtime, setup. |
| xai | openclaw | 3e72c0352d | extensions/xai/index.ts | 2026.4.5 | media, provider, realtime, tool | media, provider, realtime, tool | registerTool, registerWebSearchProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider, realtime, tool. |
| xiaomi | openclaw | 3e72c0352d | extensions/xiaomi/index.ts | 2026.4.5 | provider, realtime | provider, realtime |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: provider, realtime. |
| zai | openclaw | 3e72c0352d | extensions/zai/index.ts | 2026.4.5 | media, provider | media, provider | registerProvider | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: media, provider. |
| zalo | openclaw | 3e72c0352d | extensions/zalo/index.ts | 2026.4.5 | browser, channel, media, process, realtime, setup | browser, channel, media, process, realtime, setup |  | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, channel, media, process, realtime, setup. |
| zalouser | openclaw | 3e72c0352d | extensions/zalouser/index.ts | 2026.4.5 | browser, channel, media, realtime, setup, tool | browser, channel, media, realtime, setup, tool | registerTool | not-run | not-run | `missing` | 1 | Metis lacks zero-cost OpenClaw compatibility for capability kinds: browser, channel, media, realtime, setup, tool. |

## Release Blockers

- `release_status_not_ready` clawmate-companion: Compatibility status missing is not release-ready.
- `release_status_not_ready` channels: Compatibility status missing is not release-ready.
- `release_status_not_ready` dingtalk: Compatibility status missing is not release-ready.
- `release_status_not_ready` feishu-china: Compatibility status missing is not release-ready.
- `release_status_not_ready` qqbot: Compatibility status missing is not release-ready.
- `release_status_not_ready` wechat-mp: Compatibility status missing is not release-ready.
- `release_status_not_ready` wecom: Compatibility status missing is not release-ready.
- `release_status_not_ready` wecom-app: Compatibility status missing is not release-ready.
- `release_status_not_ready` wecom-kf: Compatibility status missing is not release-ready.
- `release_status_not_ready` openclaw-weixin: Compatibility status missing is not release-ready.
- `release_status_not_ready` acpx: Compatibility status missing is not release-ready.
- `release_status_not_ready` alibaba: Compatibility status missing is not release-ready.
- `release_status_not_ready` amazon-bedrock: Compatibility status missing is not release-ready.
- `release_status_not_ready` amazon-bedrock-mantle: Compatibility status missing is not release-ready.
- `release_status_not_ready` anthropic: Compatibility status missing is not release-ready.
- `release_status_not_ready` anthropic-vertex: Compatibility status missing is not release-ready.
- `release_status_not_ready` bluebubbles: Compatibility status missing is not release-ready.
- `release_status_not_ready` brave: Compatibility status missing is not release-ready.
- `release_status_not_ready` browser: Compatibility status missing is not release-ready.
- `release_status_not_ready` byteplus: Compatibility status missing is not release-ready.
- `release_status_not_ready` chutes: Compatibility status missing is not release-ready.
- `release_status_not_ready` cloudflare-ai-gateway: Compatibility status missing is not release-ready.
- `release_status_not_ready` comfy: Compatibility status missing is not release-ready.
- `release_status_not_ready` copilot-proxy: Compatibility status missing is not release-ready.
- `release_status_not_ready` deepgram: Compatibility status missing is not release-ready.
- `release_status_not_ready` deepseek: Compatibility status missing is not release-ready.
- `release_status_not_ready` device-pair: Compatibility status missing is not release-ready.
- `release_status_not_ready` diagnostics-otel: Compatibility status missing is not release-ready.
- `release_status_not_ready` diffs: Compatibility status missing is not release-ready.
- `release_status_not_ready` discord: Compatibility status missing is not release-ready.
- `release_status_not_ready` duckduckgo: Compatibility status missing is not release-ready.
- `release_status_not_ready` elevenlabs: Compatibility status missing is not release-ready.
- `release_status_not_ready` exa: Compatibility status missing is not release-ready.
- `release_status_not_ready` fal: Compatibility status missing is not release-ready.
- `release_status_not_ready` feishu: Compatibility status missing is not release-ready.
- `release_status_not_ready` firecrawl: Compatibility status missing is not release-ready.
- `release_status_not_ready` fireworks: Compatibility status missing is not release-ready.
- `release_status_not_ready` github-copilot: Compatibility status missing is not release-ready.
- `release_status_not_ready` google: Compatibility status missing is not release-ready.
- `release_status_not_ready` googlechat: Compatibility status missing is not release-ready.
- `release_status_not_ready` groq: Compatibility status missing is not release-ready.
- `release_status_not_ready` huggingface: Compatibility status missing is not release-ready.
- `release_status_not_ready` imessage: Compatibility status missing is not release-ready.
- `release_status_not_ready` irc: Compatibility status missing is not release-ready.
- `release_status_not_ready` kilocode: Compatibility status missing is not release-ready.
- `release_status_not_ready` kimi: Compatibility status missing is not release-ready.
- `release_status_not_ready` line: Compatibility status missing is not release-ready.
- `release_status_not_ready` litellm: Compatibility status missing is not release-ready.
- `release_status_not_ready` llm-task: Compatibility status missing is not release-ready.
- `release_status_not_ready` lobster: Compatibility status missing is not release-ready.
- `release_status_not_ready` matrix: Compatibility status missing is not release-ready.
- `release_status_not_ready` mattermost: Compatibility status missing is not release-ready.
- `release_status_not_ready` memory-core: Compatibility status missing is not release-ready.
- `release_status_not_ready` memory-lancedb: Compatibility status missing is not release-ready.
- `release_status_not_ready` microsoft: Compatibility status missing is not release-ready.
- `release_status_not_ready` microsoft-foundry: Compatibility status missing is not release-ready.
- `release_status_not_ready` minimax: Compatibility status missing is not release-ready.
- `release_status_not_ready` mistral: Compatibility status missing is not release-ready.
- `release_status_not_ready` moonshot: Compatibility status missing is not release-ready.
- `release_status_not_ready` msteams: Compatibility status missing is not release-ready.
- `release_status_not_ready` nextcloud-talk: Compatibility status missing is not release-ready.
- `release_status_not_ready` nostr: Compatibility status missing is not release-ready.
- `release_status_not_ready` nvidia: Compatibility status missing is not release-ready.
- `release_status_not_ready` ollama: Compatibility status missing is not release-ready.
- `release_status_not_ready` open-prose: Compatibility status missing is not release-ready.
- `release_status_not_ready` openai: Compatibility status missing is not release-ready.
- `release_status_not_ready` opencode: Compatibility status missing is not release-ready.
- `release_status_not_ready` opencode-go: Compatibility status missing is not release-ready.
- `release_status_not_ready` openrouter: Compatibility status missing is not release-ready.
- `release_status_not_ready` openshell: Compatibility status missing is not release-ready.
- `release_status_not_ready` perplexity: Compatibility status missing is not release-ready.
- `release_status_not_ready` phone-control: Compatibility status missing is not release-ready.
- `release_status_not_ready` qa-channel: Compatibility status missing is not release-ready.
- `release_status_not_ready` qa-lab: Compatibility status missing is not release-ready.
- `release_status_not_ready` qianfan: Compatibility status missing is not release-ready.
- `release_status_not_ready` qqbot: Compatibility status missing is not release-ready.
- `release_status_not_ready` qwen: Compatibility status missing is not release-ready.
- `release_status_not_ready` runway: Compatibility status missing is not release-ready.
- `release_status_not_ready` searxng: Compatibility status missing is not release-ready.
- `release_status_not_ready` sglang: Compatibility status missing is not release-ready.
- `release_status_not_ready` signal: Compatibility status missing is not release-ready.
- `release_status_not_ready` slack: Compatibility status missing is not release-ready.
- `release_status_not_ready` stepfun: Compatibility status missing is not release-ready.
- `release_status_not_ready` synology-chat: Compatibility status missing is not release-ready.
- `release_status_not_ready` synthetic: Compatibility status missing is not release-ready.
- `release_status_not_ready` talk-voice: Compatibility status missing is not release-ready.
- `release_status_not_ready` tavily: Compatibility status missing is not release-ready.
- `release_status_not_ready` telegram: Compatibility status missing is not release-ready.
- `release_status_not_ready` thread-ownership: Compatibility status missing is not release-ready.
- `release_status_not_ready` tlon: Compatibility status missing is not release-ready.
- `release_status_not_ready` together: Compatibility status missing is not release-ready.
- `release_status_not_ready` twitch: Compatibility status missing is not release-ready.
- `release_status_not_ready` venice: Compatibility status missing is not release-ready.
- `release_status_not_ready` vercel-ai-gateway: Compatibility status missing is not release-ready.
- `release_status_not_ready` vllm: Compatibility status missing is not release-ready.
- `release_status_not_ready` voice-call: Compatibility status missing is not release-ready.
- `release_status_not_ready` volcengine: Compatibility status missing is not release-ready.
- `release_status_not_ready` vydra: Compatibility status missing is not release-ready.
- `release_status_not_ready` whatsapp: Compatibility status missing is not release-ready.
- `release_status_not_ready` xai: Compatibility status missing is not release-ready.
- `release_status_not_ready` xiaomi: Compatibility status missing is not release-ready.
- `release_status_not_ready` zai: Compatibility status missing is not release-ready.
- `release_status_not_ready` zalo: Compatibility status missing is not release-ready.
- `release_status_not_ready` zalouser: Compatibility status missing is not release-ready.
- `source_missing` qmd: Source root not found: /Users/l3gi0n/work/workspace_cangjie/qmd

## Diagnostics

- `source_missing` qmd: Source root not found: /Users/l3gi0n/work/workspace_cangjie/qmd
