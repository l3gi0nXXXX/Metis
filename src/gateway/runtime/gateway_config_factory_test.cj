package metis.gateway.runtime

import metis.core.config.{CliConfig, GatewayUserSettings}
import metis.gateway.channels.feishu.FeishuAdapter
import metis.gateway.channels.qq.QQAdapter
import metis.gateway.channels.telegram.TelegramAdapter

import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

private func withGatewayConfigFactoryTestHome<T>(block: () -> T): T {
    let testHome = "/tmp/metis-gateway-config-factory-test-home"
    try {
        remove(Path(testHome), recursive: true)
    } catch (_: Exception) {
        ()
    }
    Directory.create(testHome, recursive: true)
    let oldHome = getVariable("METIS_HOME")
    setVariable("METIS_HOME", testHome)
    CliConfig.invalidatePathCache()
    try {
        return block()
    } finally {
        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        CliConfig.invalidatePathCache()
    }
}

private func factorySnapshotAccounts(snapshot: JsonObject, channelId: String): JsonArray {
    let channelAccounts = (snapshot.get("channelAccounts") ?? JsonObject()).asObject()
    (channelAccounts.get(channelId) ?? JsonArray([])).asArray()
}

private func factorySnapshotHasAccount(snapshot: JsonObject, channelId: String, accountId: String): Bool {
    let accounts = factorySnapshotAccounts(snapshot, channelId)
    for (i in 0..accounts.size()) {
        let row = try { accounts[i].asObject() } catch (_: Exception) { JsonObject() }
        let id = try { (row.get("accountId") ?? JsonString("")).asString().getValue() } catch (_: Exception) { "" }
        if (id == accountId) {
            return true
        }
    }
    false
}

@Test
public class GatewayConfigFactoryTest {
    @TestCase
    public func buildGatewayServiceRegistersNativeTelegramAdapter(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"

        let (gateway, _feishu) = buildGatewayServiceFromUserSettings(user)
        let adapter = gateway.getAdapter("telegram")
        @Expect(adapter.isSome(), true)
        @Expect(adapter.getOrThrow() is TelegramAdapter, true)
    }

    @TestCase
    public func buildGatewayServiceRegistersConfiguredImAccountsWithPureAccountIds(): Unit {
        withGatewayConfigFactoryTestHome {
            var user = GatewayUserSettings()

            user.feishu.enabled = true
            let feishuAccounts = JsonObject()
            let feishuWriter = JsonObject()
            feishuWriter.put("appId", JsonString("feishu-writer-app"))
            feishuWriter.put("appSecret", JsonString("feishu-writer-secret"))
            feishuAccounts.put("feishu-writer", feishuWriter)
            user.feishu.accounts = Some(feishuAccounts)

            user.telegram.enabled = true
            let telegramAccounts = JsonObject()
            let tgWriter = JsonObject()
            tgWriter.put("botToken", JsonString("100001:writer"))
            telegramAccounts.put("tg-writer", tgWriter)
            user.telegram.accounts = Some(telegramAccounts)

            user.qq.enabled = true
            let qqAccounts = JsonObject()
            let qqWriter = JsonObject()
            qqWriter.put("appId", JsonString("qq-writer-app"))
            qqWriter.put("appSecret", JsonString("qq-writer-secret"))
            qqAccounts.put("qq-writer", qqWriter)
            user.qq.accounts = Some(qqAccounts)

            let (gateway, _feishu) = buildGatewayServiceFromUserSettings(user)
            let snapshot = gateway.liveChannelSnapshot()
            @Expect(factorySnapshotHasAccount(snapshot, "feishu", "feishu-writer"), true)
            @Expect(factorySnapshotHasAccount(snapshot, "telegram", "tg-writer"), true)
            @Expect(factorySnapshotHasAccount(snapshot, "qq", "qq-writer"), true)
            @Expect(factorySnapshotHasAccount(snapshot, "telegram", "telegram:tg-writer"), false)
            @Expect(factorySnapshotHasAccount(snapshot, "feishu", "default"), false)

            let feishuAdapter = gateway.getAdapter("feishu").getOrThrow()
            @Expect(feishuAdapter is FeishuAdapter, true)
            let telegramAdapter = gateway.getAdapter("telegram").getOrThrow()
            @Expect(telegramAdapter is TelegramAdapter, true)
            let qqAdapter = gateway.getAdapter("qq").getOrThrow()
            @Expect(qqAdapter is QQAdapter, true)
        }
    }

    @TestCase
    public func buildGatewayServiceSkipsDisabledOrUnconfiguredImProfilesAtAutostartRegistration(): Unit {
        withGatewayConfigFactoryTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            let telegramAccounts = JsonObject()
            let disabled = JsonObject()
            disabled.put("enabled", JsonBool(false))
            disabled.put("botToken", JsonString("100002:disabled"))
            telegramAccounts.put("tg-disabled", disabled)
            let unconfigured = JsonObject()
            telegramAccounts.put("tg-empty", unconfigured)
            user.telegram.accounts = Some(telegramAccounts)

            let (gateway, _feishu) = buildGatewayServiceFromUserSettings(user)
            let snapshot = gateway.liveChannelSnapshot()
            @Expect(factorySnapshotHasAccount(snapshot, "telegram", "tg-disabled"), false)
            @Expect(factorySnapshotHasAccount(snapshot, "telegram", "tg-empty"), false)
        }
    }
}
