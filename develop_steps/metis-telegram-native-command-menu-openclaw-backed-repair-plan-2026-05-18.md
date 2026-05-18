# Metis Telegram Native Command Menu OpenClaw-Backed Repair Plan - 2026-05-18

## 1. 问题结论

Metis Telegram bot 中输入 `/` 不出现命令提示，是 Metis 注册 Telegram Bot API 原生命令菜单失败导致的真实缺陷。运行日志多次出现：

- `/Users/l3gi0n/.metis/logs/2026_05_18-12_49_15_670873000.log:216-220`
- `/Users/l3gi0n/.metis/logs/2026_05_18-12_34_45_967730000.log:216-220`
- `/Users/l3gi0n/.metis/logs/2026_05_18-12_18_24_825242000.log:224-228`

错误均为 `setMyCommands` 返回 `400 Bad Request: BOT_COMMAND_INVALID`。这说明 Telegram 已经收到 Metis 的 `setMyCommands` 请求，但请求体中至少有一个 `command` 不符合 Telegram Bot API 的命令名规则。

## 2. OpenClaw 源码依据

### 2.1 Telegram 命令名规则与规范化

OpenClaw 在 `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/telegram/src/command-config.ts:1` 定义 Telegram 命令名规则：

```ts
export const TELEGRAM_COMMAND_NAME_PATTERN = /^[a-z0-9_]{1,32}$/;
```

OpenClaw 在同文件 `:14-21` 规范化命令名：

1. `trim`
2. 去掉开头 `/`
3. 转小写
4. 将 `-` 替换成 `_`

这直接说明：`export-session` 不能原样发给 Telegram 菜单，应该在菜单注册层转换为 `export_session`。

### 2.2 菜单构造必须对所有来源统一校验

OpenClaw 在 `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/telegram/src/bot-native-commands.ts:491-562` 处理 native、custom、plugin 命令：

- `:497-519` 使用规范化后的 native/custom 名称建立保留集合与冲突集合。
- `:542-559` 对 native command 执行 `normalizeTelegramCommandName(command.name)`，并用 `TELEGRAM_COMMAND_NAME_PATTERN` 校验，校验失败则跳过。
- `:560-562` 再追加 plugin/custom 命令。

OpenClaw 在 `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/telegram/src/bot-native-command-menu.ts:138-175` 对 plugin 命令也使用同一套规范化与校验，避免不同来源走不同规则。

### 2.3 菜单同步路径

OpenClaw 在 `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/telegram/src/bot-native-command-menu.ts:259-340` 负责同步菜单：

- `:279-289` 先 `deleteMyCommands`
- `:300-319` 再 `setMyCommands`
- `:320-337` 对 `BOT_COMMANDS_TOO_MUCH` 做裁剪重试

Metis 已经有类似的 delete -> set 与 too-many 裁剪重试逻辑，因此本次不新增架构分支，只修复命令名规范化与执行兼容。

### 2.4 OpenClaw 测试已覆盖本问题

OpenClaw 在 `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/telegram/src/bot-native-commands.test.ts:142-164` 有明确测试：

- 菜单注册中必须出现 `export_session`
- 菜单注册中不得出现 `export-session`
- Telegram command handler 注册 `export_session`

OpenClaw 在同文件 `:166-204` 还验证 native、custom、plugin 的命令名都必须满足 `TELEGRAM_COMMAND_NAME_PATTERN`，并且 hyphen 命令会显示为 underscore 命令。

### 2.5 OpenClaw 文档说明

OpenClaw 在 `/Users/l3gi0n/work/workspace_cangjie/openclaw/docs/channels/telegram.md:308-347` 说明 Telegram command menu 由启动时的 `setMyCommands` 注册，`commands.native: "auto"` 会启用 native commands，并明确写出命令名规则：`a-z`、`0-9`、`_`、长度 `1..32`，custom command 不能覆盖 native command。

