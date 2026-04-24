package metis.core.prompting

import magic.core.tool.Tool

import metis.core.config.CliConfig

import std.collection.{ArrayList, HashMap}
import std.sort.sort

private const SILENT_REPLY_TOKEN = "<SILENT_REPLY>"
private const SYSTEM_PROMPT_CACHE_BOUNDARY = "<SYSTEM_PROMPT_CACHE_BOUNDARY>"
private const CONTEXT_FILE_ORDER_FALLBACK: Int64 = 9223372036854775807
private const TOOL_FILE_MULTI_EDIT = "fileMultiEdit"
private const TOOL_CANGJIE_RETRIEVE_DOCUMENTS = "cangjieRetrieveDocuments"
private const TOOL_CANGJIE_INIT_PROJECT = "cangjieInitProject"
private const TOOL_CANGJIE_COMPILE_FILE = "cangjieCompileFile"
private const TOOL_CANGJIE_BUILD_PROJECT = "cangjieBuildProject"
private const TOOL_CANGJIE_CLEAN_PROJECT = "cangjieCleanProject"
private const TOOL_UPDATE_PLAN = "update_plan"
private const TOOL_TODO_CREATE = "todoCreate"
private const TOOL_TASK_BREAKDOWN = "taskBreakDown"
private const TOOL_TASK_MARK_COMPLETE = "taskMarkComplete"
private const TOOL_TODO_REVIEW = "todoReview"

public enum PromptMode {
    | FullMode
    | MinimalMode
    | NoneMode
}

public class MetisPromptRuntimeInfo {
    public var agentId: String = ""
    public var host: String = ""
    public var os: String = ""
    public var arch: String = ""
    public var node: String = ""
    public var model: String = ""
    public var defaultModel: String = ""
    public var shell: String = ""
    public var channel: String = ""
    public var nativeApprovalUiAvailable: Bool = false
    public var repoRoot: String = ""
    public var capabilities: Array<String> = []
    public init() {}
}

public class MetisPromptSandboxElevatedInfo {
    public var allowed: Bool = false
    public var defaultLevel: String = ""
    public init() {}
}

public class MetisPromptSandboxInfo {
    public var enabled: Bool = false
    public var containerWorkspaceDir: String = ""
    public var workspaceDir: String = ""
    public var workspaceAccess: String = ""
    public var agentWorkspaceMount: String = ""
    public var browserBridgeUrl: String = ""
    public var browserNoVncUrl: String = ""
    public var hostBrowserAllowed: String = ""
    public var elevated: MetisPromptSandboxElevatedInfo = MetisPromptSandboxElevatedInfo()
    public init() {}
}

public class MetisReactionGuidance {
    public var level: String = ""
    public var channel: String = ""
    public init() {}
}

public class MetisSystemPromptSectionOverrides {
    public var interactionStyle: String = ""
    public var toolCallStyle: String = ""
    public var executionBias: String = ""
    public init() {}
}

public class MetisProviderPromptContribution {
    public var stablePrefix: String = ""
    public var dynamicSuffix: String = ""
    public var sectionOverrides: MetisSystemPromptSectionOverrides = MetisSystemPromptSectionOverrides()
    public init() {}
}

public class MetisContextFile {
    public var path: String = ""
    public var content: String = ""
    public init() {}
    public init(path: String, content: String) {
        this.path = path
        this.content = content
    }
}

public class MetisSystemPromptParams {
    public var workspaceDir: String = ""
    public var defaultThinkLevel: String = "off"
    public var reasoningLevel: String = "off"
    public var extraSystemPrompt: String = ""
    public var ownerNumbers: Array<String> = []
    public var reasoningTagHint: Bool = false
    public var toolNames: Array<String> = []
    public var modelAliasLines: Array<String> = []
    public var userTimezone: String = ""
    public var skillsPrompt: String = ""
    public var heartbeatPrompt: String = ""
    public var docsPath: String = ""
    public var workspaceNotes: Array<String> = []
    public var ttsHint: String = ""
    public var promptMode: PromptMode = PromptMode.FullMode
    public var acpEnabled: Bool = true
    public var memoryPromptSectionLines: Array<String> = []
    public var runtimeInfo: MetisPromptRuntimeInfo = MetisPromptRuntimeInfo()
    public var messageToolHints: Array<String> = []
    public var sandboxInfo: MetisPromptSandboxInfo = MetisPromptSandboxInfo()
    public var reactionGuidance: MetisReactionGuidance = MetisReactionGuidance()
    public var contextFiles: Array<MetisContextFile> = []
    public var extraSections: Array<String> = []
    public var promptContribution: MetisProviderPromptContribution = MetisProviderPromptContribution()
    public init() {}
}

