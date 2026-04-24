package metis.core.config

import magic.dsl.jsonable
import magic.jsonable.*

import stdx.encoding.json.*
import std.collection.{ArrayList,HashMap}

/**
 * 兼容 AgentSkills 风格的技能配置（保存在 `~/.metis/metis.json` 的 legacy settings 区域）。
 *
 * - `loadExtraDirs`：额外技能根目录（每个目录下为若干子目录，内含 `SKILL.md`）。
 * - `entries`：按技能名覆盖，例如 `{ "my-skill": { "enabled": false } }`。
 *   键名须与 SKILL.md frontmatter 的 `name` 一致（不含 `\r`；见 `skillEntryEnabled`）。
 */
@jsonable
public struct SkillsUserSettings {
    public var enabled: Bool = true
    public var loadExtraDirs: Array<String> = []
    public var entries: Option<JsonObject> = None
}

public struct ResolvedSkillEntryConfig {
    ResolvedSkillEntryConfig(
        public let key: String,
        public let value: JsonObject
    ) {}
}

private func jsonValueToOptionalBool(ev: JsonValue): Option<Bool> {
    try {
        return Some(Bool.fromJsonValue(ev))
    } catch (_: JsonableException) {
        return None
    }
}

/**
 * `entries` 中未出现该技能名，或 `enabled` 缺省/非布尔 → 视为启用；
 * 仅当 `entries.<name>.enabled === false` 时为关闭。
 * CLI / 网关天气工具与 SKILL 扫描共用此逻辑。
 */
public func resolveSkillEntryConfig(
    st: SkillsUserSettings,
    skillName: String,
    skillKey!: String = ""
): Option<ResolvedSkillEntryConfig> {
    if (let Some(root) <- st.entries) {
        let candidates = ArrayList<String>()
        let normalizedKey = skillKey.trimAscii()
        let normalizedName = skillName.trimAscii()
        if (!normalizedKey.isEmpty()) {
            candidates.add(normalizedKey)
        }
        if (!normalizedName.isEmpty() && !candidates.contains(normalizedName)) {
            candidates.add(normalizedName)
        }
        for (candidate in candidates) {
            if (let Some(v) <- root.get(candidate)) {
                try {
                    return Some(ResolvedSkillEntryConfig(candidate, v.asObject()))
                } catch (_: Exception) {
                    return None
                }
            }
        }
    }
    None
}

public func skillEntryEnabled(st: SkillsUserSettings, skillName: String, skillKey!: String = ""): Bool {
    match (resolveSkillEntryConfig(st, skillName, skillKey: skillKey)) {
        case Some(entry) =>
            match (entry.value.get("enabled")) {
                case Some(ev) =>
                    match (jsonValueToOptionalBool(ev)) {
                        case Some(en) => en
                        case None => true
                    }
                case None => true
            }
        case None => true
    }
}

public func skillEntryApiKey(st: SkillsUserSettings, skillName: String, skillKey!: String = ""): String {
    match (resolveSkillEntryConfig(st, skillName, skillKey: skillKey)) {
        case Some(entry) =>
            match (entry.value.get("apiKey")) {
                case Some(value) =>
                    try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
                case None => ""
            }
        case None => ""
    }
}

public func skillEntryEnvValue(
    st: SkillsUserSettings,
    skillName: String,
    envKey: String,
    skillKey!: String = ""
): String {
    let normalizedEnv = envKey.trimAscii()
    if (normalizedEnv.isEmpty()) {
        return ""
    }
    match (resolveSkillEntryConfig(st, skillName, skillKey: skillKey)) {
        case Some(entry) =>
            match (entry.value.get("env")) {
                case Some(value) =>
                    try {
                        let envObj = value.asObject()
                        match (envObj.get(normalizedEnv)) {
                            case Some(v) =>
                                try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
                            case None => ""
                        }
                    } catch (_: Exception) {
                        ""
                    }
                case None => ""
            }
        case None => ""
    }
}

public func skillEntryConfigBag(
    st: SkillsUserSettings,
    skillName: String,
    skillKey!: String = ""
): Option<JsonObject> {
    match (resolveSkillEntryConfig(st, skillName, skillKey: skillKey)) {
        case Some(entry) =>
            match (entry.value.get("config")) {
                case Some(value) =>
                    try { Some(value.asObject()) } catch (_: Exception) { None }
                case None => None
            }
        case None => None
    }
}
