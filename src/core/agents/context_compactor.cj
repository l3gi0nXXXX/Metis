package metis.core.agents

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import magic.core.message.ConversationCompactor
import magic.core.message.{Message, MessageRole, MessageList}
import magic.log.LogUtils
import magic.core.tokenizer.Tokenizer
import magic.model.ModelManager

import metis.core.config.CliConfig
import metis.core.model.CliModelManager
import metis.core.model.ModelTokenLimits
import metis.core.agents.common.*
import metis.core.memory.buildMemoryPromptSectionForToolNames
import metis.core.prompting.{MetisBootstrapBudget, MetisSystemPromptParams, MetisSystemPromptBuilder, MetisWorkspaceBootstrap}
import metis.core.skills.SkillsPrompt
import metis.utils.buildTokenizer

private let COMPACT_CONTEXT_PROMPT = """
You are the component that summarizes internal chat history into a given structure.

When the conversation history grows too large, you will be invoked to distill the entire history into a concise, structured XML snapshot. This snapshot is CRITICAL, as it will become the agent's *only* memory of the past. The agent will resume its work based solely on this snapshot. All crucial details, plans, errors, and user directives MUST be preserved.

First, you will think through the entire history in a private <scratchpad>. Review the user's overall goal, the agent's actions, tool outputs, file modifications, and any unresolved questions. Identify every piece of information that is essential for future actions.

After your reasoning is complete, generate the final <state_snapshot> XML object. Be incredibly dense with information. Omit any irrelevant conversational filler.

The structure MUST be as follows:

<state_snapshot>
    <overall_goal>
        <!-- A single, concise sentence describing the user's high-level objective. -->
        <!-- Example: "Refactor the authentication service to use a new JWT library." -->
    </overall_goal>

    <key_knowledge>
        <!-- Crucial facts, conventions, and constraints the agent must remember based on the conversation history and interaction with the user. Use bullet points. -->
        <!-- Example:
         - Build Command: `npm run build`
         - Testing: Tests are run with `npm test`. Test files must end in `.test.ts`.
         - API Endpoint: The primary API endpoint is `https://api.example.com/v2`.
        -->
    </key_knowledge>

    <file_system_state>
        <!-- List files that have been created, read, modified, or deleted. Note their status and critical learnings. -->
        <!-- Example:
         - CWD: `/home/user/project/src`
         - READ: `package.json` - Confirmed 'axios' is a dependency.
         - MODIFIED: `services/auth.ts` - Replaced 'jsonwebtoken' with 'jose'.
         - CREATED: `tests/new-feature.test.ts` - Initial test structure for the new feature.
        -->
    </file_system_state>

    <recent_actions>
        <!-- A summary of the last few significant agent actions and their outcomes. Focus on facts. -->
        <!-- Example:
         - Ran `grep 'old_function'` which returned 3 results in 2 files.
         - Ran `npm run test`, which failed due to a snapshot mismatch in `UserProfile.test.ts`.
         - Ran `ls -F static/` and discovered image assets are stored as `.webp`.
        -->
    </recent_actions>

    <current_plan>
        <!-- The agent's step-by-step plan. Mark completed steps. -->
        <!-- Example:
         1. [DONE] Identify all files using the deprecated 'UserAPI'.
         2. [IN PROGRESS] Refactor `src/components/UserProfile.tsx` to use the new 'ProfileAPI'.
         3. [TODO] Refactor the remaining files.
         4. [TODO] Update tests to reflect the API change.
        -->
    </current_plan>
</state_snapshot>
"""

@agent[
    model: CliModelManager.fastModel ?? CliModelManager.model,
    executor: "naive"
]
private class CompactContextAgent {
    @prompt(
        """
        ${COMPACT_CONTEXT_PROMPT}
        """
    )
}
// If the total token of conversation is less than 70% of the model context token limit, then no need to compact
const COMPACT_TOKEN_THRESHOLD = 0.7
// The last 30% of the conversation will be preserved during compact
const COMPACT_PRESERVE_THRESHOLD = 0.3

// This is a temporary interface that will be integrated into CangjieMagic later.
public interface CliConversationCompactor <: ConversationCompactor {
    func calculateCompactIndex(conversation: Conversation): Option<Int64>
}

public class Compactor <: CliConversationCompactor {

    private let tokenizer: Tokenizer

    protected init() {
        this.tokenizer = buildTokenizer()
    }

    override public func compact(conversation: Conversation): String {
        var toBeCompactedContent = StringBuilder()
        for(i in 0..conversation.size){
            toBeCompactedContent.append(conversation[i].toString())
        }
        let agent = CompactContextAgent()
        return agent.chat(toBeCompactedContent.toString())
    }

    public func calculateCompactIndex(conversation: Conversation): Option<Int64> {
        let (totalTokens, roundTokens) = this.calculateToken(conversation)
        let modelContextLimit = ModelTokenLimits.getInputLimit(
            (CliModelManager.lastAvailableModel ?? CliModelManager.model).fullName
        )
        // If the total token of conversation is less than 70% of the model context token limit, then no need to compact
        let threshold = Int64(Float64(modelContextLimit) * COMPACT_TOKEN_THRESHOLD)
        if (totalTokens <= threshold) {
            LogUtils.debug("Calculate compact index: Not to compact")
            return None
        }
        // Calculate the number of chat rounds to be compacted based on the token count
        var compactTokens = totalTokens - Int64(Float64(modelContextLimit) * COMPACT_PRESERVE_THRESHOLD)
        var index = 0
        for (i in 0..roundTokens.size) {
            if (compactTokens <= 0) {
                break
            }
            compactTokens -= roundTokens[i]
            index += 1
        }
        LogUtils.debug("Calculate compact index: ${index}")
        return index
    }

    private func calculateToken(conversation: Conversation): (Int64, ArrayList<Int64>) {
        let cangjieMode = CliConfig.language.toAsciiLower() == "cangjie"
        let params = MetisSystemPromptParams()
        params.workspaceDir = CliConfig.cwd.toString()
        params.toolNames = MetisSystemPromptBuilder.defaultMainToolNames(cangjieMode: cangjieMode)
        params.runtimeInfo.model = CliConfig.model
        params.skillsPrompt = SkillsPrompt.buildAvailableSkillsMetadataForPrompt()
        params.memoryPromptSectionLines = buildMemoryPromptSectionForToolNames(params.toolNames)
        let bootstrap = MetisWorkspaceBootstrap.resolveContextFilesDetailed(CliConfig.cwd)
        params.contextFiles = bootstrap.files
        params.promptContribution = MetisSystemPromptBuilder.buildPromptContributionForModel(CliConfig.model)
        let systemPrompt = MetisSystemPromptBuilder.build(params, cangjieMode: cangjieMode)
        LogUtils.debug("ContextCompactor bootstrap: ${MetisBootstrapBudget.describe(bootstrap)}")
        let systemPromptTokens = this.tokenizer.countToken(systemPrompt)
        var totalTokens: Int64 = systemPromptTokens
        let roundTokens = ArrayList<Int64>()
        // Calculate the total token of the current conversation and token consumption for each ChatRound
        for (chatRound in conversation) {
            let tokens = this.tokenizer.countToken(chatRound.toString())
            roundTokens.add(tokens)
            totalTokens += tokens
        }
        return (totalTokens, roundTokens)
    }
}
