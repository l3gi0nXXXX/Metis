package metis.gateway.config

import magic.jsonable.*

import std.collection.HashMap
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func bindingRegistryBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func bindingRegistryString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayBindingRegistryProfilesTest {
    @TestCase
    public func rowJsonMergesConfiguredAndRuntimeState(): Unit {
        let configured = JsonObject(HashMap<String, JsonValue>())
        configured.put("configured", true.toJsonValue())
        configured.put("autoEnabled", true.toJsonValue())
        configured.put("accountId", JsonString("qq:default"))
        let runtime = JsonObject(HashMap<String, JsonValue>())
        runtime.put("primed", true.toJsonValue())
        runtime.put("primedAtMs", 123.toJsonValue())
        let runtimeAccounts = JsonArray([])
        runtimeAccounts.add(runtime)

        let row = gatewayBindingRegistryRowJson("channelId", "QQ", configured, runtimeAccounts)
        @Expect(bindingRegistryString(row, "channelId"), "qq")
        @Expect(bindingRegistryBool(row, "configuredBinding"), true)
        @Expect(bindingRegistryBool(row, "primed"), true)
        @Expect(bindingRegistryString(row, "bindingState"), "primed")
        @Expect(bindingRegistryString(row, "defaultAccountId"), "qq:default")
    }

    @TestCase
    public func bindingStateHelpersMatchCurrentGatewaySemantics(): Unit {
        @Expect(gatewayChannelBindingState(true, true, true), "bound")
        @Expect(gatewayChannelBindingState(true, false, false), "pending-config")
        @Expect(gatewayPluginBindingState(true, true, true, true, false), "configured")
        @Expect(gatewayPluginBindingState(false, false, false, false, false), "missing")
        @Expect(gatewayBindingActionsNeeded(true), false)
        @Expect(gatewayBindingActionsNeeded(false), true)
    }
}
