package metis.core.model

import metis.core.config.CliConfig

import std.collection.HashMap

protected class ModelTokenLimits {
    private static let FALLBACK_INPUT_LIMIT: Int64 = 128 * 1024
    private static let FALLBACK_OUTPUT_LIMIT: Int64 = 32 * 1024

    /**
     * The maximum number of input tokens that can be used in a single request.
     */
    private static let INPUT_LIMITS = HashMap<String, Int64>([
        // Ark (ByteDance) models
        ("ark:kimi-k2-250711", 128 * 1024),
        ("ark:kimi-k2-250905", 256 * 1024),
        ("ark:doubao-seed-1-6-flash", 256 * 1024),
        ("ark:doubao-1-5-pro-32k", 32 * 1024),
        ("ark:deepseek-v3-1", 128 * 1024),
        ("ark:deepseek-v3", 128 * 1024),
        ("ark:deepseek-r1", 128 * 1024),
        ("ark:doubao-seed-code", 224 * 1024),

        // Moonshot models
        ("moonshot:kimi-k2", 256 * 1024),

        // Zhipu AI models
        ("zhipuai:glm-4.5", 128 * 1024),
        ("zhipuai:glm-4.5-air", 128 * 1024),
        ("zhipuai:glm-4-plus", 128 * 1024),
        ("zai:glm-4.5", 128 * 1024),
        ("zai:glm-4.5-air", 128 * 1024),
        ("zai:glm-4-plus", 128 * 1024),

        // Qwen models
        ("dashscope:qwen3-max", 256 * 1024),
        ("dashscope:qwen-plus", 128 * 1024),
        ("dashscope:qwen-flash", 1024 * 1024),
        ("dashscope:qwen3-coder-plus", 1024 * 1024),
        ("dashscope:qwen3-coder-flash", 1024 * 1024),
        ("dashscope:qwen3.5-plus", 128 * 1024),
        ("qwen:qwen3.5-plus", 128 * 1024),
        ("qwen:qwen-plus", 128 * 1024),
        ("qwen:qwen-flash", 1024 * 1024),

        // DeepSeek models
        ("deepseek:deepseek-chat", 128 * 1024),
        ("deepseek:deepseek-reasoner", 128 * 1024),

        // OpenAI GPT models
        ("openai:gpt-4", 128 * 1024),
        ("openai:gpt-4-turbo", 128 * 1024),
        ("openai:gpt-4o", 128 * 1024),
        ("openai:gpt-3.5-turbo", 16 * 1024),

        // Google Gemini models
        ("google:gemini-1.5-flash", 1024 * 1024),
        ("google:gemini-2.5-pro-preview", 1024 * 1024),
        ("google:gemini-2.5-pro", 1024 * 1024),
        ("google:gemini-2.5-flash-preview", 1024 * 1024),
        ("google:gemini-2.5-flash", 1024 * 1024),
        ("google:gemini-2.5-flash-lite", 1024 * 1024),
        ("google:gemini-2.0-flash", 1024 * 1024),

        // OpenRouter models
        ("openrouter:qwen/qwen3-coder-30b-a3b-instruct", 32 * 1024)
    ])

    private static let INPUT_PROVIDER_DEFAULTS = HashMap<String, Int64>([
        ("deepseek:", 128 * 1024),
        ("openai:", 128 * 1024),
        ("openrouter:", 128 * 1024),
        ("dashscope:", 128 * 1024),
        ("qwen:", 128 * 1024),
        ("google:", 1024 * 1024),
        ("ark:", 128 * 1024),
        ("moonshot:", 128 * 1024),
        ("zhipuai:", 128 * 1024),
        ("zai:", 128 * 1024)
    ])

    public static func getInputLimit(model: String): Int64 {
        for ((key, value) in INPUT_LIMITS) {
            if (model.startsWith(key)) {
                return value
            }
        }
        for ((key, value) in INPUT_PROVIDER_DEFAULTS) {
            if (model.startsWith(key)) {
                return value
            }
        }
        if (CliConfig.defaultModelInputLimit > 0) {
            return CliConfig.defaultModelInputLimit
        }
        return FALLBACK_INPUT_LIMIT
    }

    /**
     * The maximum number of output tokens that can be used in a single request.
     */
    private static let OUTPUT_LIMITS = HashMap<String, Int64>([
        // Ark (ByteDance) models
        ("ark:kimi-k2-250711", 32 * 1024),
        ("ark:kimi-k2-250905", 32 * 1024),
        ("ark:doubao-seed-1-6-flash", 32 * 1024),
        ("ark:doubao-1-5-pro-32k", 8 * 1024),
        ("ark:doubao-seed-code-preview", 32 * 1024),
        ("ark:deepseek-v3-1", 32 * 1024),
        ("ark:deepseek-v3", 32 * 1024),
        ("ark:deepseek-r1", 32 * 1024),

        // Moonshot models
        ("moonshot:kimi-k2", 32* 1024),

        // Zhipu AI models
        ("zhipuai:glm-4.5", 32 * 1024),
        ("zhipuai:glm-4.5-air", 32 * 1024),
        ("zhipuai:glm-4-plus", 32 * 1024),
        ("zai:glm-4.5", 32 * 1024),
        ("zai:glm-4.5-air", 32 * 1024),
        ("zai:glm-4-plus", 32 * 1024),

        // Qwen models
        ("dashscope:qwen3-max-preview", 32 * 1024),
        ("dashscope:qwen-plus", 32 * 1024),
        ("dashscope:qwen-flash", 32 * 1024),
        ("dashscope:qwen3-coder-plus", 32 * 1024),
        ("dashscope:qwen3-coder-flash", 32 * 1024),
        ("dashscope:qwen3.5-plus", 32 * 1024),
        ("qwen:qwen3.5-plus", 32 * 1024),
        ("qwen:qwen-plus", 32 * 1024),
        ("qwen:qwen-flash", 32 * 1024),

        // DeepSeek models
        ("deepseek:deepseek-chat", 8 * 1024),
        ("deepseek:deepseek-reasoner", 32 * 1024),

        // OpenRouter models
        ("openrouter:qwen/qwen3-coder-30b-a3b-instruct", 8 * 1024)
    ])

    private static let OUTPUT_PROVIDER_DEFAULTS = HashMap<String, Int64>([
        ("deepseek:", 32 * 1024),
        ("openai:", 32 * 1024),
        ("openrouter:", 32 * 1024),
        ("dashscope:", 32 * 1024),
        ("qwen:", 32 * 1024),
        ("google:", 32 * 1024),
        ("ark:", 32 * 1024),
        ("moonshot:", 32 * 1024),
        ("zhipuai:", 32 * 1024),
        ("zai:", 32 * 1024)
    ])

    public static func getOutputLimit(model: String): Int64 {
        for ((key, value) in OUTPUT_LIMITS) {
            if (model.startsWith(key)) {
                return value
            }
        }
        for ((key, value) in OUTPUT_PROVIDER_DEFAULTS) {
            if (model.startsWith(key)) {
                return value
            }
        }
        if (CliConfig.defaultModelOutputLimit > 0) {
            return CliConfig.defaultModelOutputLimit
        }
        return FALLBACK_OUTPUT_LIMIT
    }
}
