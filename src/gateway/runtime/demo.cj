package metis.gateway.runtime

import metis.core.{gatewayClearSubagentNoticeDeliveryHook, gatewayClearSubagentNoticeEventHook, gatewayRegisterSubagentNoticeDeliveryHook}
import metis.core.config.{CliSettingManager, MetisConfigManager, MetisConfigWriteNotification}
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.gateway.gatewayPrepareStartupAuth
import metis.gateway.core.gatewayLogProcessMemory
import metis.core.memory.{DreamingPhaseRuntime, MemoryRuntime}
import metis.io.PrintUtils
import metis.gateway.model.ChatType
import magic.log.LogUtils
import std.time.*
import stdx.encoding.json.JsonObject

private func gatewayServeNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

private func gatewayServeTimingLog(step: String, startMs: Int64): Unit {
    let elapsedMs = gatewayServeNowMs() - startMs
    LogUtils.info("Gateway.serve.timing: step=${step} elapsedMs=${elapsedMs}")
    gatewayLogProcessMemory("serve:${step}", note: "elapsedMs=${elapsedMs}")
}

/**
 * Gateway P0 本地联调示例。
 *
 * 运行流程：
 * 1) 组装 Gateway + FeishuAdapter
 * 2) 启动网关
 * 3) 模拟一条飞书私聊入站消息
 * 4) 处理一次消息循环
 * 5) 输出发送日志，验证链路已打通
 */
public func runGatewayP0Demo(): Unit {
    let (gateway, feishu) = buildP0Gateway()
    gateway.start()

    // 注入一条模拟消息用于端到端验证。
    feishu.simulateIncomingText(
        "msg-demo-1",
        "chat-demo-1",
        "user-demo-1",
        "你好，Gateway P0",
        chatType: ChatType.Direct,
        mentioned: true
    )

    gateway.processOnce()
    let logs = feishu.getOutboundLog()

    PrintUtils.printLine("Gateway P0 demo finished. Outbound messages: ${logs.size}")
    for (msg in logs) {
        PrintUtils.printLine(" - channel=feishu peer=${msg.peerId} text=${msg.text}")
    }

    gateway.stop()
}

/**
 * Gateway P1 联调示例（飞书 webhook 文本事件）。
 */
public func runGatewayP1DemoWithFeishuWebhook(): Unit {
    let (gateway, feishu) = buildP0Gateway()
    gateway.start()

    let webhookPayload = """
{
  "schema": "2.0",
  "header": {
    "event_type": "im.message.receive_v1"
  },
  "event": {
    "sender": {
      "sender_id": {
        "open_id": "ou_demo_user"
      }
    },
    "message": {
      "message_id": "om_demo_message",
      "chat_id": "oc_demo_chat",
      "chat_type": "p2p",
      "message_type": "text",
      "content": "{\"text\":\"你好，请介绍一下你自己\"}"
    }
  }
}
"""
    let ack = feishu.ingestWebhookPayload(webhookPayload)
    PrintUtils.printLine("Feishu webhook ack: ${ack}")

    gateway.processOnce()
    let logs = feishu.getOutboundLog()
    PrintUtils.printLine("Gateway P1 demo finished. Outbound messages: ${logs.size}")
    for (msg in logs) {
        PrintUtils.printLine(" - channel=feishu peer=${msg.peerId} text=${msg.text}")
    }
    gateway.stop()
}

/**
 * 常驻模式：启动网关并循环处理消息。
 * 配置来自 `~/.metis/metis.json` 的 `gateway` 与可选环境变量；总开关为 `gateway.enabled`。
 */
