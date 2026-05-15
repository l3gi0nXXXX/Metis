# Metis AgentTeam Series 18 Phase 3 Telegram Completion

日期：2026-05-15
工作区：`.worktrees/agentteam-s17-phase3-20260515`
范围：Series 17 Phase 3 Telegram live route 验收准备与 fake/opt-in gate 补齐。

## 源码事实

| 能力 | 源码证据 | 结论 |
| --- | --- | --- |
| Telegram account route | `src/gateway/core/gateway_agent_route_resolver_test.cj:360-378` | fake test 覆盖 `telegram` accountId `bot-a` 解析到 `assistant-a`，并生成 agent-scoped sessionKey。 |
| Telegram group/topic session isolation | `src/gateway/core/gateway_agent_route_resolver_test.cj:380-397`、`src/gateway/channels/telegram/telegram_adapter_test.cj:412-437` | fake tests 覆盖 group route、topic route、topic inbound `imRoute`，并断言 topic 41/42 sessionKey 不相同。 |
| Telegram alias route | `src/gateway/channels/telegram/telegram_adapter_test.cj:440-460` | fake inbound 覆盖 `/agent writer` 和 `@writer` 路由到 writer，普通消息保持 default。 |
| Telegram broadcast aggregate | `src/gateway/core/gateway_agent_team_broadcast_test.cj:313-365` | fake test 覆盖 Telegram broadcast fan-out，aggregate rows 保留 member sessionKey 和答案顺序。 |
| Telegram live gate 缺资源语义 | `scripts/agentteam-manual-acceptance-gate.sh:66-78`、`scripts/agentteam-manual-acceptance-gate.sh:99-137`、`scripts/agentteam-manual-acceptance-gate.sh:370-379` | opt-in 但缺 live 资源时写 `status=skipped`、`reason=external-resource-required`，不访问真实 Telegram，不把缺资源当失败。 |

## 本阶段变更

| 文件 | 变更 |
| --- | --- |
| `scripts/agentteam-manual-acceptance-gate.sh` | 增加 Telegram live resource 状态判定、`requiredResources`、四项 `manualChecks`，并把缺资源 opt-in 降级为结构化 skipped。 |
| `scripts/agentteam-manual-acceptance-gate.test.mjs` | 新增 Node 回归测试，使用临时 `METIS_HOME` 和 report dir 验证 Telegram opt-in 缺资源时 gate exit 0 且 report 为 `external-resource-required`。 |
| `develop_steps/metis-agent-team-series-18-phase3-telegram-completion-2026-05-15.md` | 记录 Phase 3 源码事实、验收和剩余 live resource 阻塞项。 |

## 验收矩阵

| Phase 3 项 | fake/gate 覆盖 | live 状态 |
| --- | --- | --- |
| account route | `gateway_agent_route_resolver_test.cj` fake test；manual gate `account-route` | external resource required |
| group/topic session isolation | `gateway_agent_route_resolver_test.cj` 与 `telegram_adapter_test.cj` fake tests；manual gate `group-topic-session-isolation` | external resource required |
| alias route | `telegram_adapter_test.cj` fake test；manual gate `alias-route` | external resource required |
| broadcast aggregate | `gateway_agent_team_broadcast_test.cj` fake test；manual gate `broadcast-aggregate` | external resource required |

## 外部 live resource 阻塞项

真实 Telegram live route 仍需要以下用户提供的测试资源。资源缺失时 gate 应保持 `skipped/external-resource-required`，不算失败。

| 资源 | 用途 | 记录要求 |
| --- | --- | --- |
| Telegram test bot/account | account/direct route live smoke | 只记录 redacted account id，不记录 bot token。 |
| Telegram test group | group route 和 broadcast live smoke | 只记录 redacted chat id，不使用生产群。 |
| Telegram test topic/thread | topic session isolation live smoke | 只记录 redacted topic/thread id。 |
| Gateway log evidence | 确认 `Gateway.inbound: channel=telegram` 和 resolved agent/session | 不记录 token、proxy password、Authorization header 或真实用户私聊内容。 |

## Focused 验收命令

本阶段预期 focused checks：

```bash
node --test scripts/agentteam-manual-acceptance-gate.test.mjs
cjpm test --filter GatewayAgentRouteResolverTest --parallel 1 -j 1 src/gateway/core
cjpm test --filter GatewayAgentTeamBroadcastTest --parallel 1 -j 1 src/gateway/core
cjpm test --filter TelegramAdapterTest --parallel 1 -j 1 src/gateway/channels/telegram
METIS_AGENTTEAM_SKIP_ENVSETUP=1 METIS_HOME=/tmp/metis-agentteam-phase3-gate METIS_AGENTTEAM_LIVE_TELEGRAM=1 scripts/agentteam-manual-acceptance-gate.sh
```

完整 `cjpm build -i` 与全量 gate 由主工作区统一执行。