## 3. Metis 源码现状

### 3.1 Metis 已经会在启动时同步 Telegram 原生命令菜单

Metis 在 `src/gateway/config/gateway_builtin_adapter_factory.cj:75-79` 创建 `TelegramAdapter` 时传入 `registerNativeCommandsOnStart: true`。

Metis 在 `src/gateway/channels/telegram/telegram_adapter.cj:279-300` 的 `start` 流程会调用 `startNativeCommandSyncIfNeeded()`。

Metis 在 `src/gateway/channels/telegram/telegram_adapter.cj:5199-5281` 执行实际同步：

- `:5223-5239` 先 `deleteMyCommands`
- `:5240-5252` 再 `setMyCommands`
- `:5253-5272` 对 too-many 场景裁剪重试

所以本问题不是缺少菜单同步机制，而是同步 payload 中存在非法命令名。

### 3.2 Metis 内置命令中存在非法 Telegram 菜单命令名

Metis 在 `src/gateway/core/gateway_telegram_native_command_catalog.cj:80` 定义：

```cangjie
spec("export-session", "Export current session transcript.", "status", aliases: ["export"], args: ["path"]),
```

`export-session` 包含 `-`，不符合 Telegram 的 `[a-z0-9_]{1,32}` 规则。

### 3.3 Metis 只对 plugin/custom 命令规范化，没有对 builtin 命令规范化

Metis 在 `src/gateway/channels/telegram/telegram_adapter.cj:5346-5380` 构造菜单：

- `:5351-5354` builtin/native 命令直接 `rows.add((command, description))`
- `:5356-5379` plugin/custom 命令才调用 `normalizeTelegramCommandName`

因此 `export-session` 会原样进入 `setMyCommands` payload，触发日志中的 `BOT_COMMAND_INVALID`。

### 3.4 Metis 现有规范化函数缺少 OpenClaw 的 hyphen -> underscore 行为

Metis 在 `src/gateway/channels/telegram/telegram_adapter.cj:5405-5422` 的 `normalizeTelegramCommandName` 只允许 `a-z`、`0-9`、`_`。它没有将 `-` 转成 `_`，而是直接返回空字符串。

Metis 在 `src/gateway/core/gateway_service.cj:2185-2202` 还有一份用于 custom command 执行侧的同名规范化逻辑，同样没有 hyphen -> underscore 行为。若只修复菜单侧，自定义命令 `custom-backup` 会显示成 `/custom_backup`，但执行侧仍可能无法匹配。

### 3.5 Metis 测试缺少关键看护

Metis 在 `src/gateway/channels/telegram/telegram_adapter_test.cj:718-735` 只验证菜单数量和部分命令存在，没有验证所有 `command` 都符合 Telegram 规则，也没有验证 `export-session` 被注册为 `export_session`。

Metis 在 `src/gateway/core/gateway_service_telegram_native_test.cj:1653` 覆盖 `/export-session`，但没有覆盖 Telegram 菜单实际会发出的 `/export_session`。

## 4. 修补原则

1. 不改 Telegram transport、session、model、control-ui、agent team 架构边界。
2. 保持 Metis 现有 Gateway/Telegram native command 架构，只在 native command menu 生成、命令规范化、命令分发兼容层修复。
3. 参考 OpenClaw 的事实行为：菜单注册名使用 Telegram-safe 名称，业务命令可以保留内部 canonical 名称。
4. 不使用真实 Telegram 网络、真实 bot token、真实用户配置进行测试。
5. 测试必须覆盖“payload 不含非法命令名”，避免以后新增内置命令再次把非法名称发给 Bot API。

## 5. 分阶段落地方案与验收项

### Phase 0：冻结证据与回归目标

实施方案：

