# Metis AgentTeam Series 18 Phase 0-9 Integration Verification

日期：2026-05-15

## 合入范围

本轮以 `develop_steps/metis-agent-team-series-17-post-phase16-source-recheck-gap-quantification-manual-acceptance-2026-05-15.md` 为执行基线，通过独立 git worktree 并行完成 Phase 0-9，并按阶段合入主工作区。

| Phase | 合入提交 | 范围 |
| --- | --- | --- |
| 0-1 | `968b44a` | manual acceptance gate、CLI team update/binding 测试、RPC 验收证据 |
| 2 | `503eb45` | profile/model/auth 隔离测试，`agents.models.*` modelRef alias |
| 3 | `ec18f1a` | Telegram opt-in live gate、structured skipped evidence |
| 4-6 | `fbc2ff2` | Feishu auth/OAPI repair、token mode、fake success/auth/scope diagnostics |
| 7-9 | `a62bc43` | Feishu card/event/resource fake coverage、Control UI browser smoke、built assets |
| integration | pending final commit | `npm run build` 后的最终 Control UI built assets |

## 验证结果

| 验证项 | 结果 |
| --- | --- |
| `bash -n scripts/agentteam-manual-acceptance-gate.sh scripts/agentteam-manual-acceptance-gate-test.sh` | passed |
| `bash scripts/agentteam-manual-acceptance-gate-test.sh` | passed |
| `node --test scripts/agentteam-manual-acceptance-gate.test.mjs` | passed |
| `METIS_AGENTTEAM_SKIP_ENVSETUP=1 METIS_HOME=/tmp/metis-agentteam-s17-main-gate METIS_AGENTTEAM_REPORT_DIR=/tmp/metis-agentteam-s17-main-report scripts/agentteam-manual-acceptance-gate.sh` | passed |
| `npm --prefix ui test -- src/ui/controllers/agent-teams.metis.test.ts src/ui/views/agents-panel-teams.metis.test.ts src/ui/views/agents.metis.test.ts src/ui/metis-control-ui-browser-smoke.metis.test.ts --reporter verbose` | 34 passed |
| `npm --prefix ui run build` | passed |
| `npm --prefix ui test -- src/ui/metis-control-ui-browser-smoke.metis.test.ts --reporter verbose` | 2 passed |
| touched-area Cangjie focused tests | passed |
| `cjpm clean` | passed |
| `cjpm build -i` | passed |
| `cjpm test -j 1 --parallel 1` | final run passed: 1412 passed, 0 failed, 0 error |

完整最终 Cangjie 测试日志：`/tmp/metis-agentteam-s17-full-cjpm-test-20260516002703.log`。

## 说明

全量 `cjpm test -j 1 --parallel 1` 前两次出现过 runner 级间歇错误：一次为 `metis.program` / `metis.core.prompting` package `exit code = 9`，一次为 `GatewayServiceTelegramNativeTest.t44OpenClawPluginSidecarLoadsLocalPluginAndDispatchesRuntimeFacets` 单例 error。对应 package 或 test case 单独重跑均通过，`src/gateway/core` 全包也通过；第三次完整全量测试通过。

本轮没有使用真实 Telegram bot token、Feishu app secret、access token、refresh token 或真实 `~/.metis` 作为测试目标。manual gate 只写临时 redacted evidence pack。

## 仍需外部资源的 live 验收

以下项目仍不能由本地 fake tests 自动闭环，需要 operator 提供测试环境后执行：

| Live 项 | 所需资源 |
| --- | --- |
| Telegram account/group/topic route | 测试 bot、测试群、测试 topic、可脱敏 Gateway live 日志 |
| Telegram broadcast aggregate | 可用 team、测试 provider/model 凭证、测试群或私聊 |
| Feishu OAuth/UAT/TAT/app-scope | 测试 Feishu app/bot、测试租户、测试用户、user/app scopes |
| Feishu OAPI live read | 低风险 doc/wiki/calendar/task/bitable 等测试资源 ID |
| Feishu CardKit live | 测试群、CardKit 权限、可用 image key 或可降级测试素材 |
| Feishu rich events/resource read | 事件订阅、测试文件/消息、临时 cache 目录 |

