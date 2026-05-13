package metis.core.skills

import magic.log.LogUtils
import magic.jsonable.*

import metis.core.config.{MetisPaths, CliConfig, CliSettingManager, MetisConfigManager, SkillsUserSettings, skillEntryEnabled, skillEntryApiKey, skillEntryConfigBag, skillEntryEnvValue, resolveSkillEntryConfig}
import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, FileInfo, OpenMode, Path, exists}
import std.io.readToEnd
import std.time.DateTime
import stdx.encoding.json.{JsonObject, JsonValue}

private const SKILL_FILE = "SKILL.md"
private const MAX_BODY_PER_SKILL: Int64 = 6000
private const MAX_TOTAL_PROMPT: Int64 = 28000

public struct SkillMatchState {
    SkillMatchState(
        public let skillName: String,
        public let enabled: Bool
    ) {}
}

public struct SkillDescriptor {
    SkillDescriptor(
        public let name: String,
        public let description: String,
        public let location: String,
        public let source: String,
        public let enabled: Bool,
        public let skillKey: String,
        public let primaryEnv: String,
        public let homepage: String,
        public let always: Bool,
        public let requiredOs: Array<String>,
        public let userInvocable: Bool,
        public let disableModelInvocation: Bool,
        public let requiredEnv: Array<String>,
        public let requiredBins: Array<String>,
        public let requiredAnyBins: Array<String>,
        public let requiredConfig: Array<String>,
        public let installSpecs: Array<JsonObject>,
        public let configuredApiKey: String,
        public let configuredEnv: Option<JsonObject>,
        public let configuredConfig: Option<JsonObject>
    ) {}
}

public struct SkillLegacyMetadata {
    SkillLegacyMetadata(
        public let skillKey: String,
        public let primaryEnv: String,
        public let homepage: String,
        public let always: Bool,
        public let requiredOs: Array<String>,
        public let userInvocable: Bool,
        public let disableModelInvocation: Bool,
        public let requiredEnv: Array<String>,
        public let requiredBins: Array<String>,
        public let requiredAnyBins: Array<String>,
        public let requiredConfig: Array<String>,
        public let installSpecs: Array<JsonObject>
    ) {}
}

private func emptySkillLegacyMetadata(): SkillLegacyMetadata {
    SkillLegacyMetadata("", "", "", false, [], true, false, [], [], [], [], [])
}

public struct SkillSelectionDecision {
    SkillSelectionDecision(
        public let selectedSkillName: Option<String>,
        public let selectedSkillEnabled: Bool,
        public let forced: Bool,
        public let reason: String,
        public let confidence: String
    ) {}
}

public struct SkillVisibilityResolution {
    SkillVisibilityResolution(
        public let scope: String,
        public let names: Option<Array<String>>
    ) {}
}

private struct SkillEnvOverrideUpdate {
    SkillEnvOverrideUpdate(
        public let key: String,
        public let baseline: Option<String>
    ) {}
}

private struct LoadedSkill {
    LoadedSkill(
        public let name: String,
        public let description: String,
        public let body: String,
        public let sourcePath: Path,
        public let source: String,
        public let skillModel: Option<String>,
        public let apiKey: Option<String>,
        public let apiKeyEnv: Option<String>,
        public let metadata: SkillLegacyMetadata
    ) {}
}

private func configuredSkillKeyForLoadedSkill(sk: LoadedSkill): String {
    if (sk.metadata.skillKey.isEmpty()) {
        sk.name
    } else {
        sk.metadata.skillKey
    }
}

private func configuredSkillEnvForLoadedSkill(st: SkillsUserSettings, sk: LoadedSkill): Option<JsonObject> {
    match (resolveSkillEntryConfig(st, sk.name, skillKey: configuredSkillKeyForLoadedSkill(sk))) {
        case Some(entry) =>
            match (entry.value.get("env")) {
                case Some(value) =>
                    try { Some(value.asObject()) } catch (_: Exception) { None }
                case None => None
            }
        case None => None
    }
}