private let TOOL_SUMMARIES = HashMap<String, String>([
    ("read", "Read file contents"),
    ("write", "Create or overwrite files"),
    ("edit", "Make precise edits to files"),
    ("apply_patch", "Apply multi-file patches"),
    ("grep", "Search file contents for patterns"),
    ("find", "Find files by glob pattern"),
    ("ls", "List directory contents"),
    ("exec", "Run shell commands"),
    ("process", "Manage background commands"),
    ("web_search", "Search the web"),
    ("fileRead", "Read file contents"),
    ("fileWrite", "Create or overwrite files"),
    ("fileEdit", "Make precise edits to files"),
    (TOOL_FILE_MULTI_EDIT, "Apply multi-file patches"),
    ("grepSearch", "Search file contents for patterns"),
    ("globSearch", "Find files by glob pattern"),
    ("listDirectory", "List directory contents"),
    ("shellExecute", "Run shell commands"),
    ("fileBatchRead", "Read multiple files efficiently"),
    ("fileCreate", "Create new files"),
    ("weather", "Get weather information"),
    ("basicMediaInspect", "Inspect local media/PDF metadata"),
    ("sessionsList", "List local gateway sessions"),
    ("sessionsHistory", "Read local gateway session transcript"),
    ("sessionsSend", "Append a local gateway session message"),
    ("sessionsSpawn", "Create a local gateway session"),
    ("gateway", "Control the local gateway runtime and gateway configuration"),
    ("cron", "Manage local cron jobs and trigger cron runs"),
    ("message", "Send gateway-backed messages, replies, reactions, and poll payloads"),
    ("memory_search", "Search MEMORY.md and memory/*.md for relevant recalled snippets"),
    ("memory_get", "Read a specific snippet from MEMORY.md or memory/*.md"),
    ("session_status", "Inspect local runtime and managed session state"),
    ("sessions_send", "Append a message to a target session by sessionKey or label"),
    ("sessions_spawn", "Create a managed session and optionally launch subagent or ACP work"),
    ("sessions_list", "List persisted local sessions with optional transcript excerpts"),
    ("subagents", "List, steer, and kill managed spawned sessions"),
    ("update_plan", "Replace the current top-level plan with structured steps"),
    (TOOL_CANGJIE_RETRIEVE_DOCUMENTS, "Retrieve Cangjie documentation"),
    (TOOL_CANGJIE_INIT_PROJECT, "Initialize a Cangjie project"),
    (TOOL_CANGJIE_COMPILE_FILE, "Compile a single Cangjie source file"),
    (TOOL_CANGJIE_BUILD_PROJECT, "Build a Cangjie project"),
    (TOOL_CANGJIE_CLEAN_PROJECT, "Clean Cangjie build artifacts"),
    ("fixCangjieProjectCompileError", "Fix Cangjie compilation errors"),
    (TOOL_TODO_CREATE, "Create or replace a task plan"),
    (TOOL_TASK_BREAKDOWN, "Break a parent task into subtasks"),
    (TOOL_TASK_MARK_COMPLETE, "Mark a task complete"),
    (TOOL_TODO_REVIEW, "Review the current task plan"),
    ("ExplorerAgent", "Explore the codebase and report findings"),
    ("EditorAgent", "Apply focused code edits"),
    ("ReviewerAgent", "Review code for risks and regressions"),
    ("TestGeneratorAgent", "Generate tests for changed code"),
    ("RefactoringAgent", "Perform bounded refactors"),
    ("lspGetAllSymbols", "List symbols in a Cangjie file"),
    ("lspFindSymbolsByKind", "Find symbols of a specific kind"),
    ("lspFindSymbolByName", "Find a symbol by name"),
    ("lspFindSymbolReference", "Find references to a symbol"),
    ("lspFindSymbolDefinition", "Locate a symbol definition")
])

private let CONTEXT_FILE_ORDER = HashMap<String, Int64>([
    ("agents.md", 10),
    ("soul.md", 20),
    ("identity.md", 30),
    ("user.md", 40),
    ("tools.md", 50),
    ("bootstrap.md", 60),
    ("memory.md", 70)
])

private func appendLines(target: ArrayList<String>, lines: Array<String>): Unit {
    for (line in lines) {
        if (!line.isEmpty()) {
            target.add(line)
        }
    }
}

private func normalizeText(value: String): String {
    value.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
}

private func sanitizeForPromptLiteral(value: String): String {
    normalizeText(value).replace("\n", " ")
}

private func buildSandboxSection(
    sandboxInfo: MetisPromptSandboxInfo,
    hasSessionsSpawn: Bool,
    acpEnabled: Bool
): Array<String> {
    if (!sandboxInfo.enabled) {
        return []
    }
    let lines = ArrayList<String>()
    lines.add("## Sandbox")
    lines.add("You are running in a sandboxed runtime (tools execute in Docker).")
    lines.add("Some tools may be unavailable due to sandbox policy.")
    lines.add("Sub-agents stay sandboxed (no elevated/host access). Need outside-sandbox read/write? Don't spawn; ask first.")
    if (hasSessionsSpawn && acpEnabled) {
        lines.add("ACP harness spawns are blocked from sandboxed sessions (`sessions_spawn` with `runtime: \"acp\"`). Use `runtime: \"subagent\"` instead.")
    }
    let containerWorkspaceDir = sanitizeForPromptLiteral(sandboxInfo.containerWorkspaceDir)
    if (!containerWorkspaceDir.isEmpty()) {
        lines.add("Sandbox container workdir: ${containerWorkspaceDir}")
    }
    let workspaceDir = sanitizeForPromptLiteral(sandboxInfo.workspaceDir)
    if (!workspaceDir.isEmpty()) {
        lines.add("Sandbox host mount source (file tools bridge only; not valid inside sandbox exec): ${workspaceDir}")
    }
    let workspaceAccess = sanitizeForPromptLiteral(sandboxInfo.workspaceAccess)
    if (!workspaceAccess.isEmpty()) {
        let mount = sanitizeForPromptLiteral(sandboxInfo.agentWorkspaceMount)
        if (mount.isEmpty()) {
            lines.add("Agent workspace access: ${workspaceAccess}")
        } else {
            lines.add("Agent workspace access: ${workspaceAccess} (mounted at ${mount})")
        }
    }
    if (!sanitizeForPromptLiteral(sandboxInfo.browserBridgeUrl).isEmpty()) {
        lines.add("Sandbox browser: enabled.")
    }
    let browserNoVncUrl = sanitizeForPromptLiteral(sandboxInfo.browserNoVncUrl)
    if (!browserNoVncUrl.isEmpty()) {
        lines.add("Sandbox browser observer (noVNC): ${browserNoVncUrl}")
    }
    if (sandboxInfo.hostBrowserAllowed == "true") {
        lines.add("Host browser control: allowed.")
    } else if (sandboxInfo.hostBrowserAllowed == "false") {
        lines.add("Host browser control: blocked.")
    }
    if (sandboxInfo.elevated.allowed) {
        lines.add("Elevated exec is available for this session.")
        lines.add("User can toggle with /elevated on|off|ask|full.")
        lines.add("You may also send /elevated on|off|ask|full when needed.")
        let defaultLevel = sanitizeForPromptLiteral(sandboxInfo.elevated.defaultLevel)
        if (!defaultLevel.isEmpty()) {
            lines.add("Current elevated level: ${defaultLevel} (ask runs exec on host with approvals; full auto-approves).")
        }
    }
    lines.add("")
    lines.toArray()
}

private func containsTool(toolNames: Array<String>, target: String): Bool {
    let needle = target.trimAscii().toAsciiLower()
    for (name in toolNames) {
        if (name.trimAscii().toAsciiLower() == needle) {
            return true
        }
    }
    return false
}

private func appendIfMissing(target: ArrayList<String>, value: String): Unit {
    let normalized = value.trimAscii()
    if (normalized.isEmpty()) {
        return
    }
    for (existing in target) {
        if (existing.trimAscii().toAsciiLower() == normalized.toAsciiLower()) {
            return
        }
    }
    target.add(normalized)
}

