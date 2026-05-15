# Metis AgentTeam Series 18 Phase 2 Completion Note

日期：2026-05-15
工作区：`/Users/l3gi0n/work/workspace_cangjie/Metis/.worktrees/agentteam-s17-phase2-20260515`
范围：Series 17 Phase 2 Agent profile / model / auth 隔离验收。

## 源码复核事实

| 能力 | 源码证据 | 结论 |
| --- | --- | --- |
| 支持的 profile 文件 | `src/core/prompting/metis_workspace_bootstrap.cj:190-200` 列出 `AGENTS.md`、`SOUL.md`、`TOOLS.md`、`IDENTITY.md`、`USER.md`、`HEARTBEAT.md`、`BOOTSTRAP.md`、`MEMORY.md`。 | Phase 2 需要直接验收 8 个 supported profile。 |
| `agents.files.list/get/set` | `src/gateway/runtime/gateway_server_methods_agents.cj:1594-1631` 从 supported profile 生成列表；`src/gateway/runtime/gateway_server_methods_agents.cj:1634-1661` 通过 workspace safe read/write 读取和写入。 | 可用 focused RPC 测试证明默认 7 个文件存在、`BOOTSTRAP.md` 初始 missing、`set` 后可读。 |
| `agents.models.get/set` | `src/gateway/runtime/gateway_server_methods_agents.cj:1758-1813` 按 resolved agent scope 选择 `agentDir/models.json`，读写均使用该路径。 | 可用 agent-a/agent-b 双 agent 测试证明 `models.json` 路径不同且 runtime model 不串用。 |
| model runtime state | `src/core/config/model_runtime_state_manager.cj:252-272` 从 scope materialize `primaryModelRef` 和 `runtimePrimaryModelRef`，并携带 credential source summary；`src/gateway/runtime/gateway_server_methods_agents.cj:1738-1744` 现在返回只读 `models.modelRef` alias。 | `models.modelRef` 来源是 runtime state 的 `runtimePrimaryModelRef`，为空时退回 `primaryModelRef`，用于直接验收 per-agent modelRef 不串用。 |
| auth source order | `src/core/config/metis_agent_scope.cj:865-923` 只检查当前 agent 的 `agentDir/auth-profiles.json`、当前 agent 的 `agentDir/models.json` provider、root `models.providers` 和 env，不读取 main 或其他 agent 的 `auth-profiles.json`。 | 未显式复制时 agentB 不应读取 agentA/main auth profile。 |
| redaction | `src/gateway/runtime/gateway_server_methods_agents.cj:1664-1707` redacts secret-like keys before returning model state and credential source。 | 验收输出必须不含 `apiKey`、secret literal 或 Authorization header。 |

## Phase 2 验收项

| 子阶段 | focused 验收 | 状态 |
| --- | --- | --- |
| 2.1 profile 文件语义 | `GatewayServerMethodsAgentsTest.agentFilesRpcUsesWorkspaceSafeBootstrapFiles` 断言 supported profile 正好 8 个、默认 present 7 个、`BOOTSTRAP.md` 初始 missing，8 个文件均可 `agents.files.set` 后 `agents.files.get` 读回。 | passed |
| 2.2 per-agent model 隔离 | `GatewayServerMethodsAgentsTest.agentAAgentBModelsRpcKeepsModelsJsonPathAndModelRefSeparate` 使用 path-safe agent ids `agent-a` / `agent-b`，断言两者 `models.json` 路径不同，`modelRef`、`runtimePrimaryModelRef` 和文件内容不串用。 | passed |
| 2.3 per-agent auth 隔离 | `GatewayServerMethodsAgentsTest.agentBWithoutExplicitAuthCopyDoesNotReadAgentAOrMainCredentialsAndRedactsOutput` 断言未显式复制时 agent-b 不读取 agent-a/main 凭证，agent-a 可看到自己的 configured summary，输出不含 secret literal、`apiKey` value field 或 Authorization。 | passed |

## 验证命令

运行前需要加载 Cangjie 环境并把 stdx dynamic lib 加入 `DYLD_LIBRARY_PATH`，否则测试二进制会因找不到 `libstdx.encoding.json.dylib` 在启动阶段退出。

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/Users/l3gi0n/work/workspace_cangjie/CangjieMagic/libs/cangjie-stdx-mac-aarch64-1.0.0.1/darwin_aarch64_llvm/dynamic/stdx:/opt/homebrew/opt/openssl@3/lib:/opt/homebrew/opt/openssl@3.5/lib:/usr/local/opt/openssl@3/lib:${DYLD_LIBRARY_PATH:-}"
cjpm test src/gateway/runtime --filter GatewayServerMethodsAgentsTest --no-color --parallel 1
cjpm test src/core/config --filter MetisAgentScopeTest --no-color --parallel 1
```

结果：

- `GatewayServerMethodsAgentsTest`: 44 passed, 264 skipped, 0 failed.
- `MetisAgentScopeTest`: 15 passed, 40 skipped, 0 failed.

## 外部 live resource

本 Phase 只做临时 `METIS_HOME` 下的 focused source/RPC 验收，不访问真实 Telegram、Feishu、真实 provider token 或真实 `~/.metis`。真实 Telegram bot、Feishu app/bot、租户、群、线程、scopes、provider 凭证仍属于后续 live evidence 阻塞项。
