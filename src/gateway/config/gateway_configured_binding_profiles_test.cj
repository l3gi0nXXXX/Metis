package metis.gateway.config

import metis.core.config.GatewayUserSettings

import magic.jsonable.*
import std.collection.HashMap
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func bindingProfileBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func bindingProfileString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayConfiguredBindingProfilesTest {
    @TestCase
    public func builtinBindingRowsAndPrimeEntriesShareConfigSemantics(): Unit {
        var user = GatewayUserSettings()
        user.feishu.enabled = true
        user.feishu.appId = "feishu-app"
        let root = JsonObject(HashMap<String, JsonValue>())
        let slack = JsonObject()
        slack.put("enabled", true.toJsonValue())
        slack.put("webhookUrl", JsonString("https://hooks.slack.test/demo"))
        root.put("slack", slack)
        user.channelsExtra = Some(root)

        let rows = gatewayConfiguredBuiltinBindingRows(user)
        @Expect(rows.size(), 5)

        let primeEntries = gatewayConfiguredBuiltinPrimeEntries(user)
        @Expect(primeEntries.size(), 2)

        let first = primeEntries[0].asObject()
        @Expect(bindingProfileBool(first, "configuredBinding"), true)
    }

    @TestCase
    public func pluginDefaultBindingRowAndPrimeEntryReuseSameConfigShape(): Unit {
        let row = gatewayConfiguredPluginDefaultBindingRow("DemoPlugin", true, true)
        @Expect(bindingProfileString(row, "channelId"), "demoplugin")
        @Expect(bindingProfileBool(row, "configured"), true)
        let primed = gatewayConfiguredPrimeEntryFromBindingRow(row)
        @Expect(bindingProfileBool(primed, "configuredBinding"), true)
        @Expect(bindingProfileBool(primed, "autoEnabled"), true)
    }

    @TestCase
    public func bindingRowLookupByFieldUsesNormalizedStrings(): Unit {
        let rows = JsonArray([])
        rows.add(gatewayConfiguredBindingRowJson("QQ", "qq", "qq:default", true, true, true))
        rows.add(gatewayConfiguredPluginDefaultBindingRow("DemoPlugin", true, true))
        @Expect(bindingProfileString(gatewayConfiguredBindingRowByField(rows, "channelId", "qq"), "pluginId"), "qq")
        @Expect(bindingProfileString(gatewayConfiguredBindingRowByField(rows, "pluginId", "DEMOPLUGIN"), "channelId"), "demoplugin")
    }

    @TestCase
    public func primedBindingsReuseConfiguredRows(): Unit {
        let rows = JsonArray([])
        rows.add(gatewayConfiguredBindingRowJson("qq", "qq", "qq:default", true, true, true))
        rows.add(gatewayConfiguredPluginDefaultBindingRow("demo", true, false))
        let primed = gatewayConfiguredPrimedBindings(rows)
        @Expect(primed.size(), 1)
        let first = primed[0].asObject()
        @Expect(bindingProfileBool(first, "configuredBinding"), true)
        @Expect(bindingProfileString(first, "bindingKind"), "configured")
    }
}