private func buildToolSummaryLines(toolNames: Array<String>): Array<String> {
    let lines = ArrayList<String>()
    let seen = ArrayList<String>()
    for (toolName in toolNames) {
        let normalized = toolName.trimAscii()
        if (normalized.isEmpty()) {
            continue
        }
        if (containsTool(seen.toArray(), normalized)) {
            continue
        }
        seen.add(normalized)
        let summary = TOOL_SUMMARIES.get(normalized) ?? ""
        if (summary.isEmpty()) {
            lines.add("- ${normalized}")
        } else {
            lines.add("- ${normalized}: ${summary}")
        }
    }
    return lines.toArray()
}

private func normalizeCapabilityIds(capabilities: Array<String>): Array<String> {
    let ordered = ArrayList<String>()
    for (cap in capabilities) {
        let normalized = cap.trimAscii().toAsciiLower()
        if (normalized.isEmpty()) {
            continue
        }
        appendIfMissing(ordered, normalized)
    }
    return ordered.toArray()
}

private func buildOwnerLine(ownerNumbers: Array<String>): String {
    let numbers = ArrayList<String>()
    for (value in ownerNumbers) {
        let trimmed = value.trimAscii()
        if (!trimmed.isEmpty()) {
            numbers.add(trimmed)
        }
    }
    if (numbers.isEmpty()) {
        return ""
    }
    return "Authorized senders: ${String.join(numbers.toArray(), delimiter: ", ")}. These senders are allowlisted; do not assume they are the owner."
}

private func buildSkillsSection(skillsPrompt: String, readToolName: String, isMinimal: Bool): Array<String> {
    if (isMinimal) {
        return []
    }
    let trimmed = normalizeText(skillsPrompt)
    if (trimmed.isEmpty()) {
        return []
    }
    return [
        "## Skills (mandatory)",
        "Before replying: scan <available_skills> metadata entries.",
        "- If exactly one skill clearly applies: use `${readToolName}` to read SKILL.md at <location>, then follow it.",
        "- If multiple could apply: choose the most specific one, then read/follow it.",
        "- If none clearly apply: do not read any SKILL.md.",
        "Constraints: never read more than one skill up front; only read after selecting.",
        "Do not fabricate skill paths. Only use <location> values already listed in <available_skills>.",
        "- When a skill drives external API writes, assume rate limits: prefer fewer larger writes, avoid tight one-item loops, serialize bursts when possible, and respect 429/Retry-After.",
        trimmed,
        ""
    ]
}

private func buildTimeSection(userTimezone: String): Array<String> {
    let trimmed = userTimezone.trimAscii()
    if (trimmed.isEmpty()) {
        return []
    }
    return ["## Current Date & Time", "Time zone: ${trimmed}", ""]
}

private func buildUserIdentitySection(ownerLine: String, isMinimal: Bool): Array<String> {
    if (isMinimal || ownerLine.isEmpty()) {
        return []
    }
    return ["## Authorized Senders", ownerLine, ""]
}

private func buildMemoryRecallSection(toolNames: Array<String>, isMinimal: Bool): Array<String> {
    if (isMinimal) {
        return []
    }
    let hasMemorySearch = containsTool(toolNames, "memory_search")
    let hasMemoryGet = containsTool(toolNames, "memory_get")
    if (!hasMemorySearch && !hasMemoryGet) {
        return []
    }
    if (hasMemorySearch && hasMemoryGet) {
        return [
            "## Memory Recall",
            "Before answering anything about prior work, decisions, dates, people, preferences, or todos: run memory_search on MEMORY.md + memory/*.md; then use memory_get to pull only the needed lines. If low confidence after search, say you checked.",
            "Citations: include Source: <path#line> when it helps the user verify memory snippets.",
            ""
        ]
    }
    if (hasMemorySearch) {
        return [
            "## Memory Recall",
            "Before answering anything about prior work, decisions, dates, people, preferences, or todos: run memory_search on MEMORY.md + memory/*.md and answer from the matching results. If low confidence after search, say you checked.",
            "Citations: include Source: <path#line> when it helps the user verify memory snippets.",
            ""
        ]
    }
    return [
        "## Memory Recall",
        "Before answering anything about prior work, decisions, dates, people, preferences, or todos that already point to a specific memory file or note: run memory_get to pull only the needed lines. If low confidence after reading them, say you checked.",
        "Citations: include Source: <path#line> when it helps the user verify memory snippets.",
        ""
    ]
}

private func buildMemorySection(memoryPromptSectionLines: Array<String>, isMinimal: Bool): Array<String> {
    if (isMinimal) {
        return []
    }
    let lines = memoryPromptSectionLines
    if (lines.isEmpty()) {
        return []
    }
    let out = ArrayList<String>(["## Memory"])
    for (line in lines) {
        let normalized = normalizeText(line)
        if (!normalized.isEmpty()) {
            out.add(normalized)
        }
    }
    out.add("")
    out.toArray()
}

private func buildReplyTagsSection(isMinimal: Bool): Array<String> {
    if (isMinimal) {
        return []
    }
    return [
        "## Reply Tags",
        "To request a native reply/quote on supported surfaces, include one tag in your reply:",
        "- Reply tags must be the very first token in the message (no leading text/newlines): [[reply_to_current]] your reply.",
        "- [[reply_to_current]] replies to the triggering message.",
        "- Prefer [[reply_to_current]]. Use [[reply_to:<id>]] only when an id was explicitly provided (e.g. by the user or a tool).",
        "Whitespace inside the tag is allowed (e.g. [[ reply_to_current ]] / [[ reply_to: 123 ]]).",
        "Tags are stripped before sending; support depends on the current channel config.",
        ""
    ]
}

private func buildExecApprovalPromptGuidance(nativeApprovalUiAvailable: Bool, inlineButtonsEnabled: Bool): String {
    if (nativeApprovalUiAvailable || inlineButtonsEnabled) {
        return "When exec returns approval-pending on this channel, rely on native approval card/buttons when they appear and do not also send plain chat /approve instructions. Only include the concrete /approve command if the tool result says chat approvals are unavailable or only manual approval is possible."
    }
    return "When exec returns approval-pending, include the concrete /approve command from tool output as plain chat text for the user, and do not ask for a different or rotated code."
}

