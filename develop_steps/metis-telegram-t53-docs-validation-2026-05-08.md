# Metis Telegram T53 文档与总体验收关闭矩阵

日期：2026-05-08

范围：本文件只覆盖 T53-14 文档、验收矩阵、CI/mock 回归建议。本文不声明业务代码已经实现；每个 gap 的关闭状态以对应 T53 阶段的实现和测试结果为准。

## 配置与测试隔离原则

所有 Telegram T53 回归测试必须使用临时 HOME、临时 `METIS_HOME`、临时 Metis config path、fake Telegram token、mock Telegram Bot API 和 mock Gateway/plugin/TTS provider。测试不得读取或写入真实 `~/.metis/metis.json`、真实 `~/.metis/gateway-telegram`、真实 Telegram token 文件、真实用户媒体目录或真实 Telegram 网络。

文档示例可以展示 `~/.metis/...` 作为生产配置位置，但测试、CI 和验收脚本必须显式覆盖为临时目录。涉及媒体保存、TTS 音频、target writeback、allowlist 写入和 plugin sidecar 的测试必须断言真实用户配置文件的 mtime 不变化，或在没有真实文件时断言不会创建该文件。

## TG52-GAP 到 T53 关闭矩阵

| Gap | T53 阶段 | 测试名 / 验收方式 | 关闭标准 |
|---|---|---|---|
| `TG52-GAP-01` `/allowlist` Telegram list/add/remove 缺口 | `T53-02`、`T53-14` | `telegram_native_allowlist_list_uses_temp_store`；`telegram_native_allowlist_add_remove_requires_approval`；文档 `docs/user/telegram.md` Native Commands 表 | `/allowlist list/add/remove` 在 mock Telegram sender 下可确定性返回；写配置只创建或消费 Gateway approval；测试不触碰真实 config。 |
| `TG52-GAP-02` `/skill` native skill runner 缺口 | `T53-07`、`T53-14` | `telegram_native_skill_runs_registered_skill`；`telegram_native_skill_missing_or_disabled_is_deterministic`；用户文档 `/skill` 行 | enabled skill 通过 Metis skill registry 执行；missing/disabled 返回明确错误；命令不进入模型猜测路径。 |
| `TG52-GAP-03` `/btw` transient turn 缺口 | `T53-07`、`T53-14` | `telegram_native_btw_transient_turn_does_not_write_main_transcript`；用户文档 `/btw` 行 | `/btw` 可返回 side question 答案；主 session transcript 不新增普通 user/assistant 对话；后续普通消息上下文不被污染。 |
| `TG52-GAP-04` `/tts` provider/limit/audio/on/off 缺口 | `T53-08`、`T53-14` | `telegram_native_tts_status_without_provider_reports_not_configured`；`telegram_native_tts_audio_uses_fake_provider_and_temp_file`；用户文档 TTS 小节 | 无 provider 时返回可操作诊断；fake provider 时生成临时 audio/voice 并走 Telegram send mock；prefs 和音频不写真实用户目录。 |
| `TG52-GAP-05` `/bash`、`/stop`、`/restart` 控制闭环缺口 | `T53-05`、`T53-06`、`T53-14` | `telegram_native_bash_creates_approval_without_exec`；`telegram_native_restart_requires_approval`；`telegram_native_stop_cancels_current_run_only`；用户文档权限/Approval 小节 | `/bash` 和 `/restart` 未批准前 executor/restart 调用次数为 0；批准后走 mock Gateway 控制面；`/stop` 只取消当前 Telegram session active run。 |
| `TG52-GAP-06` `/sessions`、`/approvals`、`/config`、`/mcp`、`/plugins`、`/debug` 管理能力缺口 | `T53-03`、`T53-04`、`T53-14` | `telegram_native_sessions_list_and_preview_from_temp_transcript`；`telegram_native_approvals_lists_pending_callbacks`；`telegram_native_config_get_redacts_secrets`；`telegram_native_config_set_creates_approval`；`telegram_native_plugin_debug_mutations_require_approval` | 只读命令直接返回脱敏摘要；写命令创建 approval；测试只读写临时 transcript/config/plugin fixture。 |
| `TG52-GAP-07` reaction 入站语义差异 | `T53-09`、`T53-14` | `telegram_reaction_update_records_system_event_without_agent_turn`；`telegram_reaction_unauthorized_sender_is_ignored`；用户文档 Reactions 语义 | reaction update 不触发 AgentBridge；授权 reaction 写入 system event/audit；普通文本仍触发 agent。 |
| `TG52-GAP-08` answer/reasoning streaming lane 缺口 | `T53-10`、`T53-14` | `telegram_streaming_answer_lane_edits_single_preview`；`telegram_streaming_reasoning_respects_session_setting`；用户文档 Draft / Streaming 小节 | answer delta 使用一个 preview message 和 edit 收敛；reasoning off 时不发送 reasoning lane；失败 fallback 不丢最终回复。 |
| `TG52-GAP-09` 长文本/forward burst debounce 缺口 | `T53-11`、`T53-14` | `telegram_debounce_merges_long_text_across_polling_batches`；`telegram_debounce_keeps_senders_and_commands_separate`；用户文档 Debounce 小节 | 跨 polling 批次长文本分片合并为一次 Gateway inbound turn；不同 sender、slash command、media group 不被错误合并。 |
| `TG52-GAP-10` live membership/security audit 缺口 | `T53-12`、`T53-14` | `telegram_audit_get_chat_member_member_and_admin_ok`；`telegram_audit_get_chat_member_left_or_kicked_warns`；`telegram_audit_redacts_token_on_failure`；用户文档 Audit 小节 | audit/doctor 输出 membership section；member/admin 为 ok，left/kicked 为 warning，网络/token 错误不泄露 token。 |
| `TG52-GAP-11` plugin interactive callback/command/hooks 兼容子集缺口 | `T53-13`、`T53-14` | `telegram_plugin_callback_maps_reply_edit_buttons_clear_delete`；`telegram_plugin_command_runs_via_native_entry`；`telegram_plugin_hook_failure_does_not_block_send`；用户文档 plugin 兼容限制 | fake plugin callback/command/hook 可在 mock sidecar 下验收；未支持 SDK API 返回 `unsupportedCapability`；sidecar 不接管 transport。 |
| 全部 gap 的文档、CI/mock 回归闭环 | `T53-00`、`T53-14` | `telegram_fixture_does_not_touch_real_metis_home`；CI job `telegram-native-mock-regression`；本文矩阵和 `docs/user/telegram.md` | 每个 T53 行有测试名或验收方式；CI 使用 mock Bot API 和临时配置；普通文本、媒体、callback、approval、plugin、TTS、audit 都有隔离守卫。 |

