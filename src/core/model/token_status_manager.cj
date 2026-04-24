package metis.core.model

import magic.core.model.ChatUsage

import metis.io.{PrintUtils, Theme, wrapBox, WithColor}
import metis.core.config.CliConfig

/**
 * Manage token status
 */
protected class TokenStatusManager {
    private var promptTokens: Int64 = 0
    private var completionTokens: Int64 = 0
    private var totalTokens: Int64 = 0
    private var lastPromptTokens: Int64 = 0  // Track the last request's prompt tokens

    protected func addUsage(usage: ChatUsage): Unit {
        this.promptTokens += usage.promptTokens
        this.completionTokens += usage.completionTokens
        this.totalTokens += usage.totalTokens
        this.lastPromptTokens = usage.promptTokens  // Store the latest request's prompt tokens
    }

    protected prop contextUsagePercentage: Int64 {
        get() {
            try {
                let model = CliModelManager.lastAvailableModel ?? CliModelManager.model
                // Get the context limit for the model
                let tokenLimit = ModelTokenLimits.getInputLimit(model.fullName)
                // The last prompt length is the current context size
                let currentTokens = this.lastPromptTokens
                // Now, compute the percentage of used context
                if (tokenLimit > 0 && currentTokens > 0) {
                    (currentTokens * 100) / tokenLimit
                } else {
                    0
                }
            } catch (e: Exception) {
                // If model initialization fails (e.g., missing API KEY), return 0
                return 0
            }
        }
    }

    protected func printStatus(): Unit {
        let message = wrapBox(
            " 📊 Token Status".withColor(Theme.PRIMARY),
            lines: [
                " ∙ Input:  ${promptTokens}",
                " ∙ Output: ${completionTokens}",
                " ∙ Total:  ${totalTokens}",
                " ∙ Context Usage: ${contextUsagePercentage}%"
            ]
        )
        PrintUtils.printLine(message)
    }
}