private func buildMessagingSection(
    isMinimal: Bool,
    availableTools: Array<String>,
    runtimeChannel: String,
    runtimeCapabilities: Array<String>,
    messageToolHints: Array<String>,
    isCompact!: Bool = false
): Array<String> {
    if (isMinimal) {
        return []
    }
    let lines = ArrayList<String>([
        "## Messaging",
        "- Reply in current session -> automatically routes to the source channel (Signal, Telegram, etc.)",
        "- Cross-session messaging -> use sessions_send(sessionKey, message)"
    ])
    if (containsTool(availableTools, "subagents")) {
        lines.add("- Sub-agent orchestration -> use subagents(action=list|steer|kill)")
    }
    lines.add("- Runtime-generated completion events may ask for a user update. Rewrite those in your normal assistant voice and send the update (do not forward raw internal metadata or default to ${SILENT_REPLY_TOKEN}).")
    lines.add("- Never use exec/curl for provider messaging; Metis handles all routing internally.")
    if (isCompact) {
        if (containsTool(availableTools, "message")) {
            lines.add("- Use `message` only for proactive sends or channel actions. If it already delivered the visible reply, respond with ONLY ${SILENT_REPLY_TOKEN}.")
        }
        lines.add("")
        return lines.toArray()
    }
    if (containsTool(availableTools, "message")) {
        lines.add("")
        lines.add("### message tool")
        lines.add("- Use `message` for proactive sends + channel actions (polls, reactions, etc.).")
        lines.add("- For `action=send`, include `to` and `message`.")
        lines.add("- If you use `message` (`action=send`) to deliver your user-visible reply, respond with ONLY: ${SILENT_REPLY_TOKEN} (avoid duplicate replies).")
        if (containsTool(runtimeCapabilities, "inlinebuttons")) {
            lines.add("- Inline buttons supported. Use `action=send` with `buttons=[[{text,callback_data,style?}]]`; `style` can be `primary`, `success`, or `danger`.")
        } else if (!runtimeChannel.isEmpty()) {
            lines.add("- Inline buttons not enabled for ${runtimeChannel}. If you need them, ask to set ${runtimeChannel}.capabilities.inlineButtons (\"dm\"|\"group\"|\"all\"|\"allowlist\").")
        }
    }
    for (hint in messageToolHints) {
        let trimmed = normalizeText(hint)
        if (!trimmed.isEmpty()) {
            lines.add(trimmed)
        }
    }
    lines.add("")
    return lines.toArray()
}

private func buildVoiceSection(isMinimal: Bool, ttsHint: String): Array<String> {
    if (isMinimal) {
        return []
    }
    let trimmed = normalizeText(ttsHint)
    if (trimmed.isEmpty()) {
        return []
    }
    return ["## Voice (TTS)", trimmed, ""]
}

private func buildDocsSection(isMinimal: Bool, docsPath: String): Array<String> {
    let trimmed = docsPath.trimAscii()
    if (isMinimal || trimmed.isEmpty()) {
        return []
    }
    return [
        "## Documentation",
        "Metis docs: ${trimmed}",
        "Mirror: https://docs.metis.ai",
        "Source: https://github.com/metis/metis",
        "Community: https://discord.com/invite/clawd",
        "Find new skills: https://clawhub.ai",
        "For Metis behavior, commands, config, or architecture: consult local docs first.",
        "When diagnosing issues, run `metis status` yourself when possible; only ask the user if you lack access (e.g., sandboxed).",
        ""
    ]
}

private func buildExecutionBiasSection(isMinimal: Bool): Array<String> {
    if (isMinimal) {
        return []
    }
    return [
        "## Execution Bias",
        "If the user asks you to do the work, start doing it in the same turn.",
        "Use a real tool call or concrete action first when the task is actionable; do not stop at a plan or promise-to-act reply.",
        "Commentary-only turns are incomplete when tools are available and the next action is clear.",
        "If the work will take multiple steps or a while to finish, send one short progress update before or while acting.",
        ""
    ]
}

private func buildReasoningFormatSection(reasoningTagHint: Bool): Array<String> {
    if (!reasoningTagHint) {
        return []
    }
    return [
        "## Reasoning Format",
        "ALL internal reasoning MUST be inside <think>...</think>. Do not output any analysis outside <think>. Format every reply as <think>...</think> then <final>...</final>, with no other text. Only the final user-visible reply may appear inside <final>. Only text inside <final> is shown to the user; everything else is discarded and never seen by the user.",
        ""
    ]
}

private func buildOverridableSection(override: String, fallback: Array<String>): Array<String> {
    let normalizedOverride = normalizeText(override)
    if (!normalizedOverride.isEmpty()) {
        return [normalizedOverride, ""]
    }
    return fallback
}

private func getContextFileBasename(path: String): String {
    let normalized = normalizeContextFilePath(path)
    if (normalized.isEmpty()) {
        return ""
    }
    let parts = normalized.split("/")
    if (parts.isEmpty()) {
        return normalized.toAsciiLower()
    }
    return parts[parts.size - 1].toAsciiLower()
}

private func normalizeContextFilePath(path: String): String {
    path.trimAscii().replace("\\", "/")
}

private func isDynamicContextFile(path: String): Bool {
    getContextFileBasename(path) == "heartbeat.md"
}

private func isPromptModeNone(mode: PromptMode): Bool {
    match (mode) {
        case PromptMode.NoneMode => true
        case _ => false
    }
}

private func isPromptModeMinimal(mode: PromptMode): Bool {
    match (mode) {
        case PromptMode.MinimalMode => true
        case _ => false
    }
}

private func sortContextFiles(files: Array<MetisContextFile>): Array<MetisContextFile> {
    let ordered = ArrayList<MetisContextFile>()
    for (file in files) {
        let path = file.path.trimAscii()
        if (path.isEmpty()) {
            continue
        }
    }
    for (file in files) {
        if (!file.path.trimAscii().isEmpty()) {
            ordered.add(file)
        }
    }
    sort(ordered, by: { a, b =>
        let aPath = normalizeContextFilePath(a.path)
        let bPath = normalizeContextFilePath(b.path)
        let aBase = getContextFileBasename(a.path)
        let bBase = getContextFileBasename(b.path)
        let aOrder = if (let Some(value) <- CONTEXT_FILE_ORDER.get(aBase)) { value } else { CONTEXT_FILE_ORDER_FALLBACK }
        let bOrder = if (let Some(value) <- CONTEXT_FILE_ORDER.get(bBase)) { value } else { CONTEXT_FILE_ORDER_FALLBACK }
        if (aOrder != bOrder) {
            aOrder.compare(bOrder)
        } else if (aBase != bBase) {
            aBase.compare(bBase)
        } else {
            aPath.compare(bPath)
        }
    }, stable: true)
    return ordered.toArray()
}

