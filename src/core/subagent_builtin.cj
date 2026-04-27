package metis.core

public func gatewaySubagentNormalizeBuiltinAgentId(agentId: String): String {
    let normalized = agentId.trimAscii().toAsciiLower().replace("-", "_")
    if (normalized.isEmpty()) {
        return "explorer"
    }
    match (normalized) {
        case "explorer" | "exploreragent" | "explorer_agent" => "explorer"
        case "editor" | "edit" | "editoragent" | "editor_agent" => "editor"
        case "reviewer" | "review" | "revieweragent" | "reviewer_agent" => "reviewer"
        case "test_generator" | "testgenerator" | "testgeneratoragent" | "test_generator_agent" => "test_generator"
        case "refactoring" | "refactor" | "refactoringagent" | "refactoring_agent" => "refactoring"
        case "planner" | "planneragent" | "planner_agent" => "planner"
        case _ => normalized
    }
}

public func gatewaySubagentIsBuiltinAgent(agentId: String): Bool {
    match (gatewaySubagentNormalizeBuiltinAgentId(agentId)) {
        case "explorer" | "editor" | "reviewer" | "test_generator" | "refactoring" | "planner" => true
        case _ => false
    }
}

public func gatewaySubagentBuiltinAgentIsWriteCapable(agentId: String): Bool {
    match (gatewaySubagentNormalizeBuiltinAgentId(agentId)) {
        case "editor" | "test_generator" | "refactoring" => true
        case _ => false
    }
}

public func gatewaySubagentAgentLooksWriteCapable(agentId: String): Bool {
    let normalized = gatewaySubagentNormalizeBuiltinAgentId(agentId)
    if (gatewaySubagentBuiltinAgentIsWriteCapable(normalized)) {
        return true
    }
    if (normalized.isEmpty()) {
        return false
    }
    normalized.contains("write") ||
        normalized.contains("fix") ||
        normalized.contains("patch") ||
        normalized.contains("implement") ||
        normalized.contains("coder")
}

public func gatewaySubagentBuiltinRolePrompt(agentId: String): String {
    match (gatewaySubagentNormalizeBuiltinAgentId(agentId)) {
        case "editor" => "Subagent role: editor. Make precise code changes and focus on concrete edits."
        case "reviewer" => "Subagent role: reviewer. Focus on bugs, risks, regressions, and validation."
        case "test_generator" => "Subagent role: test_generator. Focus on creating or improving tests."
        case "refactoring" => "Subagent role: refactoring. Focus on structural cleanup without changing behavior."
        case "planner" => "Subagent role: planner. Focus on breaking the task into a concrete plan."
        case _ => "Subagent role: explorer. Focus on exploring the codebase and reporting findings."
    }
}

public func gatewaySubagentBuildBuiltinPrompt(
    task: String,
    cwd: String,
    sessionKey: String,
    agentId: String
): String {
    let effectiveCwd = cwd.trimAscii()
    "${gatewaySubagentBuiltinRolePrompt(agentId)}\nProject path: ${effectiveCwd}\nSession key: ${sessionKey.trimAscii()}\n\nTask:\n${task.trimAscii()}"
}
