package metis.core.config

import std.collection.ArrayList

public struct CliModelAuthChoiceGroupDescriptor {
    public CliModelAuthChoiceGroupDescriptor(
        public let groupId: String,
        public let title: String,
        public let description: String
    ) {}
}

public struct CliModelAuthChoiceDescriptor {
    public CliModelAuthChoiceDescriptor(
        public let choiceId: String,
        public let providerId: String,
        public let groupId: String,
        public let label: String,
        public let authMethod: String,
        public let description: String,
        public let defaultModelRef: String,
        public let baseUrl: String,
        public let docsUrl: String,
        public let highPriority: Bool
    ) {}
}

private let CLI_MODEL_AUTH_CHOICE_GROUPS = [
    CliModelAuthChoiceGroupDescriptor("domestic", "Domestic providers", "Providers commonly used in mainland China and adjacent domestic runtimes."),
    CliModelAuthChoiceGroupDescriptor("global", "Global providers", "Bundled international providers with direct API-key onboarding."),
    CliModelAuthChoiceGroupDescriptor("local", "Local / self-hosted", "Self-hosted or local model runners with explicit base URLs."),
    CliModelAuthChoiceGroupDescriptor("custom", "Custom / compatible", "Bring your own compatible endpoint and model naming.")
]

private let CLI_MODEL_AUTH_CHOICES = [
    CliModelAuthChoiceDescriptor("anthropic-api-key", "anthropic", "global", "Anthropic API key", "api-key", "Anthropic API key for direct Claude access.", "anthropic:claude-sonnet-4-6", "https://api.anthropic.com/v1", "https://console.anthropic.com/", true),
    CliModelAuthChoiceDescriptor("anthropic-claude-cli", "anthropic", "global", "Claude CLI + API key", "subscription", "Claude CLI subscription flow plus API-backed usage path.", "anthropic:claude-sonnet-4-6", "https://api.anthropic.com/v1", "https://console.anthropic.com/", true),
    CliModelAuthChoiceDescriptor("arcee-api-key", "arcee", "global", "Arcee AI API key", "api-key", "Arcee API key", "arcee:arcee-blitz", "https://conductor.arcee.ai/v1", "https://www.arcee.ai/", false),
    CliModelAuthChoiceDescriptor("byteplus-api-key", "byteplus", "domestic", "BytePlus API key", "api-key", "BytePlus ARK endpoint", "byteplus:ark-code-latest", "https://ark.cn-beijing.volces.com/api/coding/v3", "https://www.byteplus.com/", true),
    CliModelAuthChoiceDescriptor("chutes-api-key", "chutes", "global", "Chutes API key", "api-key", "Chutes hosted model API", "chutes:deepseek-r1", "https://api.chutes.ai/v1", "https://docs.metis.ai/providers/chutes", false),
    CliModelAuthChoiceDescriptor("cloudflare-ai-gateway-api-key", "cloudflare-ai-gateway", "global", "Cloudflare AI Gateway token", "api-key", "Cloudflare AI Gateway account token", "cloudflare-ai-gateway:claude-sonnet-4-5", "https://gateway.ai.cloudflare.com/v1", "https://developers.cloudflare.com/ai-gateway/", false),
    CliModelAuthChoiceDescriptor("copilot-proxy-local", "copilot-proxy", "global", "Copilot Proxy local bridge", "local-bridge", "Use local Copilot Proxy as the runtime bridge.", "copilot-proxy:gpt-5.4", "http://127.0.0.1:4141/v1", "https://docs.metis.ai/providers/github-copilot", false),
    CliModelAuthChoiceDescriptor("custom-api-key", "custom", "custom", "Custom API-compatible endpoint", "api-key", "Provide your own compatible API key and endpoint.", "custom:gpt-5.4-compatible", "", "", true),
    CliModelAuthChoiceDescriptor("deepseek-api-key", "deepseek", "domestic", "DeepSeek API key", "api-key", "DeepSeek direct API key", "deepseek:deepseek-chat", "https://api.deepseek.com/v1", "https://platform.deepseek.com/", true),
    CliModelAuthChoiceDescriptor("fireworks-api-key", "fireworks", "global", "Fireworks API key", "api-key", "Fireworks hosted inference API", "fireworks:accounts/fireworks/models/llama-v3p1-70b-instruct", "https://api.fireworks.ai/inference/v1", "https://docs.metis.ai/providers/fireworks", false),
    CliModelAuthChoiceDescriptor("gemini-cli-oauth", "gemini-cli-oauth", "global", "Gemini CLI OAuth", "oauth", "Authenticate through Gemini CLI OAuth.", "google:gemini-3.1-pro-preview", "https://generativelanguage.googleapis.com/v1beta/openai", "https://ai.google.dev/", false),
    CliModelAuthChoiceDescriptor("github-copilot-oauth", "github-copilot", "global", "GitHub Copilot", "oauth", "Use GitHub Copilot account auth.", "github-copilot:gpt-5.4", "", "https://github.com/features/copilot", false),
    CliModelAuthChoiceDescriptor("google-api-key", "google", "global", "Google API key", "api-key", "Google Gemini API key", "google:gemini-3.1-pro-preview", "https://generativelanguage.googleapis.com/v1beta/openai", "https://ai.google.dev/", false),
    CliModelAuthChoiceDescriptor("huggingface-api-key", "huggingface", "global", "Hugging Face token", "api-key", "Hugging Face router token", "huggingface:Qwen/Qwen3-Coder-480B-A35B-Instruct", "https://router.huggingface.co/v1", "https://huggingface.co/", false),
    CliModelAuthChoiceDescriptor("kilocode-api-key", "kilocode", "custom", "Kilo Gateway API key", "api-key", "Kilo Gateway unified API", "kilocode:kilo/auto", "https://api.kilocode.ai/v1", "https://docs.metis.ai/providers/kilocode", false),
    CliModelAuthChoiceDescriptor("litellm-api-key", "litellm", "custom", "LiteLLM key/token", "api-key", "LiteLLM gateway token", "litellm:gpt-5.4", "http://127.0.0.1:4000/v1", "https://docs.litellm.ai/", false),
    CliModelAuthChoiceDescriptor("foundry-api-key", "foundry", "global", "Microsoft Foundry API key", "api-key", "Azure AI Foundry credential", "foundry:gpt-4.1", "", "https://learn.microsoft.com/azure/ai-foundry/", false),
    CliModelAuthChoiceDescriptor("minimax-api-key", "minimax", "domestic", "MiniMax API key", "api-key", "MiniMax direct API", "minimax:MiniMax-M2.7", "https://api.minimax.chat/v1", "https://www.minimax.io/", false),
    CliModelAuthChoiceDescriptor("mistral-api-key", "mistral", "global", "Mistral API key", "api-key", "Mistral direct API", "mistral:mistral-large-latest", "https://api.mistral.ai/v1", "https://console.mistral.ai/", false),
    CliModelAuthChoiceDescriptor("moonshot-api-key", "moonshot", "domestic", "Moonshot AI API key", "api-key", "Moonshot AI (Kimi) direct API", "moonshot:kimi-k2.5", "https://api.kimi.com/coding/v1", "https://platform.moonshot.cn/", true),
    CliModelAuthChoiceDescriptor("ollama-local", "ollama", "local", "Ollama local server", "local", "Use a local Ollama OpenAI-compatible endpoint.", "ollama:qwen3:latest", "http://127.0.0.1:11434/v1", "https://ollama.com/", false),
    CliModelAuthChoiceDescriptor("openai-api-key", "openai", "global", "OpenAI API key", "api-key", "OpenAI direct API key", "openai:gpt-5.4", "https://api.openai.com/v1", "https://platform.openai.com/", true),
    CliModelAuthChoiceDescriptor("openai-codex-oauth", "openai-codex", "global", "OpenAI Codex subscription/OAuth", "oauth", "Subscription-style auth for OpenAI Codex workflows.", "openai-codex:gpt-5.4", "https://api.openai.com/v1", "https://platform.openai.com/", false),
    CliModelAuthChoiceDescriptor("opencode-api-key", "opencode", "global", "OpenCode catalog auth", "api-key", "OpenCode shared catalog access.", "opencode:claude-opus-4-6", "", "https://docs.metis.ai/providers/opencode", false),
    CliModelAuthChoiceDescriptor("openrouter-api-key", "openrouter", "global", "OpenRouter API key", "api-key", "OpenRouter unified API", "openrouter:openai/gpt-5.4", "https://openrouter.ai/api/v1", "https://openrouter.ai/", false),
    CliModelAuthChoiceDescriptor("qianfan-api-key", "qianfan", "domestic", "Qianfan API key", "api-key", "Qianfan direct API", "qianfan:deepseek-v3.2", "https://qianfan.baidubce.com/v2", "https://cloud.baidu.com/product/wenxinworkshop", false),
    CliModelAuthChoiceDescriptor("qwen-api-key-cn", "qwen", "domestic", "Coding Plan API Key for China (subscription)", "api-key", "Endpoint: coding.dashscope.aliyuncs.com/v1", "qwen/qwen3.5-plus", "https://coding.dashscope.aliyuncs.com/v1", "https://help.aliyun.com/zh/model-studio/", true),
    CliModelAuthChoiceDescriptor("qwen-api-key", "qwen", "domestic", "Coding Plan API Key for Global/Intl (subscription)", "api-key", "Endpoint: coding-intl.dashscope.aliyuncs.com/v1", "qwen/qwen3.5-plus", "https://coding-intl.dashscope.aliyuncs.com/v1", "https://help.aliyun.com/zh/model-studio/", true),
    CliModelAuthChoiceDescriptor("qwen-standard-api-key-cn", "qwen", "domestic", "Standard API Key for China (pay-as-you-go)", "api-key", "Endpoint: dashscope.aliyuncs.com/compatible-mode/v1", "qwen/qwen3.6-plus", "https://dashscope.aliyuncs.com/compatible-mode/v1", "https://help.aliyun.com/zh/model-studio/", true),
    CliModelAuthChoiceDescriptor("qwen-standard-api-key", "qwen", "domestic", "Standard API Key for Global/Intl (pay-as-you-go)", "api-key", "Endpoint: dashscope-intl.aliyuncs.com/compatible-mode/v1", "qwen/qwen3.6-plus", "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", "https://help.aliyun.com/zh/model-studio/", true),
    CliModelAuthChoiceDescriptor("sglang-local", "sglang", "local", "SGLang local server", "local", "Use a local SGLang OpenAI-compatible endpoint.", "sglang:LocalModel", "http://127.0.0.1:30000/v1", "https://docs.metis.ai/providers/sglang", false),
    CliModelAuthChoiceDescriptor("stepfun-api-key", "stepfun", "domestic", "StepFun API key", "api-key", "StepFun direct API", "stepfun:step-2-16k", "https://api.stepfun.com/v1", "https://platform.stepfun.com/", false),
    CliModelAuthChoiceDescriptor("synthetic-api-key", "synthetic", "global", "Synthetic API key", "api-key", "Synthetic provider key", "synthetic:hf:MiniMaxAI/MiniMax-M2.5", "", "https://docs.metis.ai/providers/synthetic", false),
    CliModelAuthChoiceDescriptor("together-api-key", "together", "global", "Together AI API key", "api-key", "Together AI unified API", "together:moonshotai/Kimi-K2.5", "https://api.together.xyz/v1", "https://www.together.ai/", false),
    CliModelAuthChoiceDescriptor("venice-api-key", "venice", "global", "Venice AI API key", "api-key", "Venice privacy-first inference", "venice:venice-uncensored", "https://api.venice.ai/api/v1", "https://venice.ai/", false),
    CliModelAuthChoiceDescriptor("vercel-ai-gateway-api-key", "vercel-ai-gateway", "global", "Vercel AI Gateway token", "api-key", "Vercel AI Gateway account token", "vercel-ai-gateway:anthropic/claude-opus-4.6", "https://ai-gateway.vercel.sh/v1", "https://vercel.com/ai-gateway", false),
    CliModelAuthChoiceDescriptor("vllm-local", "vllm", "local", "vLLM local server", "local", "Use a local vLLM OpenAI-compatible endpoint.", "vllm:LocalModel", "http://127.0.0.1:8000/v1", "https://docs.metis.ai/providers/vllm", false),
    CliModelAuthChoiceDescriptor("volcengine-api-key", "volcengine", "domestic", "Volcano Engine API key", "api-key", "Volcano Engine / ARK direct API", "volcengine:ark-code-latest", "https://ark.cn-beijing.volces.com/api/coding/v3", "https://www.volcengine.com/product/ark", true),
    CliModelAuthChoiceDescriptor("xai-api-key", "xai", "global", "xAI API key", "api-key", "xAI direct API", "xai:grok-4", "https://api.x.ai/v1", "https://x.ai/", false),
    CliModelAuthChoiceDescriptor("xiaomi-api-key", "xiaomi", "domestic", "Xiaomi API key", "api-key", "Xiaomi direct API", "xiaomi:mi-32k", "", "https://platform.xiaomi.com/", false),
    CliModelAuthChoiceDescriptor("zai-api-key", "zai", "domestic", "Z.AI API key", "api-key", "Z.AI / GLM direct API", "zai:glm-4.5", "https://open.bigmodel.cn/api/coding/paas/v4", "https://open.bigmodel.cn/", true)
]

