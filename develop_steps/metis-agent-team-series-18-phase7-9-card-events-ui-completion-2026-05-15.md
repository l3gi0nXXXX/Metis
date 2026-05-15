# Metis AgentTeam Series 18: Phase 7-9 Card/Event/UI Completion

日期：2026-05-15
工作区：`.worktrees/agentteam-s17-phase7-9-20260515`

## 1. 源码事实补充

本轮先复核 Series 17 Phase 7-9 范围内的当前源码，不从文件名或预期能力推断结论。

| 范围 | 源码事实 | 状态 |
| --- | --- | --- |
| Feishu CardKit fake lifecycle | `src/gateway/channels/feishu/feishu_adapter_test.cj` 已覆盖 interactive card send/patch、streaming create/patch/finalize/abort/fallback、footer metrics、message unavailable、long text、markdown table、image key replacement 和 pending image 降级。 | fake coverage 已具备，需要补 live 缺资源输出口径。 |
| Feishu card checklist | `src/gateway/channels/feishu/feishu_cards.cj` 暴露 `FeishuCardLiveSmokeChecklist`，默认网络 disabled，需要 `METIS_FEISHU_LIVE_CARD_SMOKE` 显式 opt-in。 | 需要补 `skipped` + `external-resource-required` 的结构化报告。 |
| Feishu rich event replay | `src/gateway/channels/feishu/feishu_event_replay_samples.json` 和 `feishu_adapter_test.cj` 已覆盖 message/post/image/file/audio/video/interactive/card_action/reaction/drive/bot/vc/bitable 以及 ignored diagnostics。 | replay fake coverage 已具备，需要补 live 缺事件源输出口径。 |
| Feishu historical resource read | `src/gateway/tools/gateway_feishu_media_toolset.cj` 已把历史资源读取限制在 OAPI boundary，要求 safe `/tmp/metis-*` cache root，并在测试中覆盖 auth/scope/mime/size/not_found/rate_limit 诊断。 | fake/safe temp cache 已具备，需要补 live 缺测试消息/文件资源输出。 |
| Control UI runtime smoke | `ui/src/ui/metis-control-ui-browser-smoke.metis.test.ts` 已用真实 Chrome 打开 built `assets/control-ui`，检查 `customElements.get("metis-app")`、可见 Metis 文本、page errors/request failures、control token sessionStorage。 | 需要补 built JS raw decorator scan、JS/CSS 失败请求分类、favicon/touch-icon OpenClaw marker scan。 |

## 2. 本轮补齐口径

| Phase | 补齐项 | 验收项 |
| --- | --- | --- |
| Phase 7 | Card live parity 准备 | fake tests 继续覆盖 create/patch/finalize/abort/fallback、long text、markdown table、image key replacement/degrade；无测试 Feishu 群或 card 权限时输出 `status=skipped`、`reason=external-resource-required`、`networkAttempted=false`。 |
| Phase 8 | rich events/resource reads | event replay 继续使用 redacted fixtures；historical resource read 继续只写 safe temp cache；无真实 event subscription、message id、file key、resource scopes 时输出 `status=skipped`、`reason=external-resource-required`。 |
| Phase 9 | Control UI final gate | browser smoke 证明 built JS 无 raw TS decorator、`metis-app` 注册、页面有可见 Metis UI、无 JS/CSS asset failures、token bootstrap 写入 runtime 读取的 scoped sessionStorage、favicon/touch-icon 无 OpenClaw branding markers。 |

## 3. 外部 live 阻塞

真实 live 项仍需要用户提供测试 Feishu app/bot、测试租户、测试群/thread、事件订阅、CardKit 权限、低风险测试消息/文件资源和 scopes。没有这些资源时，本分支只记录 redacted `skipped/external-resource-required` 证据，不访问真实网络，不写真实 `~/.metis`。