public func runGatewayService(): Unit {
    let startMs = gatewayServeNowMs()
    gatewayServeTimingLog("enter", startMs)
    let persistedUser = CliSettingManager.readGatewaySettings()
    let (user, generatedAuthToken, _) = gatewayPrepareStartupAuth(persistedUser)
    LogUtils.info("Gateway.serve: read settings gateway.enabled=${user.enabled}")
    gatewayServeTimingLog("settings-ready", startMs)
    if (!user.enabled) {
        gatewayRuntimeMarkStopped(reason: "disabled")
        LogUtils.info("Gateway.serve: aborted (gateway.enabled=false)")
        gatewayServeTimingLog("disabled", startMs)
        PrintUtils.printLine(
            "网关总开关已关闭（metis.json 中 gateway.enabled=false）。执行：metis gateway master on"
        )
        return
    }
    if (!gatewayAcquireServeLockForRunningProcess()) {
        gatewayRuntimeMarkStopped(reason: "lock-not-acquired")
        LogUtils.error("Gateway.serve: aborted (serve lock not acquired; another instance or stale lock)")
        gatewayServeTimingLog("lock-failed", startMs)
        PrintUtils.printLine(
            "[网关] 无法启动：检测到已有网关实例在运行，或锁文件 ~/.metis/gateway-serve.lock 仍有效。请先关闭旧网关窗口后再试。"
        )
        return
    }
    gatewayRuntimeMarkStarting()
    LogUtils.info("Gateway.serve: serve lock acquired, building gateway service")
    gatewayServeTimingLog("lock-acquired", startMs)
    let (gateway, feishu) = buildGatewayServiceFromUserSettings(user)
    let gatewayCfg = buildGatewayConfigFromUserSettings(user)
    gatewayServeTimingLog("service-built", startMs)
    gatewayRegisterActiveService(gateway)
    gatewayRegisterSubagentNoticeDeliveryHook({ channelName, accountId, peerId, notice, replyToMessageId, replyInThread =>
        gateway.sendTextToPeerDetailed(
            channelName,
            peerId,
            notice,
            replyToMessageId: if (replyToMessageId.trimAscii().isEmpty()) { None<String> } else { Some<String>(replyToMessageId.trimAscii()) },
            replyInThread: replyInThread,
            accountId: accountId
        )
    })
    gatewayEnsureSubagentNoticeEventPublisherRegistered()
    GatewayServer.startGatewayServer(options: gatewayServerOptionsFromConfig(gatewayCfg))
    gatewayServeTimingLog("rpc-server-started", startMs)
    let cronRunner = CronRunner(
        gatewayOpt: Some(gateway),
        cronEnabled: user.cronEnabled
    )
    try {
        if (generatedAuthToken) {
            LogUtils.info(
                "Gateway.serve: startup auth generated runtime-only gateway.auth.token for this startup; config was not modified."
            )
        }
        let reconcileOut = DreamingPhaseRuntime.reconcileManagedCronJobs()
        if (!reconcileOut.trimAscii().isEmpty()) {
            LogUtils.info("Gateway.serve: dreaming reconcile => ${reconcileOut.replace("\n", " | ")}")
        }
        // Keep gateway control-plane startup compact. QMD maintenance/indexing can be
        // triggered manually instead of scanning the workspace during gateway boot.
        if (gatewayHttpAnyEndpointEnabled(gatewayCfg)) {
            GatewayHttpSurface.startIfNeeded(gatewayCfg)
            LogUtils.info("Gateway.serve: HTTP surface started at ${GatewayHttpSurface.baseUrl(gatewayCfg)}")
            gatewayServeTimingLog("http-started", startMs)
        }
        if (gatewayCfg.controlUi.enabled) {
            GatewayControlUiRuntime.startIfEnabled(gatewayCfg)
            let snapshot = GatewayControlUiRuntime.controlUiSnapshot(gatewayCfg)
            let rootState = gatewayControlUiRootStateJson(gatewayCfg)
            let assetMode = match (gatewayControlUiSnapshotJson(gatewayCfg).get("assetMode")) {
                case Some(v) =>
                    try { v.asString().getValue() } catch (_e: Exception) { "inline-fallback" }
                case None => "inline-fallback"
            }
            let rootKind = match (rootState.get("kind")) {
                case Some(v) =>
                    try { v.asString().getValue() } catch (_e: Exception) { "" }
                case None => ""
            }
            LogUtils.info("Gateway.serve: control UI embedded at ${snapshot.httpUrl} assetMode=${assetMode} rootState=${rootKind}")
            if (assetMode == "inline-fallback") {
                LogUtils.info("Gateway.serve: control UI is using legacy inline fallback; restore bundled static assets or set gateway.controlUi.root to a built static UI directory for the formal production path.")
            }
            gatewayServeTimingLog("control-ui-started", startMs)
        }
        gatewayPlatformMarkRunning(gatewayCfg)
        LogUtils.info("Gateway.serve: calling gateway.start()")
        gatewayServeTimingLog("gateway-start-begin", startMs)
        gateway.start()
        gatewayRuntimeMarkRunning()
        gatewayServeTimingLog("gateway-start-done", startMs)
        let reloadSnapshot = readGatewayConfigSnapshot()
        let reloadRoot = if (reloadSnapshot.valid) { reloadSnapshot.root } else { JsonObject() }
        let configReloader = GatewayConfigReloader(
            reloadRoot,
            GatewayServiceConfigReloadCallbacks(GatewayServiceReloadChannelRuntime(gateway))
        )
        let memoryArm = MemoryRuntime.armSearchBackend(purpose: "gateway-startup")
        match (memoryArm.manager) {
            case Some(manager) =>
                LogUtils.info(
                    "Gateway.serve: memory backend armed provider=${manager.backendConfig.providerId} backend=${manager.backendConfig.backend}"
                )
            case None =>
                let error = memoryArm.error.trimAscii()
                if (!error.isEmpty()) {
                    LogUtils.error("Gateway.serve: memory backend arm failed: ${error}")
                }
        }
        LogUtils.info(
            "Gateway.serve: gateway.start() returned, entering poll loop (IM/processOnce 200ms; cron tick 按需，臂长≤60s 对齐当前 armTimer 语义)"
        )
        LogUtils.info("Gateway.serve: cron store=${cronRunner.storeFilePath().toString()}")
        gatewayServeTimingLog("poll-loop-enter", startMs)
        feishu.printFeishuIngressHints()

        var heartbeatTick: Int64 = 0
        while (true) {
            gateway.processOnce()
            configReloader.pollOnce()
            cronRunner.tick()
            heartbeatTick += 1
            if (heartbeatTick % 50 == 0) {
                gatewayRefreshServeLockMtime()
                gatewayRuntimeHeartbeat()
                gatewayPlatformHeartbeat(gatewayCfg)
                // 无入站消息时文件里仍应有迹可循，便于区分「未拉到消息」与「进程未进循环」
                LogUtils.info("Gateway.serve: heartbeat pollTicks=${heartbeatTick} (~${heartbeatTick * 200 / 1000}s)")
            }
            sleep(Duration.millisecond * 200)
        }
    } finally {
        MetisConfigManager.setWriteRootNotificationHook(None<(MetisConfigWriteNotification) -> Unit>)
        try {
            gateway.stop()
        } catch (_: Exception) {
            ()
        }
        gatewayClearActiveService()
        gatewayClearSubagentNoticeDeliveryHook()
        gatewayClearSubagentNoticeEventHook()
        gatewayResetSubagentNoticeEventPublisherRegistration()
        GatewayHttpSurface.stopIfRunning()
        GatewayServer.defaultServer().stopServer(reason: "gateway-serve-shutdown")
        gatewayPlatformMarkStopped(gatewayCfg)
        MemoryRuntime.stopActiveMaintenance()
        gatewayRuntimeMarkStopped(reason: "shutdown")
        gatewayReleaseServeLockQuiet()
    }
}

/** 兼容旧参数 `--gateway-feishu-webhook`，行为与 `magic-cli gateway serve` 一致。 */
public func runFeishuWebhookGatewayService(): Unit {
    runGatewayService()
}
