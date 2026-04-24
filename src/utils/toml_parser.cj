package metis.utils

import magic.config.Config
import magic.utils.readFile
import magic.jsonable.FromJsonValue

import std.fs.*
import std.io.*
import std.collection.*
import std.convert.*
import std.regex.*
import stdx.encoding.json.*

protected class TomlInvalidKeyPathException <: Exception {
    public init(keyPath: String) {
        super("Invalid TOML key path: ${keyPath}")
    }
}

protected class Toml {
    private let jsonObject: JsonObject

    protected init(path: String) {
        this.jsonObject = parseToml(path)
    }

    protected init(path: Path) {
        this.jsonObject = parseToml(path.toString())
    }

    /**
     * Get value by key path, e.g. "a.b.c"
     */
    protected func getValue(keyPath: String): Option<JsonValue> {
        let pathParts = keyPath.split(".")
        var current = this.jsonObject

        for (i in 0..pathParts.size-1) {
            let part = pathParts[i].trimAscii()
            if (let Some(jv) <- current.get(part)) {
                current = jv.asObject()
            } else {
                return None
            }
        }
        return current.get(pathParts[pathParts.size-1].trimAscii())
    }

    protected func get<T>(keyPath: String): T where T <: FromJsonValue<T> {
        if (let Some(jv) <- this.getValue(keyPath)) {
            return T.fromJsonValue(jv)
        } else {
            throw TomlInvalidKeyPathException(keyPath)
        }
    }
}

/**
 * Parse TOML file with support for nested sections like [a.b.c] and arrays
 * Returns JsonObject where sections create nested object structures
 * Supports environment variable substitution in string values like ${VAR_NAME}
 */
protected func parseToml(path: String): JsonObject {
    let content = readFile(Path(path))
    let lines = content.split("\n")
    let root = JsonObject()
    var currentSection = root

    for (line in lines) {
        let trimed = line.trimAscii()
        if (trimed.isEmpty() || trimed.startsWith("#")) {
            continue
        }

        // Handle section headers like [section] or [a.b.c]
        if (trimed.startsWith("[") && trimed.endsWith("]")) {
            let sectionPath = trimed[1..trimed.size - 1].trimAscii()
            currentSection = getOrCreateNestedSection(root, sectionPath)
            continue
        }

        // Handle key = value pairs
        let parts = trimed.split("=", 2)
        if (parts.size != 2) {
            continue
        }
        let key = parts[0].trimAscii()
        let valueStr = parts[1].trimAscii()
        let jsonValue = parseTomlValue(valueStr)
        currentSection.put(key, jsonValue)
    }
    return root
}

/**
 * Create or retrieve nested JsonObject for section path like "a.b.c"
 */
private func getOrCreateNestedSection(root: JsonObject, sectionPath: String): JsonObject {
    let pathParts = sectionPath.split(".")
    var current = root

    for (i in 0..pathParts.size) {
        let part = pathParts[i].trimAscii()

        // Check if this part already exists and is an object
        if (let Some(jv) <- current.get(part)) {
            current = jv.asObject()
        } else {
            // Create new nested object
            let newSection = JsonObject()
            current.put(part, newSection)
            current = newSection
        }
    }

    return current
}

/**
 * Parse TOML value string and convert to JsonValue
 * Supports arrays like [1, 2, 3] or ["a", "b", "c"]
 */
private func parseTomlValue(valueStr: String): JsonValue {
    // Handle arrays like [1, 2, 3] or ["a", "b", "c"]
    if (valueStr.startsWith("[") && valueStr.endsWith("]")) {
        let arrayContent = valueStr[1..valueStr.size - 1].trimAscii()
        if (arrayContent.isEmpty()) {
            return JsonArray(ArrayList<JsonValue>())
        }

        let elements = arrayContent.split(",")
        let jsonArray = ArrayList<JsonValue>()

        for (element in elements) {
            let trimmedElement = element.trimAscii()
            jsonArray.add(parseSingleTomlValue(trimmedElement))
        }

        return JsonArray(jsonArray)
    }

    return parseSingleTomlValue(valueStr)
}

/**
 * Parse single TOML value (non-array) and convert to JsonValue
 */
private func parseSingleTomlValue(valueStr: String): JsonValue {
    // Handle quoted strings with environment variable substitution
    if (valueStr.startsWith("\"") && valueStr.endsWith("\"")) {
        let content = valueStr[1..valueStr.size - 1]
        let expandedContent = expandEnvironmentVariables(content)
        return JsonString(expandedContent)
    }

    if (valueStr.startsWith("'") && valueStr.endsWith("'")) {
        let content = valueStr[1..valueStr.size - 1]
        // Single quoted strings don't support environment variable expansion
        return JsonString(content)
    }

    // Boolean values
    if (valueStr == "true") {
        return JsonBool(true)
    }
    if (valueStr == "false") {
        return JsonBool(false)
    }

    // Try parsing as integer
    if (Regex(#"^-?\d+$"#).matches(valueStr)) {
        try {
            let intVal = Int64.parse(valueStr)
            return JsonInt(intVal)
        } catch (_: IllegalArgumentException) {
            return JsonString(valueStr)
        }
    }

    // Try parsing as float
    if (Regex(#"^-?\d*\.\d+$"#).matches(valueStr)) {
        try {
            let floatVal = Float64.parse(valueStr)
            return JsonFloat(floatVal)
        } catch (_: IllegalArgumentException) {
            return JsonString(valueStr)
        }
    }

    // Default to string with environment variable expansion
    let expandedContent = expandEnvironmentVariables(valueStr)
    return JsonString(expandedContent)
}

/**
 * Expand environment variables in string like ${VAR_NAME}
 */
private func expandEnvironmentVariables(input: String): String {
    return RegexUtils.replaceAll(input, #"\${([^}]+)}"#, { m =>
        let varName = m.matchString(1).trimAscii()
        return Config.env[varName] ?? ""
    })
}
