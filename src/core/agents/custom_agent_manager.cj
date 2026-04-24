package metis.core.agents

import magic.core.agent.Agent
import magic.log.LogUtils

import metis.core.config.CliConfig
import metis.io.{PrintUtils, CompletionListUtils, WithColor, Theme}

import std.collection.HashMap
import std.fs.exists

protected class CustomAgentManager {
    private var agents = HashMap<String, CustomAgent>()

    protected init() {
        this.loadAgents()
    }

    /**
     * Load all agent configurations from the agent directories
     */
    private func loadAgents(): Unit {
        for (agentDir in CliConfig.subagentDirs) {
            if (exists(agentDir)) {  
                if (!exists(agentDir.join("AGENT.md"))) {
                    LogUtils.error("AGENT.md not found in Agent directory, skipped: ${agentDir}")
                    continue
                }
                let agent = CustomAgent(agentDir)
                agents.add(agent.name, agent)
                CompletionListUtils.registerCompletionItem("@${agent.name}")
                LogUtils.info("Loaded custom agent: @${agent.name}")
            } else {
                LogUtils.error("Agent directory not found: ${agentDir}")
            }
        }
    }

    protected func getAgent(name: String): Option<Agent> {
        if (let Some(ag) <- this.agents.get(name)) {
            return ag
        }
        return None
    }

    /**
     * List all available custom agents
     */
    protected func listAgents(): Unit {
        if (agents.isEmpty()) {
            PrintUtils.printLine("No custom agents found")
            return
        }

        PrintUtils.printLine("🤖 Available custom agents\n".withColor(Theme.current.primary))
        for ((name, agent) in agents) {
            PrintUtils.printLine("  • ${name.withColor(Theme.current.highlight)} - ${agent.description}")
        }
        PrintUtils.printLine("")
        PrintUtils.printLine("Usage: @<agent-name> [arguments] <question in natural language>\n")
    }
}