private func configuredSkillsLoadExtraDirs(st: SkillsUserSettings): Array<String> {
    let root = MetisConfigManager.rawConfig() ?? JsonObject()
    let skillsObj = match (root.get("skills")) {
        case Some(value) =>
            try { value.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let loadObj = match (skillsObj.get("load")) {
        case Some(value) =>
            try { value.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
    match (loadObj.get("extraDirs")) {
        case Some(value) =>
            try {
                let arr = value.asArray()
                let out = ArrayList<String>()
                for (i in 0..arr.size()) {
                    try {
                        let text = arr[i].asString().getValue().trimAscii()
                        if (!text.isEmpty()) {
                            out.add(text)
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
                out.toArray()
            } catch (_: Exception) {
                st.loadExtraDirs
            }
        case None => st.loadExtraDirs
    }
}

private func compactSkillPromptText(text: String, limit!: Int64 = 96): String {
    let trimmed = text.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    let sb = StringBuilder()
    let normalized = trimmed.replace("\r", "\n").replace("\t", " ")
    for (line in normalized.split("\n")) {
        for (word0 in line.split(" ")) {
            let word = word0.trimAscii()
            if (word.isEmpty()) {
                continue
            }
            if (sb.size > 0) {
                sb.append(" ")
            }
            sb.append(word)
            if (Int64(sb.size) >= limit) {
                let compacted = sb.toString().trimAscii()
                return if (compacted.size < trimmed.size) { compacted + "..." } else { compacted }
            }
        }
    }
    let compacted = sb.toString().trimAscii()
    if (compacted.size < trimmed.size) {
        return compacted + "..."
    }
    compacted
}

/**
 * 扫描并格式化注入到系统提示中的 Skills 文本；CLI 与 Gateway 共用。
 *
 * 扫描顺序（同名后者覆盖前者）：
 * `loadExtraDirs` → bundled skills → `~/.metis/skills` → `~/.agents/skills` →
 * `<workspace>/.agents/skills` → `<workspace>/skills`。
 */
public class SkillsPrompt {
    private static var memo: Option<String> = None
    private static var memoSkills: Option<ArrayList<LoadedSkill>> = None
    private static var memoSkillsAll: Option<ArrayList<LoadedSkill>> = None
    private static var memoSettingsSignature: String = ""
    private static var memoFilesystemSignature: String = ""
    private static var memoWatchCheckedAtMs: Int64 = 0

    /**
     * 在加载 settings 或切换工作目录后调用。
     * 会立即重新扫描磁盘并填充缓存（与仅「清缓存」不同），以便启动时就能在日志里看到完整 discover 链路；
     * 否则 `@prompt` 若延后求值，可能直到首次对话才访问 `appendix`，容易误以为没有 Skills 日志。
     */
    public static func invalidate(): Unit {
        memo = None
        memoSkills = None
        memoSkillsAll = None
        memoSettingsSignature = ""
        memoFilesystemSignature = ""
        memoWatchCheckedAtMs = 0
        LogUtils.info("Skills: reload — clearing prompt cache and scanning SKILL.md roots now")
        let s = buildAppendix()
        memo = Some(s)
    }

    private static func clearMemoizedCache(reason: String): Unit {
        memo = None
        memoSkills = None
        memoSkillsAll = None
        LogUtils.info("Skills: snapshot refresh — ${reason}")
    }

    private static func currentSettingsSignature(st: SkillsUserSettings): String {
        let entriesText = match (st.entries) {
            case Some(entries) => entries.toJsonString()
            case None => ""
        }
        let dirs = String.join(configuredSkillsLoadExtraDirs(st), delimiter: "|")
        "${if (st.enabled) { "1" } else { "0" }}|${dirs}|${entriesText}"
    }

    private static func watchSettings(): (Bool, Int64) {
        let root = MetisConfigManager.rawConfig() ?? JsonObject()
        let skillsObj = match (root.get("skills")) {
            case Some(value) =>
                try { value.asObject() } catch (_: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let loadObj = match (skillsObj.get("load")) {
            case Some(value) =>
                try { value.asObject() } catch (_: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let watch = match (loadObj.get("watch")) {
            case Some(value) =>
                try { value.asBool().getValue() } catch (_: Exception) { true }
            case None => true
        }
        let debounceMs = match (loadObj.get("watchDebounceMs")) {
            case Some(value) =>
                try { value.asInt().getValue() } catch (_: Exception) {
                    try { Int64.parse(value.asString().getValue().trimAscii()) } catch (_: Exception) { 500 }
                }
            case None => 500
        }
        (watch, if (debounceMs > 0) { debounceMs } else { 500 })
    }

    private static func filesystemSignature(st: SkillsUserSettings): String {
        let roots = skillsResolvedRoots(st)
        let lines = ArrayList<String>()
        for (rootEntry in roots) {
            let label = rootEntry[0]
            let root = rootEntry[1]
            if (!exists(root)) {
                lines.add("${label}|missing|${root}")
                continue
            }
            lines.add("${label}|root|${root}")
            try {
                for (info in Directory.readFrom(root)) {
                    if (!info.isDirectory()) {
                        continue
                    }
                    let skillMd = info.path.join(SKILL_FILE)
                    if (!exists(skillMd)) {
                        continue
                    }
                    let mtimeMs = try {
                        FileInfo(skillMd).lastModificationTime.toUnixTimeStamp().toMilliseconds()
                    } catch (_: Exception) {
                        -1
                    }
                    lines.add("${label}|skill|${info.name}|${skillMd}|${mtimeMs}")
                }
            } catch (_: Exception) {
                lines.add("${label}|error|${root}")
            }
        }
        String.join(lines.toArray(), delimiter: "\n")
    }

    private static func maybeRefreshMemoizedSkills(): Unit {
        let st = CliSettingManager.setting.skills
        let currentSettings = currentSettingsSignature(st)
        if (!memoSettingsSignature.isEmpty() && currentSettings != memoSettingsSignature) {
            clearMemoizedCache("settings signature changed")
        }
        memoSettingsSignature = currentSettings

        let (watchEnabled, watchDebounceMs) = watchSettings()
        if (!watchEnabled) {
            return
        }
        let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        if (memoWatchCheckedAtMs > 0 && (nowMs - memoWatchCheckedAtMs) < watchDebounceMs) {
            return
        }
        memoWatchCheckedAtMs = nowMs
        let currentFilesystem = filesystemSignature(st)
        if (!memoFilesystemSignature.isEmpty() && currentFilesystem != memoFilesystemSignature) {
            clearMemoizedCache("SKILL.md roots changed")
        }
        memoFilesystemSignature = currentFilesystem
    }

    /** 供 `@prompt` 字符串插值使用（与 `CliConfig.userRules` 类似）。 */
    public static prop appendix: String {
        get() {
            maybeRefreshMemoizedSkills()
            if (let Some(s) <- memo) {
                LogUtils.debug("Skills: appendix cache hit (${s.size} chars)")
                return s
            }
            LogUtils.info("Skills: appendix cache miss, building from disk…")
            let s = buildAppendix()
            memo = Some(s)
            return s
        }
    }

    /**
     * Check whether a skill exists by exact name (case-insensitive).
     * Used by slash-style command routing, e.g. `/weather Shanghai`.
     */
    public static func hasSkillName(skillName: String, agentId!: String = "", runtimeSkillNames!: Array<String> = []): Bool {
        let name = skillName.trimAscii().toAsciiLower()
        if (name.isEmpty()) {
            return false
        }
        let skills = userInvocableSkillsForAgent(ensureSkillsAll(), agentId, runtimeSkillNames: runtimeSkillNames)
        for (sk in skills) {
            if (sk.name.toAsciiLower() == name) {
                return true
            }
        }
        false
    }

    /**
     * Return all discovered skills with enabled status, for `/skills` command.
     * Item format: "<name>\tenabled=<true|false>".
     */
    public static func listSkillStatusLines(): Array<String> {
        let out = ArrayList<String>()
        let skills = ensureSkillsAll()
        for (sk in skills) {
            let enabled = skillEntryEnabled(
                CliSettingManager.setting.skills,
                sk.name,
                skillKey: configuredSkillKeyForLoadedSkill(sk)
            )
            out.add("${sk.name}\tenabled=${enabled}")
        }
        out.toArray()
    }

    public static func listSkillDescriptors(agentId!: String = "", runtimeSkillNames!: Array<String> = []): Array<SkillDescriptor> {
        listSkillDescriptorsFromSkills(visibleSkillsForAgent(ensureSkillsAll(), agentId, runtimeSkillNames: runtimeSkillNames))
    }

    public static func listAllSkillDescriptors(): Array<SkillDescriptor> {
        listSkillDescriptorsFromSkills(ensureSkillsAll())
    }

    public static func isSkillEnabledByName(skillName: String): Bool {
        let normalized = skillName.trimAscii().toAsciiLower()
        if (normalized.isEmpty()) {
            return false
        }
        let st = CliSettingManager.setting.skills
        for (sk in ensureSkillsAll()) {
            if (sk.name.toAsciiLower() == normalized) {
                return skillEntryEnabled(
                    st,
                    sk.name,
                    skillKey: configuredSkillKeyForLoadedSkill(sk)
                )
            }
        }
        skillEntryEnabled(st, skillName)
    }

    public static func applyRuntimeEnvOverridesForSkill(skillName: String): () -> Unit {
        let normalized = skillName.trimAscii().toAsciiLower()
        if (normalized.isEmpty()) {
            return { => () }
        }
        let st = CliSettingManager.setting.skills
        for (sk in ensureSkillsAll()) {
            if (sk.name.toAsciiLower() != normalized) {
                continue
            }
            let single = ArrayList<LoadedSkill>()
            single.add(sk)
            let descriptor = listSkillDescriptorsFromSkills(single)[0]
            return applyRuntimeEnvOverridesForDescriptor(descriptor)
        }
        { => () }
    }

    private static func listSkillDescriptorsFromSkills(skills: ArrayList<LoadedSkill>): Array<SkillDescriptor> {
        let out = ArrayList<SkillDescriptor>()
        let st = CliSettingManager.setting.skills
        for (sk in skills) {
            let configuredKey = configuredSkillKeyForLoadedSkill(sk)
            let enabled = skillEntryEnabled(st, sk.name, skillKey: configuredKey)
            out.add(
                SkillDescriptor(
                    sk.name,
                    sk.description,
                    sk.sourcePath.toString(),
                    sk.source,
                    enabled,
                    configuredKey,
                    sk.metadata.primaryEnv,
                    sk.metadata.homepage,
                    sk.metadata.always,
                    sk.metadata.requiredOs,
                    sk.metadata.userInvocable,
                    sk.metadata.disableModelInvocation,
                    sk.metadata.requiredEnv,
                    sk.metadata.requiredBins,
                    sk.metadata.requiredAnyBins,
                    sk.metadata.requiredConfig,
                    sk.metadata.installSpecs,
                    skillEntryApiKey(st, sk.name, skillKey: configuredKey),
                    configuredSkillEnvForLoadedSkill(st, sk),
                    skillEntryConfigBag(st, sk.name, skillKey: configuredKey)
                )
            )
        }
        out.toArray()
    }

    public static func decideForInput(
        input: String,
        forcedSkillName: Option<String>,
        agentId!: String = "",
        runtimeSkillNames!: Array<String> = []
    ): SkillSelectionDecision {
        let st = CliSettingManager.setting.skills
        if (!st.enabled) {
            return SkillSelectionDecision(None, false, false, "skills_disabled", "none")
        }
        match (forcedSkillName) {
            case Some(raw) =>
                let name = raw.trimAscii()
                if (name.isEmpty()) {
                    return SkillSelectionDecision(None, false, false, "forced_empty", "none")
                }
                if (!hasSkillName(name, agentId: agentId, runtimeSkillNames: runtimeSkillNames)) {
                    return SkillSelectionDecision(None, false, true, "forced_unavailable", "none")
                }
                let enabled = isSkillEnabledByName(name)
                return SkillSelectionDecision(Some(name), enabled, true, "forced_slash", "certain")
            case None => ()
        }

        match (selectSkillNameForInput(input, agentId: agentId, runtimeSkillNames: runtimeSkillNames)) {
            case Some(name) =>
                let enabled = isSkillEnabledByName(name)
                let confidence = if (input.toAsciiLower().contains(name.toAsciiLower())) {
                    "high"
                } else {
                    "medium"
                }
                SkillSelectionDecision(Some(name), enabled, false, "selector", confidence)
            case None =>
                SkillSelectionDecision(None, false, false, "none", "none")
        }
    }

    public static func buildAvailableSkillsMetadataForPrompt(agentId!: String = "", runtimeSkillNames!: Array<String> = []): String {
        let st = CliSettingManager.setting.skills
        if (!st.enabled) {
            return ""
        }
        let skills = listSkillDescriptors(agentId: agentId, runtimeSkillNames: runtimeSkillNames)
        if (skills.isEmpty()) {
            return ""
        }
        let sb = StringBuilder()
        sb.append("<available_skills>\n")
        var injectedCount = 0
        for (d in skills) {
            if (d.disableModelInvocation) {
                continue
            }
            if (injectedCount >= 12) {
                break
            }
            let summary = compactSkillPromptText(d.description, limit: 96)
            let enabled = if (d.enabled) { "true" } else { "false" }
            sb.append("<skill name=\"${d.name}\" enabled=\"${enabled}\" location=\"${d.location}\">")
            if (!summary.isEmpty()) {
                sb.append(summary)
            }
            sb.append("</skill>\n")
            injectedCount += 1
        }
        sb.append("</available_skills>")
        sb.toString()
    }

    /**
     * Skill selection for this input:
     * - Only explicit skill-name mentions are considered a match.
     * - Generic/semantic similarity must not trigger a pre-reply LLM classification pass.
     */
    public static func selectSkillNameForInput(input: String, agentId!: String = "", runtimeSkillNames!: Array<String> = []): Option<String> {
        let st = CliSettingManager.setting.skills
        if (!st.enabled) {
            LogUtils.info("Skills.select: skills disabled -> none")
            return None
        }
        let trimmed = input.trimAscii()
        // Unknown slash command should not be semantically classified as a skill.
        // Explicit slash skill is handled by forced-skill routing before this function.
        if (trimmed.startsWith("/")) {
            LogUtils.info("Skills.select: slash-like input -> none")
            return None
        }
        let skills = modelInvocableSkillsForAgent(ensureSkillsAll(), agentId, runtimeSkillNames: runtimeSkillNames)
        if (skills.isEmpty()) {
            LogUtils.info("Skills.select: no discovered skills -> none")
            return None
        }
        let lower = input.toAsciiLower()

        // 1) explicit mention fast path (longest match)
        var best: Option<LoadedSkill> = None
        for (sk in skills) {
            if (sk.name.isEmpty()) {
                continue
            }
            let kn = sk.name.toAsciiLower()
            if (lower.contains(kn)) {
                if (let Some(b) <- best) {
                    if (kn.size > b.name.toAsciiLower().size) {
                        best = Some(sk)
                    }
                } else {
                    best = Some(sk)
                }
            }
        }
        match (best) {
            case Some(sk) =>
                LogUtils.info("Skills.select: deterministic hit -> ${sk.name}")
                Some(sk.name)
            case None =>
                LogUtils.info("Skills.select: deterministic none -> none")
                None
        }
    }

    /**
     * 只解析“当前输入最可能匹配的 skill name”（最佳努力）。
     * 根据 input 是否包含 skill 的 name（不区分大小写），选择最长匹配。
     */
    public static func resolveSkillNameForInput(input: String, agentId!: String = "", runtimeSkillNames!: Array<String> = []): Option<String> {
        let st = CliSettingManager.setting.skills
        if (!st.enabled) {
            return None
        }
        let skills = modelInvocableSkillsForAgent(ensureSkills(), agentId, runtimeSkillNames: runtimeSkillNames)
        if (skills.isEmpty()) {
            return None
        }

        let lower = input.toAsciiLower()
        var best: Option<LoadedSkill> = None
        var bestScore: Int64 = -1

        for (sk in skills) {
            if (sk.name.isEmpty()) {
                continue
            }
            let score = computeSkillMatchScore(sk.name, lower)
            if (score > 0) {
                if (let Some(b) <- best) {
                    if (score > bestScore) {
                        best = Some(sk)
                        bestScore = score
                    } else if (score == bestScore) {
                        let key = sk.name.toAsciiLower()
                        let bKey = b.name.toAsciiLower()
                        if (key.size > bKey.size) {
                            best = Some(sk)
                        }
                    }
                } else {
                    best = Some(sk)
                    bestScore = score
                }
            }
        }

        match (best) {
            case Some(sk) => Some(sk.name)
            case None => None
        }
    }

    /**
     * 返回“当前输入最佳匹配的 skill name”以及它在 metis.json 中是否 enabled。
     * 即使 `settings.skills.entries.<name>.enabled=false`，也会被视为“匹配到该 skill（但禁用）”。
     */
    public static func resolveSkillMatchStateForInput(input: String, agentId!: String = "", runtimeSkillNames!: Array<String> = []): Option<SkillMatchState> {
        let st = CliSettingManager.setting.skills
        if (!st.enabled) {
            return None
        }
        let skills = modelInvocableSkillsForAgent(ensureSkillsAll(), agentId, runtimeSkillNames: runtimeSkillNames)
        if (skills.isEmpty()) {
            return None
        }

        let lower = input.toAsciiLower()
        var best: Option<LoadedSkill> = None
        var bestScore: Int64 = -1

        for (sk in skills) {
            if (sk.name.isEmpty()) {
                continue
            }
            let score = computeSkillMatchScore(sk.name, lower)
            if (score > 0) {
                if (let Some(b) <- best) {
                    if (score > bestScore) {
                        best = Some(sk)
                        bestScore = score
                    } else if (score == bestScore) {
                        let key = sk.name.toAsciiLower()
                        let bKey = b.name.toAsciiLower()
                        if (key.size > bKey.size) {
                            best = Some(sk)
                        }
                    }
                } else {
                    best = Some(sk)
                    bestScore = score
                }
            }
        }

        match (best) {
            case Some(sk) =>
                let enabled = isSkillEnabledByName(sk.name)
                Some(SkillMatchState(sk.name, enabled))
            case None => None
        }
    }

    private static func ensureSkills(): ArrayList<LoadedSkill> {
        maybeRefreshMemoizedSkills()
        if (let Some(s) <- memoSkills) {
            return s
        }
        let st = CliSettingManager.setting.skills
        let skills = if (!st.enabled) {
            ArrayList<LoadedSkill>()
        } else {
            discoverAndLoad(st)
        }
        memoSkills = Some(skills)
        skills
    }

    private static func ensureSkillsAll(): ArrayList<LoadedSkill> {
        maybeRefreshMemoizedSkills()
        if (let Some(s) <- memoSkillsAll) {
            return s
        }
        let st = CliSettingManager.setting.skills
        // even if st.enabled=true, `entries.<name>.enabled=false` skills should still be considered for matching.
        let skills = discoverAndLoadAll(st)
        memoSkillsAll = Some(skills)
        skills
    }
}

private func applyRuntimeEnvOverridesForDescriptor(descriptor: SkillDescriptor): () -> Unit {
    let updates = ArrayList<SkillEnvOverrideUpdate>()
    match (descriptor.configuredEnv) {
        case Some(envObj) =>
            for ((key, value) in envObj.getFields()) {
                let envKey = key.trimAscii()
                if (envKey.isEmpty()) {
                    continue
                }
                if (getVariable(envKey).isSome()) {
                    continue
                }
                try {
                    let envValue = value.asString().getValue().trimAscii()
                    if (envValue.isEmpty()) {
                        continue
                    }
                    updates.add(SkillEnvOverrideUpdate(envKey, getVariable(envKey)))
                    setVariable(envKey, envValue)
                } catch (_: Exception) {
                    ()
                }
            }
        case None => ()
    }
    let primaryEnv = descriptor.primaryEnv.trimAscii()
    if (!primaryEnv.isEmpty() && !descriptor.configuredApiKey.trimAscii().isEmpty() && getVariable(primaryEnv).isNone()) {
        updates.add(SkillEnvOverrideUpdate(primaryEnv, getVariable(primaryEnv)))
        setVariable(primaryEnv, descriptor.configuredApiKey.trimAscii())
    }
    {
        =>
        for (update in updates) {
            match (update.baseline) {
                case Some(value) => setVariable(update.key, value)
                case None => setVariable(update.key, "")
            }
        }
    }
}

private func normalizeVisibleSkillName(raw: String): String {
    raw.trimAscii().toAsciiLower()
}

public func resolveAgentSkillVisibility(agentId: String): SkillVisibilityResolution {
    let normalizedAgentId = agentId.trimAscii()
    if (normalizedAgentId.isEmpty()) {
        return SkillVisibilityResolution("unrestricted", None)
    }
    let scope = MetisConfigManager.readAgentSkillsScope(normalizedAgentId)
    let names = MetisConfigManager.readAgentSkills(normalizedAgentId)
    SkillVisibilityResolution(scope, names)
}

private func runtimeSkillFilterSet(runtimeSkillNames: Array<String>): Option<HashMap<String, Bool>> {
    if (runtimeSkillNames.isEmpty()) {
        return None<HashMap<String, Bool>>
    }
    let allowed = HashMap<String, Bool>()
    for (name in runtimeSkillNames) {
        let normalized = normalizeVisibleSkillName(name)
        if (!normalized.isEmpty()) {
            allowed[normalized] = true
        }
    }
    if (allowed.size == 0) {
        return None<HashMap<String, Bool>>
    }
    Some(allowed)
}

private func visibleSkillsForAgent(skills: ArrayList<LoadedSkill>, agentId: String, runtimeSkillNames!: Array<String> = []): ArrayList<LoadedSkill> {
    let resolution = resolveAgentSkillVisibility(agentId)
    var visible = match (resolution.names) {
        case Some(names) =>
            let allowed = HashMap<String, Bool>()
            for (name in names) {
                let normalized = normalizeVisibleSkillName(name)
                if (!normalized.isEmpty()) {
                    allowed[normalized] = true
                }
            }
            let filtered = ArrayList<LoadedSkill>()
            for (sk in skills) {
                if (allowed.contains(normalizeVisibleSkillName(sk.name))) {
                    filtered.add(sk)
                }
            }
            filtered
        case None => skills
    }
    match (runtimeSkillFilterSet(runtimeSkillNames)) {
        case Some(runtimeAllowed) =>
            let filtered = ArrayList<LoadedSkill>()
            for (sk in visible) {
                if (runtimeAllowed.contains(normalizeVisibleSkillName(sk.name))) {
                    filtered.add(sk)
                }
            }
            visible = filtered
        case None => ()
    }
    visible
}

private func userInvocableSkillsForAgent(skills: ArrayList<LoadedSkill>, agentId: String, runtimeSkillNames!: Array<String> = []): ArrayList<LoadedSkill> {
    let visible = visibleSkillsForAgent(skills, agentId, runtimeSkillNames: runtimeSkillNames)
    let filtered = ArrayList<LoadedSkill>()
    for (sk in visible) {
        if (sk.metadata.userInvocable) {
            filtered.add(sk)
        }
    }
    filtered
}

private func modelInvocableSkillsForAgent(skills: ArrayList<LoadedSkill>, agentId: String, runtimeSkillNames!: Array<String> = []): ArrayList<LoadedSkill> {
    let visible = visibleSkillsForAgent(skills, agentId, runtimeSkillNames: runtimeSkillNames)
    let filtered = ArrayList<LoadedSkill>()
    for (sk in visible) {
        if (!sk.metadata.disableModelInvocation) {
            filtered.add(sk)
        }
    }
    filtered
}

/**
 * 匹配 score：
 * - 2：input 里直接包含 skill 的 `name`
 * - 1：input 命中该 skill 的“中文触发词”（当前为内置技能做兼容；自定义 skill 可逐步扩展）
 * - 0：不匹配
 */
private func computeSkillMatchScore(skillName: String, inputLower: String): Int64 {
    let key = skillName.toAsciiLower()
    if (inputLower.contains(key)) {
        return 2
    }
    0
}

private func findSkillByName(skills: ArrayList<LoadedSkill>, name: String): Option<LoadedSkill> {
    let ln = name.toAsciiLower().trimAscii()
    for (sk in skills) {
        if (sk.name.toAsciiLower() == ln) {
            return Some(sk)
        }
    }
    None
}

private func buildAppendix(): String {
    let st = CliSettingManager.setting.skills
    if (!st.enabled) {
        LogUtils.info("Skills: settings.skills.enabled=false, appendix empty")
        return ""
    }
    let skills = discoverAndLoad(st)
    if (skills.isEmpty()) {
        LogUtils.info("Skills: no skill records after scan, appendix empty (check roots and SKILL.md under subdirs)")
        return ""
    }
    let text = formatPrompt(skills)
    LogUtils.info(
        "Skills: appendix built OK — ${skills.size} skill(s), ${text.size} chars injected into prompt"
    )
    text
}

/** 同一物理路径只扫描一次（例如 projectRoot/skills 与 cwd/skills 常相同，避免重复日志与重复 override）。 */
private func tryAddSkillRoot(roots: ArrayList<(String, Path)>, seen: HashMap<String, Bool>, label: String, p: Path): Unit {
    let key = p.toString()
    if (seen.contains(key)) {
        LogUtils.info("Skills: root [${label}] duplicate path (already queued), skip: ${p}")
        return
    }
    if (!exists(p)) {
        LogUtils.info("Skills: root [${label}] missing: ${p}")
        return
    }
    seen.add(key, true)
    LogUtils.info("Skills: root [${label}] use ${p}")
    roots.add((label, p))
}

public func skillsManagedDir(): Path {
    CliConfig.dotDir.join("skills")
}

public func skillsPersonalAgentsDir(): Path {
    CliConfig.dotDir.parent.join(".agents").join("skills")
}

public func skillsProjectAgentsDir(): Path {
    CliConfig.cwd.join(".agents").join("skills")
}

public func skillsWorkspaceDir(): Path {
    CliConfig.cwd.join("skills")
}

public func skillsBundledDir(): Option<Path> {
    MetisPaths.bundledSkillsRoot()
}

public func skillsResolvedRoots(st: SkillsUserSettings): ArrayList<(String, Path)> {
    let roots = ArrayList<(String, Path)>()
    let seenPaths = HashMap<String, Bool>()
    for (d in configuredSkillsLoadExtraDirs(st)) {
        let p = resolveExtraDir(d)
        tryAddSkillRoot(roots, seenPaths, "extra:${d}", p)
    }
    match (skillsBundledDir()) {
        case Some(dir) => tryAddSkillRoot(roots, seenPaths, "bundled/skills", dir)
        case None => ()
    }
    tryAddSkillRoot(roots, seenPaths, "~/.metis/skills", skillsManagedDir())
    tryAddSkillRoot(roots, seenPaths, "~/.agents/skills", skillsPersonalAgentsDir())
    tryAddSkillRoot(roots, seenPaths, "cwd/.agents/skills", skillsProjectAgentsDir())
    tryAddSkillRoot(roots, seenPaths, "cwd/skills", skillsWorkspaceDir())
    roots
}

private func discoverAndLoad(st: SkillsUserSettings): ArrayList<LoadedSkill> {
    let bundledRootText = match (skillsBundledDir()) {
        case Some(dir) => dir.toString()
        case None => "(none)"
    }
    LogUtils.info(
        "Skills: discover context — cwd=${CliConfig.cwd}, dotDir=${CliConfig.dotDir}, bundledRoot=${bundledRootText}"
    )
    let byName = HashMap<String, LoadedSkill>()
    let roots = skillsResolvedRoots(st)
    LogUtils.info("Skills: will scan ${roots.size} skill root(s)")
    for (rootEntry in roots) {
        ingestSkillRoot(rootEntry[1], rootEntry[0], byName, st, true)
    }
    let out = ArrayList<LoadedSkill>()
    for ((_, sk) in byName) {
        out.add(sk)
    }
    if (!out.isEmpty()) {
        let namesSb = StringBuilder()
        var firstName: Bool = true
        for (sk in out) {
            if (!firstName) {
                namesSb.append(", ")
            }
            firstName = false
            namesSb.append(sk.name)
        }
        LogUtils.info("Skills: merged registry (${out.size}): ${namesSb.toString()}")
    } else {
        LogUtils.info("Skills: merged registry empty (no SKILL.md loaded from any root)")
    }
    out
}

private func discoverAndLoadAll(st: SkillsUserSettings): ArrayList<LoadedSkill> {
    let byName = HashMap<String, LoadedSkill>()
    let roots = skillsResolvedRoots(st)

    for (rootEntry in roots) {
        ingestSkillRoot(rootEntry[1], rootEntry[0], byName, st, false)
    }

    let out = ArrayList<LoadedSkill>()
    for ((_, sk) in byName) {
        out.add(sk)
    }
    out
}

private func resolveExtraDir(raw: String): Path {
    let t = raw.trimAscii()
    if (t.isEmpty()) {
        return Path(t)
    }
    let p = Path(t)
    if (p.isAbsolute()) {
        return p
    }
    return CliConfig.cwd.join(t)
}

private func ingestSkillRoot(
    root: Path,
    rootLabel: String,
    byName: HashMap<String, LoadedSkill>,
    st: SkillsUserSettings,
    applyEntriesGate: Bool
): Unit {
    try {
        LogUtils.info("Skills: listing root ${root}")
        var subdirCount: Int64 = 0
        var withSkillMd: Int64 = 0
        for (info in Directory.readFrom(root)) {
            if (!info.isDirectory()) {
                continue
            }
            subdirCount += 1
            let skillMd = info.path.join(SKILL_FILE)
            if (!exists(skillMd)) {
                LogUtils.debug("Skills:   subdir '${info.name}' — no ${SKILL_FILE}, skip")
                continue
            }
            withSkillMd += 1
            LogUtils.info("Skills:   subdir '${info.name}' — found ${SKILL_FILE}, parsing…")
            let (nameRaw, description, body, skillModel, apiKey, apiKeyEnv, metadata) = parseSkillFile(skillMd, info.name, st)
            let name = normalizeSkillNameKey(nameRaw)
            if (name.isEmpty()) {
                LogUtils.info(
                    "Skills:   skip ${skillMd} — empty name (check frontmatter / requires_env / closing ---)"
                )
                continue
            }
            if (applyEntriesGate) {
                if (!passesGate(name, metadata.skillKey, description, body, st)) {
                    LogUtils.info("Skills:   skip '${name}' — disabled in settings.skills.entries")
                    continue
                }
            }
            let prev = byName.get(name)
            byName[name] = LoadedSkill(
                name,
                description,
                body,
                skillMd,
                sourceTagFromRoot(rootLabel, root),
                skillModel,
                apiKey,
                apiKeyEnv,
                metadata
            )
            if (let Some(p) <- prev) {
                LogUtils.info("Skills:   register '${name}' (override earlier from ${p.sourcePath})")
            } else {
                LogUtils.info("Skills:   register '${name}' ← ${skillMd}")
            }
        }
        LogUtils.info(
            "Skills: root ${root} done — ${subdirCount} subdir(s), ${withSkillMd} with ${SKILL_FILE}"
        )
    } catch (ex: Exception) {
        LogUtils.info("Skills: skip root ${root}: ${ex.message}")
    }
}

public func skillsSourceTagForLocation(location: String): String {
    let p = location.replace("\\", "/").toAsciiLower()
    let workspace = skillsWorkspaceDir().toString().replace("\\", "/").toAsciiLower()
    let projectAgents = skillsProjectAgentsDir().toString().replace("\\", "/").toAsciiLower()
    let personalAgents = skillsPersonalAgentsDir().toString().replace("\\", "/").toAsciiLower()
    let managed = skillsManagedDir().toString().replace("\\", "/").toAsciiLower()
    if (p.startsWith(workspace)) {
        return "metis-workspace"
    }
    if (p.startsWith(projectAgents)) {
        return "agents-skills-project"
    }
    if (p.startsWith(personalAgents)) {
        return "agents-skills-personal"
    }
    if (p.startsWith(managed)) {
        return "metis-managed"
    }
    match (skillsBundledDir()) {
        case Some(dir) =>
            let bundled = dir.toString().replace("\\", "/").toAsciiLower()
            if (p.startsWith(bundled)) {
                return "metis-bundled"
            }
        case None => ()
    }
    "metis-extra"
}

private func sourceTagFromRoot(rootLabel: String, root: Path): String {
    let label = rootLabel.toAsciiLower()
    if (label.startsWith("extra:")) {
        return "metis-extra"
    }
    if (label == "bundled/skills") {
        return "metis-bundled"
    }
    if (label == "~/.metis/skills") {
        return "metis-managed"
    }
    if (label == "~/.agents/skills") {
        return "agents-skills-personal"
    }
    if (label == "cwd/.agents/skills") {
        return "agents-skills-project"
    }
    skillsSourceTagForLocation(root.toString())
}

private func passesGate(name: String, skillKey: String, description: String, body: String, st: SkillsUserSettings): Bool {
    let _ = description
    let _ = body
    skillEntryEnabled(st, name, skillKey: skillKey)
}

/** Windows CRLF 下 frontmatter 行尾可能带 `\r`，导致与 `entries` 键不一致。 */
private func normalizeSkillNameKey(s: String): String {
    s.replace("\r", "").replace("\n", "").trimAscii()
}

private func stripYamlQuotedString(v: String): String {
    let t = v.trimAscii()
    if (t.size >= 2) {
        if (t.startsWith('\"') && t.endsWith('\"')) {
            return t[1..t.size-1].trimAscii()
        }
        if (t.startsWith('\'') && t.endsWith('\'')) {
            return t[1..t.size-1].trimAscii()
        }
    }
    t
}

private func parseSkillMetadataArray(obj: JsonObject, key: String): Array<String> {
    match (obj.get(key)) {
        case Some(value) =>
            try {
                let arr = value.asArray()
                let out = ArrayList<String>()
                for (i in 0..arr.size()) {
                    let item = try { arr[i].asString().getValue().trimAscii() } catch (_: Exception) { "" }
                    if (!item.isEmpty()) {
                        out.add(item)
                    }
                }
                out.toArray()
            } catch (_: Exception) {
                []
            }
        case None => []
    }
}

private func parseSkillMetadataString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func parseSkillMetadataObjectArray(obj: JsonObject, key: String): Array<JsonObject> {
    match (obj.get(key)) {
        case Some(value) =>
            try {
                let arr = value.asArray()
                let out = ArrayList<JsonObject>()
                for (i in 0..arr.size()) {
                    try {
                        out.add(arr[i].asObject())
                    } catch (_: Exception) {
                        ()
                    }
                }
                out.toArray()
            } catch (_: Exception) {
                []
            }
        case None => []
    }
}

private func parseSkillMetadataBool(obj: JsonObject, key: String, fallback: Bool): Bool {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asBool().getValue() } catch (_: Exception) {
                try {
                    let text = value.asString().getValue().trimAscii().toAsciiLower()
                    text == "true" || text == "1" || text == "yes" || text == "on"
                } catch (_: Exception) {
                    fallback
                }
            }
        case None => fallback
    }
}

private func looksLikeSkillMetadataNamespace(obj: JsonObject): Bool {
    let knownKeys = [
        "skillKey",
        "primaryEnv",
        "homepage",
        "always",
        "os",
        "user-invocable",
        "disable-model-invocation",
        "requires",
        "install"
    ]
    for (key in knownKeys) {
        if (obj.get(key).isSome()) {
            return true
        }
    }
    false
}

private func canonicalizeSkillMetadataRaw(raw: String): (String, Bool) {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return (raw, false)
    }
    try {
        let metadataObj = JsonValue.fromStr(trimmed).asObject()
        if (metadataObj.get("metis").isSome()) {
            return (trimmed, false)
        }
        var candidateKey = ""
        for ((key, value) in metadataObj.getFields()) {
            if (key == "metis") {
                return (trimmed, false)
            }
            let candidateObj = try {
                value.asObject()
            } catch (_: Exception) {
                continue
            }
            if (!looksLikeSkillMetadataNamespace(candidateObj)) {
                continue
            }
            if (!candidateKey.isEmpty()) {
                return (trimmed, false)
            }
            candidateKey = key
        }
        if (candidateKey.isEmpty()) {
            return (trimmed, false)
        }
        let rebuilt = JsonObject()
        for ((key, value) in metadataObj.getFields()) {
            rebuilt.put(if (key == candidateKey) { "metis" } else { key }, value)
        }
        (rebuilt.toString(), true)
    } catch (_: Exception) {
        (raw, false)
    }
}

private func parseSkillLegacyMetadata(fm: HashMap<String, String>): SkillLegacyMetadata {
    let homepage = stripYamlQuotedString(fm.get("homepage") ?? "")
    let userInvocableRaw = stripYamlQuotedString(fm.get("user-invocable") ?? "")
    let disableModelInvocationRaw = stripYamlQuotedString(fm.get("disable-model-invocation") ?? "")
    let defaultUserInvocable = if (userInvocableRaw.isEmpty()) { true } else {
        let low = userInvocableRaw.toAsciiLower()
        low == "true" || low == "1" || low == "yes" || low == "on"
    }
    let defaultDisableModelInvocation = if (disableModelInvocationRaw.isEmpty()) { false } else {
        let low = disableModelInvocationRaw.toAsciiLower()
        low == "true" || low == "1" || low == "yes" || low == "on"
    }
    match (fm.get("metadata")) {
        case Some(raw) =>
            try {
                let metadataObj = JsonValue.fromStr(raw).asObject()
                let legacyObj = try {
                    metadataObj.get("metis").getOrThrow().asObject()
                } catch (_: Exception) {
                    JsonObject()
                }
                let requiresObj = try {
                    legacyObj.get("requires").getOrThrow().asObject()
                } catch (_: Exception) {
                    JsonObject()
                }
                SkillLegacyMetadata(
                    parseSkillMetadataString(legacyObj, "skillKey"),
                    parseSkillMetadataString(legacyObj, "primaryEnv"),
                    if (!parseSkillMetadataString(legacyObj, "homepage").isEmpty()) {
                        parseSkillMetadataString(legacyObj, "homepage")
                    } else {
                        homepage
                    },
                    parseSkillMetadataBool(legacyObj, "always", false),
                    parseSkillMetadataArray(legacyObj, "os"),
                    parseSkillMetadataBool(legacyObj, "user-invocable", defaultUserInvocable),
                    parseSkillMetadataBool(legacyObj, "disable-model-invocation", defaultDisableModelInvocation),
                    parseSkillMetadataArray(requiresObj, "env"),
                    parseSkillMetadataArray(requiresObj, "bins"),
                    parseSkillMetadataArray(requiresObj, "anyBins"),
                    parseSkillMetadataArray(requiresObj, "config"),
                    parseSkillMetadataObjectArray(legacyObj, "install")
                )
            } catch (_: Exception) {
                SkillLegacyMetadata(
                    "",
                    "",
                    homepage,
                    false,
                    [],
                    defaultUserInvocable,
                    defaultDisableModelInvocation,
                    [],
                    [],
                    [],
                    [],
                    []
                )
            }
        case None =>
            SkillLegacyMetadata(
                "",
                "",
                homepage,
                false,
                [],
                defaultUserInvocable,
                defaultDisableModelInvocation,
                [],
                [],
                [],
                [],
                []
            )
    }
}

private func parseSkillFile(
    skillMd: Path,
    folderName: String,
    st: SkillsUserSettings
): (String, String, String, Option<String>, Option<String>, Option<String>, SkillLegacyMetadata) {
    var content = try {
        String.fromUtf8(readToEnd(File(skillMd, OpenMode.Read)))
    } catch (ex: Exception) {
        LogUtils.info("Skills: read failed ${skillMd}: ${ex.message}")
        return (folderName, "", "", None, None, None, emptySkillLegacyMetadata())
    }
    let lines = content.split("\n")
    if (lines.size > 0 && lines[0].trimAscii() == "---") {
        var endIdx: Int64 = -1
        var i: Int64 = 1
        while (i < lines.size) {
            if (lines[i].trimAscii() == "---") {
                endIdx = i
                break
            }
            i += 1
        }
        if (endIdx > 0) {
            var migrated = ArrayList<String>()
            var changed = false
            var idx: Int64 = 0
            while (idx < lines.size) {
                let line = lines[idx]
                if (idx > 0 && idx < endIdx && line.trimAscii().startsWith("metadata:")) {
                    match (line.indexOf(":")) {
                        case Some(colon) =>
                            let prefix = line[0..colon + 1]
                            let rawValue = line[colon + 1..line.size].trimAscii()
                            let (canonicalValue, migratedFlag) = canonicalizeSkillMetadataRaw(rawValue)
                            if (migratedFlag) {
                                changed = true
                                migrated.add("${prefix} ${canonicalValue}")
                            } else {
                                migrated.add(line)
                            }
                        case None => migrated.add(line)
                    }
                } else {
                    migrated.add(line)
                }
                idx += 1
            }
            if (changed) {
                content = String.join(migrated.toArray(), delimiter: "\n")
                try {
                    File.writeTo(skillMd, content.toArray())
                } catch (ex: Exception) {
                    LogUtils.info("Skills: metadata migration write failed ${skillMd}: ${ex.message}")
                }
            }
        }
    }
    parseSkillMarkdown(content, folderName, st)
}

private func hasConfiguredSkillRequirement(
    st: SkillsUserSettings,
    fallbackName: String,
    metadata: SkillLegacyMetadata,
    envKey: String
): Bool {
    let normalizedEnvKey = envKey.trimAscii()
    if (normalizedEnvKey.isEmpty()) {
        return false
    }
    let configuredKey = metadata.skillKey.trimAscii()
    if (!skillEntryEnvValue(st, fallbackName, normalizedEnvKey, skillKey: configuredKey).isEmpty()) {
        return true
    }
    let primaryEnv = metadata.primaryEnv.trimAscii()
    if (normalizedEnvKey == primaryEnv &&
        !skillEntryApiKey(st, fallbackName, skillKey: configuredKey).trimAscii().isEmpty()) {
        return true
    }
    false
}

private func parseSkillMarkdown(
    content: String,
    fallbackName: String,
    st: SkillsUserSettings
): (String, String, String, Option<String>, Option<String>, Option<String>, SkillLegacyMetadata) {
    let lines = content.split("\n")
    if (lines.size == 0) {
        return (fallbackName, "", content, None, None, None, emptySkillLegacyMetadata())
    }
    if (lines[0].trimAscii() != "---") {
        return (fallbackName, "", content, None, None, None, emptySkillLegacyMetadata())
    }
    var endIdx: Int64 = -1
    var i: Int64 = 1
    while (i < lines.size) {
        if (lines[i].trimAscii() == "---") {
            endIdx = i
            break
        }
        i += 1
    }
    if (endIdx < 0) {
        return (fallbackName, "", content, None, None, None, emptySkillLegacyMetadata())
    }
    let fm = HashMap<String, String>()
    var j: Int64 = 1
    while (j < endIdx) {
        let line = lines[j]
        match (line.indexOf(":")) {
            case Some(colon) =>
                let ke = line[0..colon].trimAscii()
                var ve = line[colon + 1..line.size].trimAscii()
                if (ke == "metadata") {
                    ve = canonicalizeSkillMetadataRaw(ve)[0]
                }
                if (!ke.isEmpty()) {
                    fm[ke] = ve
                }
            case None => ()
        }
        j += 1
    }
    var bodyLines = ArrayList<String>()
    var k: Int64 = endIdx + 1
    while (k < lines.size) {
        bodyLines.add(lines[k])
        k += 1
    }
    let body = String.join(bodyLines.toArray(), delimiter: "\n").trimAscii()
    let name = match (fm.get("name")) {
        case Some(s) => s
        case None => fallbackName
    }
    let description = match (fm.get("description")) {
        case Some(s) => s
        case None => ""
    }
    let metadata = parseSkillLegacyMetadata(fm)
    let requiresEnv = match (fm.get("requires_env")) {
        case Some(s) => s
        case None => ""
    }
    if (!requiresEnv.isEmpty()) {
        for (part in requiresEnv.split(",")) {
            let key = part.trimAscii()
            if (!key.isEmpty()) {
                if (getVariable(key).isNone() &&
                    !hasConfiguredSkillRequirement(st, fallbackName, metadata, key)) {
                    LogUtils.info(
                        "Skills: parse ${fallbackName} — requires_env '${key}' not set in env or settings.skills.entries, skill skipped"
                    )
                    return ("", "", "", None, None, None, metadata)
                }
            }
        }
    }

    let skillModel: Option<String> = match (fm.get("model")) {
        case Some(s) =>
            let m = stripYamlQuotedString(s)
            if (m.isEmpty()) {
                None
            } else {
                Some(m)
            }
        case None => None
    }

    // Recommended keys: api_key_env, api_key
    // We accept a few variants to make it less brittle.
    let apiKeyEnvRaw: Option<String> = match (fm.get("api_key_env")) {
        case Some(s) => Some(s)
        case None =>
            match (fm.get("apikey_env")) {
                case Some(s) => Some(s)
                case None =>
                    match (fm.get("apiKeyEnv")) {
                        case Some(s) => Some(s)
                        case None => None
                    }
            }
    }
    let apiKeyEnv: Option<String> = match (apiKeyEnvRaw) {
        case Some(v) =>
            let vv = stripYamlQuotedString(v)
            if (vv.isEmpty()) {
                None
            } else {
                Some(vv)
            }
        case None => None
    }

    let apiKeyRaw: Option<String> = match (fm.get("api_key")) {
        case Some(s) => Some(s)
        case None =>
            match (fm.get("apikey")) {
                case Some(s) => Some(s)
                case None =>
                    match (fm.get("apiKey")) {
                        case Some(s) => Some(s)
                        case None => None
                    }
            }
    }
    let apiKey: Option<String> = match (apiKeyRaw) {
        case Some(v) =>
            let vv = stripYamlQuotedString(v)
            if (vv.isEmpty()) {
                None
            } else {
                Some(vv)
            }
        case None => None
    }

    (name, description, body, skillModel, apiKey, apiKeyEnv, metadata)
}

private func formatPrompt(skills: ArrayList<LoadedSkill>): String {
    var total: Int64 = 0
    let sb = StringBuilder()
    sb.append(
        "\n\n# Agent skills（SKILL.md，按需遵循；名称后者覆盖前者）\n\n" +
            "以下为当前工作区与用户目录下已启用的技能说明正文，用于工作流与规范；无工具自动注册，由你在对话中落实。\n\n"
    )
    for (sk in skills) {
        if (sk.name.isEmpty()) {
            continue
        }
        var b = sk.body
        if (b.size > MAX_BODY_PER_SKILL) {
            // Avoid byte-slicing UTF-8 in the middle of a codepoint.
            b = "(skill body omitted: exceeds MAX_BODY_PER_SKILL)"
        }
        let chunk =
            "## ${sk.name}\n" + (if (!sk.description.isEmpty()) {
                "${sk.description}\n\n"
            } else {
                ""
            }) + "${b}\n\n---\n"
        let add = chunk.size
        if (total + add > MAX_TOTAL_PROMPT) {
            sb.append("\n…(更多技能因长度上限省略)\n")
            break
        }
        sb.append(chunk)
        total += add
    }
    sb.toString()
}