public func cliModelAuthChoiceGroups(): Array<CliModelAuthChoiceGroupDescriptor> {
    CLI_MODEL_AUTH_CHOICE_GROUPS
}

public func cliModelAuthChoiceCatalog(): Array<CliModelAuthChoiceDescriptor> {
    CLI_MODEL_AUTH_CHOICES
}

public func cliFindModelAuthChoicesForProvider(providerId: String): Array<CliModelAuthChoiceDescriptor> {
    let canonical = cliCanonicalModelProviderId(providerId)
    let out = ArrayList<CliModelAuthChoiceDescriptor>()
    for (choice in CLI_MODEL_AUTH_CHOICES) {
        if (choice.providerId == canonical) {
            out.add(choice)
        }
    }
    out.toArray()
}

public func cliFindModelAuthChoice(choiceId: String): Option<CliModelAuthChoiceDescriptor> {
    let normalized = choiceId.trimAscii().toAsciiLower()
    for (choice in CLI_MODEL_AUTH_CHOICES) {
        if (choice.choiceId == normalized) {
            return Some(choice)
        }
    }
    None
}

private func cliNormalizeBaseUrl(raw: String): String {
    var value = raw.trimAscii()
    while (value.size > 1 && value.endsWith("/")) {
        value = value[0..value.size - 1]
    }
    value
}