1. 保留本文件作为问题证据、OpenClaw 源码依据、Metis 源码依据和阶段验收清单。
2. 根因固定为：Metis 的内置 native command `export-session` 未经 Telegram-safe 规范化进入 `setMyCommands` payload。
3. 回归目标固定为：Metis 注册 Telegram 菜单时不再出现 `BOT_COMMAND_INVALID`，且 Telegram 客户端输入 `/` 能看到菜单提示。

源码依据：

- OpenClaw 命令名规则：`openclaw/extensions/telegram/src/command-config.ts:1`
- OpenClaw hyphen 转 underscore：`openclaw/extensions/telegram/src/command-config.ts:14-21`
- Metis 非法内置命令：`src/gateway/core/gateway_telegram_native_command_catalog.cj:80`
- Metis builtin 未规范化：`src/gateway/channels/telegram/telegram_adapter.cj:5351-5354`
- 运行日志错误：`~/.metis/logs/2026_05_18-12_49_15_670873000.log:216-220`

验收项：

1. 本文件存在于 `develop_steps/metis-telegram-native-command-menu-openclaw-backed-repair-plan-2026-05-18.md`。
2. 本文件列出 OpenClaw 源码文件、Metis 源码文件和日志证据。
3. 后续代码实现不得绕开本文件列出的架构边界。

### Phase 1：菜单侧命令名规范化对齐 OpenClaw

实施方案：

1. 修改 `src/gateway/channels/telegram/telegram_adapter.cj` 中的 `normalizeTelegramCommandName`。
2. 对齐 OpenClaw `command-config.ts:14-21`：
   - 去掉开头 `/`
   - 转小写
   - 将 `-` 替换为 `_`
   - 保留 `[a-z0-9_]` 和长度 `1..32` 校验
3. 不放宽空格、`@`、`!`、中文、超过 32 字符等非法命令名。

源码依据：

- OpenClaw：`openclaw/extensions/telegram/src/command-config.ts:14-21`
- Metis 待改函数：`src/gateway/channels/telegram/telegram_adapter.cj:5405-5422`

验收项：

1. `TelegramAdapter.debugBuildNativeCommandsPayload()` 生成的命令名中不包含 `-`。
2. 配置自定义命令 `custom-backup` 时，payload 中显示 `custom_backup`。
3. 配置自定义命令 `bad name` 或 `bad$name` 时，payload 不包含该命令。
4. 配置长度超过 32 的命令名时，payload 不包含该命令。

### Phase 2：builtin/native 菜单条目也必须经过同一规范化路径

实施方案：

1. 修改 `src/gateway/channels/telegram/telegram_adapter.cj` 的 `resolvedTelegramCommandMenu()`。
2. 对 `gatewayTelegramNativeCommandMenuRows()` 返回的 builtin/native 命令执行 `normalizeTelegramCommandName`。
3. 对 builtin/native 的 description 执行 `trimAscii()`，空命令名或空描述跳过。
4. `seen` 集合使用规范化后的命令名，避免 `export-session` 与 `export_session` 或 custom/plugin 同名冲突。
5. 保持 builtin/native 命令优先级：custom/plugin 不允许覆盖 native 命令。

源码依据：

- OpenClaw native 命令规范化与校验：`openclaw/extensions/telegram/src/bot-native-commands.ts:542-559`
- OpenClaw reserved/existing command 使用规范化名称：`openclaw/extensions/telegram/src/bot-native-commands.ts:497-519`
- Metis builtin 当前未规范化：`src/gateway/channels/telegram/telegram_adapter.cj:5351-5354`
- Metis plugin/custom 当前已有规范化：`src/gateway/channels/telegram/telegram_adapter.cj:5356-5379`

验收项：

1. `nativeCommandsPayloadUsesTelegramMenuShape` 断言 payload 包含 `export_session`。
2. `nativeCommandsPayloadUsesTelegramMenuShape` 断言 payload 不包含 `export-session`。
3. `nativeCommandsPayloadUsesTelegramMenuShape` 遍历所有 command，断言：
   - 不为空
   - 长度 `1..32`
   - 每个字符属于 `a-z`、`0-9`、`_`