private func buildProjectContextSection(
    files: Array<MetisContextFile>,
    heading: String,
    dynamic: Bool
): Array<String> {
    if (files.isEmpty()) {
        return []
    }
    let lines = ArrayList<String>([heading, ""])
    if (dynamic) {
        lines.add("The following frequently-changing project context files are kept below the cache boundary when possible:")
        lines.add("")
    } else {
        lines.add("The following project context files have been loaded:")
        var hasSoul = false
        for (file in files) {
            if (getContextFileBasename(file.path) == "soul.md") {
                hasSoul = true
                break
            }
        }
        if (hasSoul) {
            lines.add("If SOUL.md is present, embody its persona and tone. Avoid stiff, generic replies; follow its guidance unless higher-priority instructions override it.")
        }
        lines.add("")
    }
    for (file in files) {
        lines.add("## ${file.path}")
        lines.add("")
        lines.add(file.content)
        lines.add("")
    }
    return lines.toArray()
}

private func buildRuntimeLine(
    runtimeInfo: MetisPromptRuntimeInfo,
    runtimeChannel: String,
    runtimeCapabilities: Array<String>,
    defaultThinkLevel: String
): String {
    let parts = ArrayList<String>()
    if (!runtimeInfo.agentId.trimAscii().isEmpty()) { parts.add("agent=${runtimeInfo.agentId}") }
    if (!runtimeInfo.host.trimAscii().isEmpty()) { parts.add("host=${runtimeInfo.host}") }
    if (!runtimeInfo.repoRoot.trimAscii().isEmpty()) { parts.add("repo=${runtimeInfo.repoRoot}") }
    if (!runtimeInfo.os.trimAscii().isEmpty()) {
        if (!runtimeInfo.arch.trimAscii().isEmpty()) {
            parts.add("os=${runtimeInfo.os} (${runtimeInfo.arch})")
        } else {
            parts.add("os=${runtimeInfo.os}")
        }
    } else if (!runtimeInfo.arch.trimAscii().isEmpty()) {
        parts.add("arch=${runtimeInfo.arch}")
    }
    if (!runtimeInfo.node.trimAscii().isEmpty()) { parts.add("node=${runtimeInfo.node}") }
    if (!runtimeInfo.model.trimAscii().isEmpty()) { parts.add("model=${runtimeInfo.model}") }
    if (!runtimeInfo.defaultModel.trimAscii().isEmpty()) { parts.add("default_model=${runtimeInfo.defaultModel}") }
    if (!runtimeInfo.shell.trimAscii().isEmpty()) { parts.add("shell=${runtimeInfo.shell}") }
    if (!runtimeChannel.isEmpty()) {
        parts.add("channel=${runtimeChannel}")
        let capabilities = normalizeCapabilityIds(runtimeCapabilities)
        if (capabilities.isEmpty()) {
            parts.add("capabilities=none")
        } else {
            parts.add("capabilities=${String.join(capabilities, delimiter: ",")}")
        }
    }
    parts.add("thinking=${defaultThinkLevel}")
    return "Runtime: ${String.join(parts.toArray(), delimiter: " | ")}"
}

private func resolveDefaultParams(toolNames: Array<String>): MetisSystemPromptParams {
    let params = MetisSystemPromptParams()
    params.workspaceDir = CliConfig.cwd.toString()
    params.toolNames = toolNames
    params.defaultThinkLevel = "off"
    params.reasoningLevel = "off"
    params.runtimeInfo.model = CliConfig.model
    return params
}

private func normalizeProviderName(model: String): String {
    let trimmed = model.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    if (let Some(pivot) <- trimmed.indexOf(b':')) {
        return trimmed[0..pivot].trimAscii().toAsciiLower()
    }
    return ""
}

public class MetisSystemPromptBuilder {
    public static func buildForMainAgent(toolNames: Array<String>, cangjieMode!: Bool): String {
        let params = resolveDefaultParams(toolNames)
        return build(params, cangjieMode: cangjieMode)
    }