public func cliQwenSupportedBaseUrls(): Array<String> {
    [
        "https://coding.dashscope.aliyuncs.com/v1",
        "https://coding-intl.dashscope.aliyuncs.com/v1",
        "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    ]
}

public func cliValidateProviderBaseUrl(providerId: String, baseUrl: String): String {
    let canonical = cliCanonicalModelProviderId(providerId)
    let normalized = cliNormalizeBaseUrl(baseUrl)
    if (normalized.isEmpty()) {
        return ""
    }
    if (canonical == "qwen") {
        for (candidate in cliQwenSupportedBaseUrls()) {
            if (cliNormalizeBaseUrl(candidate) == normalized) {
                return ""
            }
        }
        return "Qwen Cloud only supports: coding.dashscope.aliyuncs.com/v1, coding-intl.dashscope.aliyuncs.com/v1, dashscope.aliyuncs.com/compatible-mode/v1, dashscope-intl.aliyuncs.com/compatible-mode/v1"
    }
    ""
}

public func cliBaseUrlMatchesAuthChoice(choiceId: String, baseUrl: String): Bool {
    let normalized = cliNormalizeBaseUrl(baseUrl)
    if (normalized.isEmpty()) {
        return false
    }
    match (cliFindModelAuthChoice(choiceId)) {
        case Some(choice) =>
            let expected = cliNormalizeBaseUrl(choice.baseUrl)
            if (expected.isEmpty()) {
                return true
            }
            normalized == expected
        case None => false
    }
}