4. 自定义命令 `export_session` 不得覆盖 builtin `export-session` 映射出来的菜单项。

### Phase 3：执行侧兼容 Telegram 菜单发出的 underscore 命令

实施方案：

1. 在 `src/gateway/core/gateway_telegram_native_command_catalog.cj` 中给 canonical 命令 `export-session` 增加 alias `export_session`。
2. 保持 canonical 命令仍为 `export-session`，不重命名内部 handler，不改已有 `/export-session` 兼容性。
3. `gatewayFindTelegramNativeCommandSpec("/export_session")` 应返回 `spec.command == "export-session"`。
4. `GatewayService.renderTelegramNativeCommand` 中现有 `case "export-session"` 保持不变，因为 alias 解析后会回到 canonical command。
5. 修改 `src/gateway/core/gateway_service.cj` 的 custom command 规范化函数，使 custom command 执行侧也采用 hyphen -> underscore 规则。否则菜单显示 `/custom_backup` 后，执行侧无法匹配配置里的 `custom-backup`。

源码依据：

- OpenClaw handler 注册使用规范化命令名：`openclaw/extensions/telegram/src/bot-native-commands.ts:705-708`
- OpenClaw 测试要求 handler 为 `export_session`：`openclaw/extensions/telegram/src/bot-native-commands.test.ts:142-164`
- Metis canonical handler：`src/gateway/core/gateway_service.cj:2080`
- Metis command spec alias 查找：`src/gateway/core/gateway_telegram_native_command_catalog.cj:119-135`
- Metis custom command 执行侧规范化：`src/gateway/core/gateway_service.cj:2135-2138`、`:2185-2202`

验收项：

1. 新增测试：`gatewayFindTelegramNativeCommandSpec("/export_session")` 返回 `Some`，且 `spec.command == "export-session"`。
2. 新增或更新 Telegram native service 测试：发送 `/export_session` 后进入 export session native handler，而不是进入模型普通消息路径。
3. 原有 `/export-session` 测试仍通过。
4. 自定义命令配置为 `custom-backup`，用户发送 `/custom_backup arg` 时能匹配 custom command 并返回配置 reply。

### Phase 4：测试覆盖所有菜单来源的 Telegram-safe payload

实施方案：

1. 更新 `src/gateway/channels/telegram/telegram_adapter_test.cj`。
2. 增加本地 helper，遍历 payload 中每个 `command` 字符，验证满足 Telegram 规则。
3. 将当前 `Bad-Name` 测试数据调整为真正非法的 `Bad Name` 或 `bad$name`，因为按 OpenClaw 规则 `Bad-Name` 应被规范化为 `bad_name`，不再是非法。
4. 增加 hyphen 自定义命令测试，证明 `generate-image` 或 `custom-backup` 会注册为 `generate_image` 或 `custom_backup`。
5. 保留 too-many 裁剪测试和失败可见性测试，不把 Bot API 网络错误吞掉。

源码依据：

- OpenClaw 全来源 safe command 测试：`openclaw/extensions/telegram/src/bot-native-commands.test.ts:166-204`
- Metis payload 测试缺口：`src/gateway/channels/telegram/telegram_adapter_test.cj:718-735`
- Metis invalid/custom 测试现状：`src/gateway/channels/telegram/telegram_adapter_test.cj:768-786`
- Metis failure visible 测试：`src/gateway/channels/telegram/telegram_adapter_test.cj:906-917`

验收项：

1. `nativeCommandsPayloadUsesTelegramMenuShape` 覆盖所有 command 的合法性。
2. `nativeCommandsPayloadSkipsCustomConflictsAndInvalidNames` 仍能证明冲突和非法命令会被跳过。
3. 新增/更新测试证明 hyphen custom command 被规范化为 underscore。
4. 测试不访问真实 Telegram 网络，不读取真实 bot token，不修改 `~/.metis`。