    public static func build(params: MetisSystemPromptParams, cangjieMode!: Bool): String {
        if (isPromptModeNone(params.promptMode)) {
            return "You are an AI assistant."
        }

        let toolNames = params.toolNames
        let isMinimal = isPromptModeMinimal(params.promptMode)
        let runtimeChannel = params.runtimeInfo.channel.trimAscii().toAsciiLower()
        let runtimeCapabilities = params.runtimeInfo.capabilities
        let isGatewayCompact = !runtimeChannel.isEmpty() && !isMinimal
        let nativeApprovalUiAvailable = params.runtimeInfo.nativeApprovalUiAvailable ||
            containsTool(runtimeCapabilities, "nativeapprovalui") ||
            containsTool(runtimeCapabilities, "native-approval-ui")
        let inlineButtonsEnabled = containsTool(runtimeCapabilities, "inlinebuttons")
        let ownerLine = buildOwnerLine(params.ownerNumbers)
        let hasGateway = containsTool(toolNames, "gateway")
        let hasExecTool = containsTool(toolNames, "exec") || containsTool(toolNames, "shellExecute")
        let hasProcessTool = containsTool(toolNames, "process")
        let hasCronTool = containsTool(toolNames, "cron") || toolNames.isEmpty()
        let hasUpdatePlanTool = containsTool(toolNames, "update_plan")
        let hasSessionsSpawn = containsTool(toolNames, "sessions_spawn")
        let hasSubagentsTool = containsTool(toolNames, "subagents")
        let acpHarnessSpawnAllowed = hasSessionsSpawn && params.acpEnabled && !params.sandboxInfo.enabled
        let readToolName = if (containsTool(toolNames, "read")) { "read" } else { "fileRead" }
        let execToolName = if (containsTool(toolNames, "exec")) { "exec" } else if (containsTool(toolNames, "shellExecute")) { "shellExecute" } else { "" }
        let processToolName = "process"
        let providerStablePrefix = normalizeText(params.promptContribution.stablePrefix)
        let providerDynamicSuffix = normalizeText(params.promptContribution.dynamicSuffix)
        let displayWorkspaceDir = if (params.sandboxInfo.enabled && !params.sandboxInfo.containerWorkspaceDir.trimAscii().isEmpty()) {
            params.sandboxInfo.containerWorkspaceDir.trimAscii()
        } else {
            params.workspaceDir.trimAscii()
        }
        let workspaceGuidance = if (params.sandboxInfo.enabled && !params.sandboxInfo.containerWorkspaceDir.trimAscii().isEmpty()) {
            let sanitizedWorkspaceDir = sanitizeForPromptLiteral(params.workspaceDir)
            let sanitizedContainerWorkspaceDir = sanitizeForPromptLiteral(params.sandboxInfo.containerWorkspaceDir)
            "For read/write/edit/apply_patch, file paths resolve against host workspace: ${sanitizedWorkspaceDir}. For bash/exec commands, use sandbox container paths under ${sanitizedContainerWorkspaceDir} (or relative paths from that workdir), not host paths. Prefer relative paths so both sandboxed exec and file tools work consistently."
        } else {
            "Treat this directory as the single global workspace for file operations unless explicitly instructed otherwise."
        }

        let lines = ArrayList<String>([
            "You are an AI assistant.",
            "Do not describe yourself as Metis, Magic CLI, or a local app unless the user explicitly asks about the runtime or product identity.",
            "",
            "## Tooling",
            if (isGatewayCompact) {
                "Use structured tool definitions as the only source of truth for tool names and parameters."
            } else {
                "Structured tool definitions are the source of truth for tool names, descriptions, and parameters."
            },
            "Tool names are case-sensitive. Call tools exactly as listed in the structured tool definitions.",
            if (isGatewayCompact) {
                "If a tool is listed, treat it as available unless a tool call reports a policy/runtime restriction."
            } else {
                "If a tool is present in the structured tool definitions, it is available unless a later tool call reports a policy/runtime restriction."
            },
            if (isGatewayCompact) {
                "TOOLS.md is only usage guidance."
            } else {
                "TOOLS.md does not control tool availability; it is user guidance for how to use external tools."
            }
        ])

        if (!toolNames.isEmpty()) {
            appendLines(lines, buildToolSummaryLines(toolNames))
        }

        if (hasExecTool && hasCronTool) {
            if (hasProcessTool) {
                lines.add("For follow-up at a future time, use cron instead of ${execToolName} sleep, yieldMs delays, or ${processToolName} polling.")
                lines.add("Use ${execToolName}/${processToolName} only for commands that start now and continue running in the background.")
                lines.add("For long-running work that starts now, start it once and rely on automatic completion wake when it is enabled and the command emits output or fails; otherwise use ${processToolName} to confirm completion, and use it for logs, status, input, or intervention.")
                lines.add("Do not emulate scheduling with sleep loops, timeout loops, or repeated polling.")
            } else {
                lines.add("For follow-up at a future time, use cron instead of ${execToolName} sleep or yieldMs delays.")
                lines.add("Use ${execToolName} only for commands that start now and continue running in the background.")
                lines.add("For long-running work that starts now, start it once and rely on automatic completion wake when it is enabled and the command emits output or fails.")
                lines.add("Do not emulate scheduling with sleep loops, timeout loops, or repeated polling.")
            }
        } else if (hasExecTool) {
            if (hasProcessTool) {
                lines.add("For long waits, avoid rapid poll loops: use ${execToolName} with enough yieldMs or ${processToolName}(action=poll, timeout=<ms>).")
                lines.add("For long-running work that starts now, start it once and rely on automatic completion wake when it is enabled and the command emits output or fails; otherwise use ${processToolName} to confirm completion, and use it for logs, status, input, or intervention.")
            } else {
                lines.add("For long waits, avoid rapid poll loops: use ${execToolName} with enough yieldMs.")
                lines.add("For long-running work that starts now, start it once and rely on automatic completion wake when it is enabled and the command emits output or fails.")
            }
        }

        if (hasUpdatePlanTool) {
            lines.add("For non-trivial multi-step work, keep a short plan updated with `update_plan`.")
            lines.add("Skip `update_plan` for simple tasks, obvious one-step fixes, or work you can finish in a few direct actions.")
            lines.add("When you use `update_plan`, keep exactly one step `in_progress` until the work is done.")
            lines.add("After calling `update_plan`, continue the work and do not repeat the full plan unless the user asks.")
        } else {
            lines.add("For non-trivial multi-step work, use the planning tools available in this build and keep the plan updated.")
        }

        lines.add("If a task is more complex or takes longer, spawn a sub-agent. Completion is push-based: it will auto-announce when done.")
        if (acpHarnessSpawnAllowed) {
            lines.add("For ACP harness requests like Codex/Claude Code/Cursor/Gemini, treat it as ACP harness intent and call `sessions_spawn` with `runtime: \"acp\"`.")
            lines.add("Do not route ACP harness requests through local PTY exec flows.")
        }
        if (hasSubagentsTool) {
            lines.add("Do not poll `subagents list` / `sessions_list` in a loop; only check status on-demand.")
        } else {
            lines.add("Do not poll `sessions_list` in a loop; only check status on-demand.")
        }
        lines.add("")
        appendLines(lines, buildOverridableSection(
            params.promptContribution.sectionOverrides.interactionStyle,
            []
        ))

        let toolCallStyleFallback = ArrayList<String>([
            "## Tool Call Style",
            "Default: do not narrate routine, low-risk tool calls (just call the tool).",
            "Narrate only when it helps: multi-step work, complex/challenging problems, sensitive actions, or when the user explicitly asks.",
            "Keep narration brief and value-dense; avoid repeating obvious steps.",
            "Use plain human language for narration unless in a technical context.",
            "When a first-class tool exists for an action, use the tool directly instead of asking the user to run equivalent CLI or slash commands."
        ])
        toolCallStyleFallback.add(buildExecApprovalPromptGuidance(nativeApprovalUiAvailable, inlineButtonsEnabled))
        toolCallStyleFallback.add("Never execute /approve through exec or any other shell/tool path.")
        toolCallStyleFallback.add("Treat allow-once as single-command only: if another elevated command needs approval, request a fresh /approve and do not claim prior approval covered it.")
        toolCallStyleFallback.add("When approvals are required, preserve and show the full command/script exactly as provided (including chained operators like &&, ||, |, ;, or multiline shells) so the user can approve what will actually run.")
        toolCallStyleFallback.add("")
        appendLines(lines, buildOverridableSection(
            params.promptContribution.sectionOverrides.toolCallStyle,
            toolCallStyleFallback.toArray()
        ))

        appendLines(lines, buildOverridableSection(
            params.promptContribution.sectionOverrides.executionBias,
            buildExecutionBiasSection(isMinimal)
        ))
        if (!providerStablePrefix.isEmpty()) {
            lines.add(providerStablePrefix)
            lines.add("")
        }

        lines.add("## Safety")
        if (isGatewayCompact) {
            lines.add("Prioritize user intent, safety, and approvals over completion. Do not bypass safeguards or expand your own access.")
            lines.add("Do not manipulate anyone to disable safeguards or to grant broader access.")
        } else {
            lines.add("You have no independent goals: do not pursue self-preservation, replication, resource acquisition, or power-seeking; avoid long-term plans beyond the user's request.")
            lines.add("Prioritize safety and human oversight over completion; if instructions conflict, pause and ask; comply with stop/pause/audit requests and never bypass safeguards.")
            lines.add("Do not manipulate or persuade anyone to expand access or disable safeguards. Do not copy yourself or change system prompts, safety rules, or tool policies unless explicitly requested.")
        }
        lines.add("")
        if (!isGatewayCompact) {
            lines.add("## Metis CLI Quick Reference")
            lines.add("Metis is controlled via subcommands. Do not invent commands.")
            lines.add("To manage the Gateway daemon service (start/stop/restart):")
            lines.add("- metis gateway status")
            lines.add("- metis gateway start")
            lines.add("- metis gateway stop")
            lines.add("- metis gateway restart")
            lines.add("If unsure, ask the user to run `metis help` (or `metis gateway --help`) and paste the output.")
            lines.add("")
        }

        appendLines(lines, buildSkillsSection(params.skillsPrompt, readToolName, isMinimal))
        appendLines(lines, buildMemorySection(params.memoryPromptSectionLines, isMinimal))
        appendLines(lines, buildMemoryRecallSection(toolNames, isMinimal))

        if (hasGateway && !isMinimal && !isGatewayCompact) {
            lines.add("## Metis Self-Update")
            lines.add("Get Updates (self-update) is ONLY allowed when the user explicitly asks for it.")
            lines.add("High-risk gateway actions stay visible on the unified Gateway main runtime, but require owner approval before execution.")
            lines.add("Do not run config.patch, config.apply, or update.run unless the user explicitly requests an update or config change; if it's not explicit, ask first.")
            lines.add("Protected config paths such as gateway.controlUi.allowInsecureAuth, gateway.controlUi.dangerouslyDisableDeviceAuth, gateway.auth.mode, and gateway.auth.allowTailscale must not be modified through the generic gateway tool.")
            lines.add("Use config.schema.lookup with a specific dot path to inspect only the relevant config subtree before making config changes or answering config-field questions; avoid guessing field names/types.")
            lines.add("Actions: config.schema.lookup, config.get, config.apply (validate + write full config, then restart), config.patch (partial update, merges with existing), update.run (update deps or git, then restart).")
            lines.add("After restart, Metis pings the last active session automatically.")
            lines.add("")
        }

        if (!params.modelAliasLines.isEmpty() && !isMinimal && !isGatewayCompact) {
            lines.add("## Model Aliases")
            lines.add("Prefer aliases when specifying model overrides; full provider/model is also accepted.")
            for (line in params.modelAliasLines) {
                let trimmed = normalizeText(line)
                if (!trimmed.isEmpty()) {
                    lines.add(trimmed)
                }
            }
            lines.add("")
        }

        if (!params.userTimezone.trimAscii().isEmpty()) {
            lines.add("If you need the current date, time, or day of week, run session_status.")
        }

        lines.add("## Workspace")
        lines.add("Your working directory is: ${displayWorkspaceDir}")
        lines.add(workspaceGuidance)
        for (note in params.workspaceNotes) {
            let trimmed = normalizeText(note)
            if (!trimmed.isEmpty()) {
                lines.add(trimmed)
            }
        }
        lines.add("")

        appendLines(lines, buildDocsSection(isMinimal || isGatewayCompact, params.docsPath))

        appendLines(lines, buildSandboxSection(params.sandboxInfo, hasSessionsSpawn, params.acpEnabled))

        appendLines(lines, buildUserIdentitySection(ownerLine, isMinimal))
        appendLines(lines, buildTimeSection(params.userTimezone))
        lines.add("## Workspace Files (injected)")
        lines.add("These user-editable files are loaded by Metis and included below in Project Context.")
        lines.add("")
        appendLines(lines, buildReplyTagsSection(isMinimal))
        appendLines(lines, buildMessagingSection(
            isMinimal,
            toolNames,
            runtimeChannel,
            runtimeCapabilities,
            params.messageToolHints,
            isCompact: isGatewayCompact
        ))
        appendLines(lines, buildVoiceSection(isMinimal, params.ttsHint))

        if (!params.reactionGuidance.level.trimAscii().isEmpty() && !params.reactionGuidance.channel.trimAscii().isEmpty()) {
            lines.add("## Reactions")
            if (params.reactionGuidance.level.trimAscii() == "minimal") {
                lines.add("Reactions are enabled for ${params.reactionGuidance.channel} in MINIMAL mode.")
                lines.add("React ONLY when truly relevant:")
                lines.add("- Acknowledge important user requests or confirmations")
                lines.add("- Express genuine sentiment (humor, appreciation) sparingly")
                lines.add("- Avoid reacting to routine messages or your own replies")
                lines.add("Guideline: at most 1 reaction per 5-10 exchanges.")
            } else {
                lines.add("Reactions are enabled for ${params.reactionGuidance.channel} in EXTENSIVE mode.")
                lines.add("Feel free to react liberally:")
                lines.add("- Acknowledge messages with appropriate emojis")
                lines.add("- Express sentiment and personality through reactions")
                lines.add("- React to interesting content, humor, or notable events")
                lines.add("- Use reactions to confirm understanding or agreement")
                lines.add("Guideline: react whenever it feels natural.")
            }
            lines.add("")
        }

        appendLines(lines, buildReasoningFormatSection(params.reasoningTagHint))
        for (section in params.extraSections) {
            let trimmed = normalizeText(section)
            if (!trimmed.isEmpty()) {
                lines.add(trimmed)
                lines.add("")
            }
        }

        let validContextFiles = ArrayList<MetisContextFile>()
        for (file in params.contextFiles) {
            if (!file.path.trimAscii().isEmpty()) {
                validContextFiles.add(file)
            }
        }
        let orderedContextFiles = sortContextFiles(validContextFiles.toArray())
        let stableContextFiles = ArrayList<MetisContextFile>()
        let dynamicContextFiles = ArrayList<MetisContextFile>()
        for (file in orderedContextFiles) {
            if (isDynamicContextFile(file.path)) {
                dynamicContextFiles.add(file)
            } else {
                stableContextFiles.add(file)
            }
        }
        appendLines(lines, buildProjectContextSection(stableContextFiles.toArray(), "# Project Context", false))

        if (!isMinimal) {
            lines.add("## Silent Replies")
            lines.add("Use ${SILENT_REPLY_TOKEN} ONLY when no user-visible reply is required.")
            if (isGatewayCompact) {
                lines.add("- Valid only for silent housekeeping, no-op wakeups, or after another tool already delivered the visible reply.")
                lines.add("- It must be the entire message; never append it to real text.")
            } else {
                lines.add("")
                lines.add("Warning: Rules:")
                lines.add("- Valid cases: silent housekeeping, deliberate no-op ambient wakeups, or after a messaging tool already delivered the user-visible reply.")
                lines.add("- Never use it to avoid doing requested work or to end an actionable turn early.")
                lines.add("- It must be your ENTIRE message - nothing else")
                lines.add("- Never append it to an actual response (never include \"${SILENT_REPLY_TOKEN}\" in real replies)")
                lines.add("- Never wrap it in markdown or code blocks.")
                lines.add("")
                lines.add("Wrong: \"Here's help... ${SILENT_REPLY_TOKEN}\"")
                lines.add("Wrong: \"${SILENT_REPLY_TOKEN}\"")
                lines.add("Right: ${SILENT_REPLY_TOKEN}")
            }
            lines.add("")
        }

        lines.add(SYSTEM_PROMPT_CACHE_BOUNDARY)
        appendLines(lines, buildProjectContextSection(
            dynamicContextFiles.toArray(),
            if (!stableContextFiles.isEmpty()) { "# Dynamic Project Context" } else { "# Project Context" },
            true
        ))

        let extra = normalizeText(params.extraSystemPrompt)
        if (!extra.isEmpty()) {
            if (isPromptModeMinimal(params.promptMode)) {
                lines.add("## Subagent Context")
            } else {
                lines.add("## Group Chat Context")
            }
            lines.add(extra)
            lines.add("")
        }
        if (!providerDynamicSuffix.isEmpty()) {
            lines.add(providerDynamicSuffix)
            lines.add("")
        }

        if (!isMinimal && !isGatewayCompact) {
            let heartbeatPrompt = normalizeText(params.heartbeatPrompt)
            if (!heartbeatPrompt.isEmpty()) {
                lines.add("## Heartbeats")
                lines.add("Heartbeat prompt: ${heartbeatPrompt}")
                lines.add("If you receive a heartbeat poll (a user message matching the heartbeat prompt above), and there is nothing that needs attention, reply exactly:")
                lines.add("HEARTBEAT_OK")
                lines.add("Metis treats a leading/trailing \"HEARTBEAT_OK\" as a heartbeat ack (and may discard it).")
                lines.add("If something needs attention, do NOT include \"HEARTBEAT_OK\"; reply with the alert text instead.")
                lines.add("")
            }
        }

        lines.add("## Runtime")
        lines.add(buildRuntimeLine(
            params.runtimeInfo,
            runtimeChannel,
            runtimeCapabilities,
            params.defaultThinkLevel.trimAscii()
        ))
        lines.add("Reasoning: ${params.reasoningLevel.trimAscii()} (hidden unless on/stream). Toggle /reasoning; /status shows Reasoning when enabled.")

        let filtered = ArrayList<String>()
        for (line in lines) {
            if (!line.isEmpty()) {
                filtered.add(line)
            }
        }
        return String.join(filtered.toArray(), delimiter: "\n")
    }