## CI/mock 回归建议

建议新增独立 CI job：`telegram-native-mock-regression`。该 job 不需要真实 Telegram token，也不允许访问真实 Telegram 网络。

推荐步骤：

1. 创建临时目录并导出 `HOME="$TMPDIR/home"`、`METIS_HOME="$TMPDIR/metis"`、`METIS_CONFIG="$TMPDIR/metis/metis.json"`。
2. 写入只含 fake token path 和 mock Telegram 配置的临时 `metis.json`。
3. 启动 mock Telegram Bot API server 或使用 adapter/transport fake，覆盖 `sendMessage`、`editMessageText`、`answerCallbackQuery`、`setMessageReaction`、`sendVoice`、`sendAudio`、`getChatMember`、`getFile`、file download。
4. 运行 Telegram native command/event 测试集合，至少覆盖 `/commands`、`/allowlist`、`/sessions`、`/approvals`、`/config`、`/mcp`、`/plugins`、`/debug`、`/bash`、`/restart`、`/stop`、`/skill`、`/btw`、`/tts`、reaction、streaming、debounce、audit、plugin callback。
5. 检查 mock server 未收到真实 token，日志中没有 token/proxy password/authorization header。
6. 检查真实 `~/.metis/metis.json` 没有被创建或 mtime 没有变化。

建议把真实网络测试留给用户显式配置的手动 smoke 流程。手动 smoke 必须在文档中说明风险：使用用户显式提供的 bot token、显式配置的临时或专用 Metis home、专用 Telegram chat，不复用个人媒体归档目录。

## 总体验收清单

| 验收项 | 方式 |
|---|---|
| Telegram 普通文本、图片保存、图片回传、voice/audio/video/document 保存和回传仍可用 | mock media inbound/outbound 测试；不使用真实媒体目录。 |
| `/commands` 展示的每个 command 都能调用并返回确定性结果 | command catalog 与 handler 状态测试。 |
| 管理和高风险命令有 approval 闭环 | mock Gateway approval store；未批准前断言无写配置、无 exec、无 restart。 |
| reaction 不触发模型回复 | AgentBridge mock 调用次数为 0。 |
| 长文本跨 polling 批次合并 | fake polling batch + timer debounce 测试。 |
| answer/reasoning streaming 有 delivery 验收 | fake Gateway delivery event 到 TelegramAdapter mock。 |
| live membership audit 有 getChatMember mock 验收 | mock member/admin/left/kicked/error 响应。 |
| OpenClaw-style plugin compatibility 线路 B 有 fake plugin 验收 | sidecar fake 覆盖 callback、command、hooks 和 unsupported capability。 |
| 所有测试隔离真实环境 | 测试前后检查真实 `~/.metis/metis.json`，并扫描日志脱敏。 |
| Cangjie 构建和测试 | 业务代码阶段运行 `source /Users/l3gi0n/cangjie100/envsetup.sh && cjpm clean && cjpm build -i && cjpm test`；纯文档阶段无需运行。 |

## 本阶段结论

T53-14 的产物是用户文档和关闭矩阵，不替代 T53-00 到 T53-13 的业务实现。后续每个实现阶段关闭 gap 时，应同步更新本矩阵中的测试名和验收结果，避免只在聊天回复中声明 gap 已关闭。