### Phase 5：运行时诊断保持可解释

实施方案：

1. 不改变现有 `setMyCommands` 失败日志路径，保持 `nativeCommandsLastSyncStatus/error` 可见。
2. 在已有健康快照测试基础上，确保失败信息仍会进入 `nativeCommands.lastSyncError`。
3. 本次不引入新的诊断架构，只保证 payload 修复后常规启动不会再因为非法命令名失败。

源码依据：

- Metis sync 失败日志：`src/gateway/channels/telegram/telegram_adapter.cj:5248-5275`
- Metis native command health snapshot：`src/gateway/channels/telegram/telegram_adapter.cj:5309-5327`
- Metis failure visible 测试：`src/gateway/channels/telegram/telegram_adapter_test.cj:906-917`

验收项：

1. `nativeCommandRegistrationFailureIsVisibleInHealthSnapshot` 继续通过。
2. 本地 fake transport 返回 `Bad Request` 时，`lastSyncStatus == "error"`。
3. 正常 fake transport 下，`debugSyncNativeCommandsForTest()` 返回 `true`。

### Phase 6：文档与用户手工验收步骤

实施方案：

1. 在本文件中保留手工验收步骤，避免用户只看到代码提交而不知道如何确认。
2. 手工验收只描述用户操作，不要求测试用例访问真实 Telegram。

手工验收步骤：

1. 重启 gateway：
   ```bash
   source /Users/l3gi0n/cangjie100/envsetup.sh
   cjpm run --skip-build --name metis --run-args "gateway run"
   ```
2. 在另一个终端查看最新日志：
   ```bash
   rg -n "setMyCommands|BOT_COMMAND_INVALID|nativeCommands" ~/.metis/logs
   ```
3. 打开 Telegram bot 会话，输入 `/`。
4. 观察命令提示列表是否出现 `help`、`commands`、`status`、`models`、`export_session` 等命令。
5. 在 Telegram 发送 `/export_session`。

验收标准：

1. 最新日志中不再出现 `Bad Request: BOT_COMMAND_INVALID`。
2. Telegram 输入 `/` 可以弹出命令提示。
3. 菜单中显示 `export_session`，不显示非法的 `export-session`。
4. 发送 `/export_session` 会进入原 `export-session` 导出会话处理逻辑。
5. 发送 `/export-session` 仍保持兼容。

### Phase 7：统一构建与测试

实施方案：

1. 所有 worktree 修改合并回本地 `main` 后，统一执行：
   ```bash
   source /Users/l3gi0n/cangjie100/envsetup.sh
   cjpm clean
   cjpm build -i
   cjpm test
   ```
2. 如果出现编译或测试失败，先定位失败文件和失败断言，再修复到问题清零。

验收项：

1. `cjpm clean` 成功。
2. `cjpm build -i` 成功。
3. `cjpm test` 成功。
4. `git status --short` 只包含本次修复相关文件，且无临时 worktree 产物。

## 6. 预期变更文件

1. `src/gateway/channels/telegram/telegram_adapter.cj`
2. `src/gateway/channels/telegram/telegram_adapter_test.cj`
3. `src/gateway/core/gateway_telegram_native_command_catalog.cj`
4. `src/gateway/core/gateway_service.cj`
5. `src/gateway/core/gateway_service_telegram_native_test.cj`
6. `develop_steps/metis-telegram-native-command-menu-openclaw-backed-repair-plan-2026-05-18.md`

## 7. 非目标

1. 不改 Telegram bot token、BotFather 配置、代理配置或真实用户配置。
2. 不改 Gateway session、model、control-ui、agent team 的架构。
3. 不新增真实 Telegram 网络测试。
4. 不把内部 canonical 命令 `export-session` 全局重命名为 `export_session`，只在 Telegram 菜单注册和 alias 执行层兼容。
