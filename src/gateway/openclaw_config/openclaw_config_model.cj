package metis.gateway.openclaw_config

import magic.jsonable.*
import std.collection.{ArrayList, HashMap}
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

public class OpenClawFakeSecretStore {
    private let values = HashMap<String, String>()

    public init() {}

    public func put(key: String, value: String): Unit {
        this.values[key] = value
    }

    public func get(key: String): Option<String> {
        this.values.get(key)
    }

    public func contains(key: String): Bool {
        this.values.contains(key)
    }
}

public class OpenClawPluginConfigRepository {
    private let records = HashMap<String, JsonObject>()

    public init() {}

    public func save(record: JsonObject): Unit {
        this.records[openClawJsonString(record, "pluginId")] = record
    }

    public func read(pluginId: String): Option<JsonObject> {
        this.records.get(pluginId)
    }
}

public func openClawRenderConfigSchema(pluginId: String, schema: JsonObject): JsonObject {
    let out = JsonObject()
    out.put("schema", JsonString("metis.openclaw.config.v1"))
    out.put("pluginId", JsonString(pluginId.trimAscii()))
    let fields = JsonArray([])
    let required = openClawRequiredNames(schema)
    let properties = openClawJsonObject(schema, "properties")
    for ((name, rawField) in properties.getFields()) {
        let field = try { rawField.asObject() } catch (_e: Exception) { JsonObject() }
        let rendered = JsonObject()
        rendered.put("name", JsonString(name))
        rendered.put("type", JsonString(openClawJsonString(field, "type", fallback: "string")))
        rendered.put("label", JsonString(openClawJsonString(field, "title", fallback: name)))
        let secret = openClawIsSecretField(name, field)
        rendered.put("secret", secret.toJsonValue())
        rendered.put("required", required.contains(name).toJsonValue())
        if (secret) {
            rendered.put("storage", JsonString("metis-secret"))
        } else {
            match (field.get("default")) {
                case Some(v) => rendered.put("default", v)
                case None => ()
            }
        }
        fields.add(rendered)
    }
    out.put("fields", fields)
    return out
}

public func openClawPersistPluginConfig(
    pluginId: String,
    renderedSchema: JsonObject,
    rawValues: JsonObject,
    store: OpenClawFakeSecretStore
): JsonObject {
    let out = JsonObject()
    let publicValues = JsonObject()
    let secretRefs = JsonObject()
    out.put("schema", JsonString("metis.openclaw.config.values.v1"))
    out.put("pluginId", JsonString(pluginId.trimAscii()))
    for (item in openClawJsonArray(renderedSchema, "fields").getItems()) {
        let field = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        let name = openClawJsonString(field, "name")
        if (name.isEmpty()) {
            continue
        }
        match (rawValues.get(name)) {
            case Some(value) =>
                if (openClawJsonBool(field, "secret")) {
                    let secretRef = openClawSecretRef(pluginId, name)
                    store.put(secretRef, openClawJsonValueString(value))
                    secretRefs.put(name, JsonString(secretRef))
                } else {
                    publicValues.put(name, value)
                }
            case None => ()
        }
    }
    out.put("values", publicValues)
    out.put("secretRefs", secretRefs)
    return out
}

public func openClawPluginSetupDoctor(
    pluginId: String,
    renderedSchema: JsonObject,
    rawValues: JsonObject,
    store: OpenClawFakeSecretStore,
    capabilities: JsonArray,
    health: String,
    diagnostics: JsonObject
): JsonObject {
    let missing = JsonArray([])
    for (item in openClawJsonArray(renderedSchema, "fields").getItems()) {
        let field = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        if (!openClawJsonBool(field, "required")) {
            continue
        }
        let name = openClawJsonString(field, "name")
        if (openClawJsonBool(field, "secret")) {
            if (!store.contains(openClawSecretRef(pluginId, name))) {
                missing.add(JsonString(name))
            }
        } else if (openClawJsonString(rawValues, name).trimAscii().isEmpty()) {
            missing.add(JsonString(name))
        }
    }
    let out = JsonObject()
    out.put("schema", JsonString("metis.openclaw.setup.doctor.v1"))
    out.put("pluginId", JsonString(pluginId.trimAscii()))
    out.put("status", JsonString(if (missing.size() == 0 && health.trimAscii() == "healthy") { "ready" } else { "setup-required" }))
    out.put("missingFields", missing)
    out.put("capabilities", capabilities)
    out.put("health", JsonString(health.trimAscii()))
    out.put("diagnostics", openClawRedactJsonObject(diagnostics))
    return out
}

public func openClawPluginControlModel(
    pluginId: String,
    health: String,
    capabilities: JsonArray,
    diagnostics: JsonObject,
    config: JsonObject
): JsonObject {
    let out = JsonObject()
    out.put("schema", JsonString("metis.openclaw.control.model.v1"))
    out.put("pluginId", JsonString(pluginId.trimAscii()))
    out.put("health", JsonString(health.trimAscii()))
    out.put("capabilities", capabilities)
    out.put("diagnostics", openClawRedactJsonObject(diagnostics))
    out.put("config", config)
    return out
}

private func openClawSecretRef(pluginId: String, name: String): String {
    "openclaw/${pluginId.trimAscii()}/${name.trimAscii()}"
}

private func openClawRequiredNames(schema: JsonObject): ArrayList<String> {
    let out = ArrayList<String>()
    for (item in openClawJsonArray(schema, "required").getItems()) {
        let name = try { item.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        if (!name.isEmpty() && !out.contains(name)) {
            out.add(name)
        }
    }
    return out
}

private func openClawIsSecretField(name: String, field: JsonObject): Bool {
    let lower = name.toAsciiLower()
    lower.contains("token") || lower.contains("secret") || lower.contains("password") ||
        lower.contains("authorization") || lower.contains("api_key") ||
        openClawJsonString(field, "format").toAsciiLower() == "password" ||
        openClawJsonBool(field, "secret") || openClawJsonBool(field, "x-secret")
}

private func openClawRedactJsonObject(input: JsonObject): JsonObject {
    let out = JsonObject()
    for ((key, value) in input.getFields()) {
        if (openClawIsSensitiveKey(key)) {
            out.put(key, JsonString("[REDACTED]"))
        } else {
            match (value) {
                case s: JsonString => out.put(key, JsonString(openClawRedactString(s.getValue())))
                case obj: JsonObject => out.put(key, openClawRedactJsonObject(obj))
                case _ => out.put(key, value)
            }
        }
    }
    return out
}

private func openClawRedactString(raw: String): String {
    let lower = raw.toAsciiLower()
    if (lower.contains("bearer ") || lower.contains("password=") || lower.contains("token=") || lower.contains("secret=")) {
        return "[REDACTED]"
    }
    raw
}

private func openClawIsSensitiveKey(key: String): Bool {
    let lower = key.toAsciiLower()
    lower.contains("token") || lower.contains("secret") || lower.contains("password") ||
        lower.contains("authorization") || lower.contains("credential") || lower.contains("api_key")
}

private func openClawJsonObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func openClawJsonArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func openClawJsonString(obj: JsonObject, key: String, fallback!: String = ""): String {
    match (obj.get(key)) {
        case Some(v) => openClawJsonValueString(v)
        case None => fallback
    }
}

private func openClawJsonValueString(value: JsonValue): String {
    match (value) {
        case s: JsonString => s.getValue()
        case b: JsonBool => if (b.getValue()) { "true" } else { "false" }
        case _ => value.toString()
    }
}

private func openClawJsonBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}
