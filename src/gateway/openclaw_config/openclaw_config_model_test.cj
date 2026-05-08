package metis.gateway.openclaw_config

import magic.jsonable.*
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private func str(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func boolValue(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func obj(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func arr(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func fieldByName(rendered: JsonObject, name: String): JsonObject {
    for (item in arr(rendered, "fields").getItems()) {
        let field = item.asObject()
        if (str(field, "name") == name) {
            return field
        }
    }
    JsonObject()
}

private func sampleSchema(): JsonObject {
    let root = JsonObject()
    let properties = JsonObject()
    let token = JsonObject()
    token.put("type", JsonString("string"))
    token.put("title", JsonString("Bot Token"))
    token.put("format", JsonString("password"))
    token.put("default", JsonString("must-not-leak"))
    let endpoint = JsonObject()
    endpoint.put("type", JsonString("string"))
    endpoint.put("title", JsonString("Endpoint"))
    endpoint.put("default", JsonString("https://api.example.com"))
    properties.put("botToken", token)
    properties.put("endpoint", endpoint)
    root.put("properties", properties)
    root.put("required", JsonArray([JsonString("botToken"), JsonString("endpoint")]))
    root.put("x-setup-hints", JsonArray([JsonString("Create a bot token in OpenClaw setup.")]))
    root.put("x-install-hints", JsonArray([JsonString("Restart the plugin after saving config.")]))
    return root
}

@Test
public class OpenClawConfigModelTest {
    @TestCase
    public func rendererMarksSecretFieldsAndOmitsSecretDefaults(): Unit {
        let rendered = openClawRenderConfigSchema("telegram-openclaw", sampleSchema())
        @Expect(str(rendered, "schema"), "metis.openclaw.config.v1")
        @Expect(str(rendered, "pluginId"), "telegram-openclaw")
        @Expect(arr(rendered, "fields").size(), 2)

        let tokenField = fieldByName(rendered, "botToken")
        let endpointField = fieldByName(rendered, "endpoint")
        @Expect(str(tokenField, "name"), "botToken")
        @Expect(boolValue(tokenField, "secret"), true)
        @Expect(str(tokenField, "storage"), "metis-secret")
        @Expect(tokenField.get("default").isNone(), true)
        @Expect(str(endpointField, "default"), "https://api.example.com")
    }

    @TestCase
    public func secretValuesPersistToFakeStoreAndPublicConfigUsesSecretRefs(): Unit {
        let store = OpenClawFakeSecretStore()
        let values = JsonObject()
        values.put("botToken", JsonString("123456789:AASecret"))
        values.put("endpoint", JsonString("https://api.example.com"))

        let saved = openClawPersistPluginConfig("telegram-openclaw", openClawRenderConfigSchema("telegram-openclaw", sampleSchema()), values, store)
        @Expect(str(saved, "schema"), "metis.openclaw.config.values.v1")
        @Expect(str(obj(saved, "values"), "endpoint"), "https://api.example.com")
        @Expect(obj(saved, "values").get("botToken").isNone(), true)
        @Expect(str(obj(saved, "secretRefs"), "botToken"), "openclaw/telegram-openclaw/botToken")
        @Expect(store.contains("openclaw/telegram-openclaw/botToken"), true)
        @Expect(store.get("openclaw/telegram-openclaw/botToken").getOrThrow(), "123456789:AASecret")
    }

    @TestCase
    public func savedConfigReadbackShowsPublicValuesAndSecretConfiguredState(): Unit {
        let store = OpenClawFakeSecretStore()
        let rendered = openClawRenderConfigSchema("telegram-openclaw", sampleSchema())
        let values = JsonObject()
        values.put("botToken", JsonString("123456789:AASecret"))
        values.put("endpoint", JsonString("https://api.example.com"))
        let saved = openClawPersistPluginConfig("telegram-openclaw", rendered, values, store)

        let readback = openClawReadPluginConfig("telegram-openclaw", rendered, saved, store)
        @Expect(str(readback, "schema"), "metis.openclaw.config.read.v1")
        @Expect(str(obj(readback, "values"), "endpoint"), "https://api.example.com")
        @Expect(obj(readback, "values").get("botToken").isNone(), true)
        @Expect(boolValue(obj(readback, "secretConfigured"), "botToken"), true)
        @Expect(readback.toString().contains("123456789:AASecret"), false)
    }

    @TestCase
    public func doctorRedactsDiagnosticsAndReportsMissingSetup(): Unit {
        let store = OpenClawFakeSecretStore()
        let values = JsonObject()
        values.put("endpoint", JsonString(""))
        let diagnostics = JsonObject()
        diagnostics.put("authorization", JsonString("Bearer secret-token"))
        diagnostics.put("plain", JsonString("network unreachable"))
        diagnostics.put("events", JsonArray([JsonString("password=top-secret-password")]))

        let doctor = openClawPluginSetupDoctor("telegram-openclaw", openClawRenderConfigSchema("telegram-openclaw", sampleSchema()), values, store, JsonArray([]), "healthy", diagnostics)
        @Expect(str(doctor, "status"), "setup-required")
        @Expect(arr(doctor, "missingFields").size(), 2)
        @Expect(arr(doctor, "setupHints").size(), 1)
        @Expect(arr(doctor, "installHints").size(), 1)
        @Expect(str(obj(doctor, "diagnostics"), "authorization"), "[REDACTED]")
        @Expect(doctor.toString().contains("top-secret-password"), false)
        @Expect(str(obj(doctor, "diagnostics"), "plain"), "network unreachable")
    }

    @TestCase
    public func controlModelCanSaveAndReadPluginHealthDiagnosticsAndCapabilities(): Unit {
        let repo = OpenClawPluginConfigRepository()
        let capabilities = JsonArray([JsonString("tool.fetch"), JsonString("channel.telegram")])
        let diagnostics = JsonObject()
        diagnostics.put("password", JsonString("do-not-log"))
        let config = JsonObject()
        config.put("enabled", true.toJsonValue())

        repo.save(openClawPluginControlModel("plugin-a", "healthy", capabilities, diagnostics, config))
        let loaded = repo.read("plugin-a").getOrThrow()

        @Expect(str(loaded, "pluginId"), "plugin-a")
        @Expect(str(loaded, "health"), "healthy")
        @Expect(arr(loaded, "capabilities").size(), 2)
        @Expect(str(obj(loaded, "diagnostics"), "password"), "[REDACTED]")
        @Expect(boolValue(obj(loaded, "config"), "enabled"), true)
    }
}