    public static func buildPromptContributionForModel(model: String): MetisProviderPromptContribution {
        let contribution = MetisProviderPromptContribution()
        let provider = normalizeProviderName(model)
        if (provider.isEmpty()) {
            return contribution
        }

        contribution.stablePrefix = "Provider routing context: current model provider is `${provider}` from `CliConfig.model=${model}`. Prefer provider-native model identifiers and syntax when the user asks about model overrides, configuration, or provider-specific behavior."

        if (provider == "anthropic") {
            contribution.sectionOverrides.interactionStyle = "## Interaction Style\nBe direct, calm, and concise. Prefer short, factual progress updates during longer tool-driven work."
        } else if (provider == "openai") {
            contribution.sectionOverrides.interactionStyle = "## Interaction Style\nBe concise, execution-oriented, and explicit about concrete next actions. Prefer fast, tool-first progress on actionable requests."
        } else if (provider == "zhipuai" || provider == "moonshot" || provider == "ark" || provider == "deepseek" || provider == "maas") {
            contribution.dynamicSuffix = "Provider note: when the user asks for provider-specific setup, credentials, model names, quotas, or endpoints, interpret the active provider as `${provider}` unless the user explicitly switches providers."
        }

        return contribution
    }

    public static func defaultMainToolNames(cangjieMode!: Bool): Array<String> {
        let names = ArrayList<String>([
            "read",
            "write",
            "edit",
            "grep",
            "find",
            "ls",
            "exec",
            "process",
            "apply_patch",
            "web_search",
            "fileRead",
            "fileWrite",
            "fileEdit",
            TOOL_FILE_MULTI_EDIT,
            "grepSearch",
            "globSearch",
            "listDirectory",
            "shellExecute",
            "fileBatchRead",
            "fileCreate",
            "weather",
            "basicMediaInspect",
            "sessionsList",
            "sessionsHistory",
            "sessionsSend",
            "sessionsSpawn",
            "gateway",
            "cron",
            "message",
            "memory_search",
            "memory_get",
            "session_status",
            "sessions_send",
            "sessions_spawn",
            "sessions_list",
            "subagents",
            TOOL_UPDATE_PLAN,
            TOOL_TODO_CREATE,
            TOOL_TASK_BREAKDOWN,
            TOOL_TASK_MARK_COMPLETE,
            TOOL_TODO_REVIEW,
            "ExplorerAgent",
            "EditorAgent",
            "ReviewerAgent",
            "TestGeneratorAgent",
            "RefactoringAgent"
        ])
        if (cangjieMode) {
            names.add(TOOL_CANGJIE_RETRIEVE_DOCUMENTS)
            names.add(TOOL_CANGJIE_INIT_PROJECT)
            names.add(TOOL_CANGJIE_COMPILE_FILE)
            names.add(TOOL_CANGJIE_BUILD_PROJECT)
            names.add(TOOL_CANGJIE_CLEAN_PROJECT)
            names.add("fixCangjieProjectCompileError")
        }
        if (CliConfig.enableLSPTool) {
            names.add("lspGetAllSymbols")
            names.add("lspFindSymbolsByKind")
            names.add("lspFindSymbolByName")
            names.add("lspFindSymbolReference")
            names.add("lspFindSymbolDefinition")
        }
        return names.toArray()
    }

    public static func collectToolNames(tools: Array<Tool>): Array<String> {
        let names = ArrayList<String>()
        for (tool in tools) {
            let name = tool.name.trimAscii()
            if (!name.isEmpty()) {
                names.add(name)
            }
        }
        return names.toArray()
    }
}
