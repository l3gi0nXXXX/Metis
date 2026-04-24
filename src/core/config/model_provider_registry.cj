package metis.core.config

import std.collection.ArrayList

public struct CliModelProviderDescriptor {
    public CliModelProviderDescriptor(
        public let providerId: String,
        public let displayName: String,
        public let groupId: String,
        public let runtimeProviderId: String,
        public let aliases: Array<String>,
        public let apiKeyEnv: String,
        public let baseUrlEnv: String,
        public let apiKeyEnvAliases: Array<String>,
        public let baseUrlEnvAliases: Array<String>,
        public let defaultModelRef: String,
        public let defaultBaseUrl: String,
        public let docsUrl: String,
        public let highPriority: Bool,
        public let setupVisible: Bool
    ) {}
}

private let CLI_MODEL_PROVIDER_DESCRIPTORS = [
    CliModelProviderDescriptor("anthropic", "Anthropic", "global", "anthropic", ["anthropic"], "ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL", ["ANTHROPIC_API_KEY"], ["ANTHROPIC_BASE_URL"], "anthropic:claude-sonnet-4-6", "https://api.anthropic.com/v1", "https://console.anthropic.com/", true, true),
    CliModelProviderDescriptor("arcee", "Arcee AI", "global", "arcee", ["arcee"], "ARCEE_API_KEY", "ARCEE_BASE_URL", ["ARCEE_API_KEY"], ["ARCEE_BASE_URL"], "arcee:arcee-blitz", "https://conductor.arcee.ai/v1", "https://www.arcee.ai/", false, true),
    CliModelProviderDescriptor("byteplus", "BytePlus", "domestic", "ark", ["byteplus"], "BYTEPLUS_API_KEY", "BYTEPLUS_BASE_URL", ["BYTEPLUS_API_KEY", "ARK_API_KEY"], ["BYTEPLUS_BASE_URL", "ARK_BASE_URL"], "byteplus:ark-code-latest", "https://ark.cn-beijing.volces.com/api/coding/v3", "https://www.byteplus.com/", true, true),
    CliModelProviderDescriptor("chutes", "Chutes", "global", "chutes", ["chutes"], "CHUTES_API_KEY", "CHUTES_BASE_URL", ["CHUTES_API_KEY"], ["CHUTES_BASE_URL"], "chutes:deepseek-r1", "https://api.chutes.ai/v1", "https://docs.metis.ai/providers/chutes", false, true),
    CliModelProviderDescriptor("cloudflare-ai-gateway", "Cloudflare AI Gateway", "global", "cloudflare-ai-gateway", ["cloudflare-ai-gateway", "ai-gateway"], "CLOUDFLARE_AI_GATEWAY_API_KEY", "CLOUDFLARE_AI_GATEWAY_BASE_URL", ["CLOUDFLARE_AI_GATEWAY_API_KEY"], ["CLOUDFLARE_AI_GATEWAY_BASE_URL"], "cloudflare-ai-gateway:claude-sonnet-4-5", "https://gateway.ai.cloudflare.com/v1", "https://developers.cloudflare.com/ai-gateway/", false, true),
    CliModelProviderDescriptor("copilot-proxy", "Copilot Proxy", "global", "copilot-proxy", ["copilot-proxy"], "COPILOT_PROXY_TOKEN", "COPILOT_PROXY_BASE_URL", ["COPILOT_PROXY_TOKEN"], ["COPILOT_PROXY_BASE_URL"], "copilot-proxy:gpt-5.4", "http://127.0.0.1:4141/v1", "https://docs.metis.ai/providers/github-copilot", false, true),
    CliModelProviderDescriptor("custom", "Custom Provider", "custom", "custom", ["custom", "custom-provider", "custom-api-key"], "CUSTOM_API_KEY", "CUSTOM_BASE_URL", ["CUSTOM_API_KEY"], ["CUSTOM_BASE_URL"], "custom:gpt-5.4-compatible", "", "", true, true),
    CliModelProviderDescriptor("deepseek", "DeepSeek", "domestic", "deepseek", ["deepseek"], "DEEPSEEK_API_KEY", "DEEPSEEK_BASE_URL", ["DEEPSEEK_API_KEY"], ["DEEPSEEK_BASE_URL"], "deepseek:deepseek-chat", "https://api.deepseek.com/v1", "https://platform.deepseek.com/", true, true),
    CliModelProviderDescriptor("fireworks", "Fireworks", "global", "fireworks", ["fireworks"], "FIREWORKS_API_KEY", "FIREWORKS_BASE_URL", ["FIREWORKS_API_KEY"], ["FIREWORKS_BASE_URL"], "fireworks:accounts/fireworks/models/llama-v3p1-70b-instruct", "https://api.fireworks.ai/inference/v1", "https://docs.metis.ai/providers/fireworks", false, true),
    CliModelProviderDescriptor("gemini-cli-oauth", "Gemini CLI OAuth", "global", "google", ["gemini-cli-oauth"], "GOOGLE_API_KEY", "GOOGLE_BASE_URL", ["GOOGLE_API_KEY", "GEMINI_API_KEY"], ["GOOGLE_BASE_URL", "GEMINI_BASE_URL"], "google:gemini-3.1-pro-preview", "https://generativelanguage.googleapis.com/v1beta/openai", "https://ai.google.dev/", false, true),
    CliModelProviderDescriptor("github-copilot", "GitHub Copilot", "global", "github-copilot", ["github-copilot", "copilot"], "GITHUB_COPILOT_TOKEN", "GITHUB_COPILOT_BASE_URL", ["GITHUB_COPILOT_TOKEN"], ["GITHUB_COPILOT_BASE_URL"], "github-copilot:gpt-5.4", "", "https://github.com/features/copilot", false, true),
    CliModelProviderDescriptor("google", "Google", "global", "google", ["google", "gemini"], "GOOGLE_API_KEY", "GOOGLE_BASE_URL", ["GOOGLE_API_KEY", "GEMINI_API_KEY"], ["GOOGLE_BASE_URL", "GEMINI_BASE_URL"], "google:gemini-3.1-pro-preview", "https://generativelanguage.googleapis.com/v1beta/openai", "https://ai.google.dev/", false, true),
    CliModelProviderDescriptor("huggingface", "Hugging Face", "global", "huggingface", ["huggingface", "hf"], "HUGGINGFACE_API_KEY", "HUGGINGFACE_BASE_URL", ["HUGGINGFACE_API_KEY", "HF_TOKEN"], ["HUGGINGFACE_BASE_URL"], "huggingface:Qwen/Qwen3-Coder-480B-A35B-Instruct", "https://router.huggingface.co/v1", "https://huggingface.co/", false, true),
    CliModelProviderDescriptor("kilocode", "Kilo Gateway", "custom", "kilocode", ["kilocode", "kilo"], "KILOCODE_API_KEY", "KILOCODE_BASE_URL", ["KILOCODE_API_KEY"], ["KILOCODE_BASE_URL"], "kilocode:kilo/auto", "https://api.kilocode.ai/v1", "https://docs.metis.ai/providers/kilocode", false, true),
    CliModelProviderDescriptor("litellm", "LiteLLM", "custom", "litellm", ["litellm"], "LITELLM_API_KEY", "LITELLM_BASE_URL", ["LITELLM_API_KEY"], ["LITELLM_BASE_URL"], "litellm:gpt-5.4", "http://127.0.0.1:4000/v1", "https://docs.litellm.ai/", false, true),
    CliModelProviderDescriptor("foundry", "Microsoft Foundry", "global", "foundry", ["foundry", "microsoft-foundry"], "FOUNDRY_API_KEY", "FOUNDRY_BASE_URL", ["FOUNDRY_API_KEY"], ["FOUNDRY_BASE_URL"], "foundry:gpt-4.1", "", "https://learn.microsoft.com/azure/ai-foundry/", false, true),
    CliModelProviderDescriptor("minimax", "MiniMax", "domestic", "openai", ["minimax"], "MINIMAX_API_KEY", "MINIMAX_BASE_URL", ["MINIMAX_API_KEY"], ["MINIMAX_BASE_URL"], "minimax:MiniMax-M2.7", "https://api.minimax.chat/v1", "https://www.minimax.io/", false, true),
    CliModelProviderDescriptor("mistral", "Mistral AI", "global", "openai", ["mistral"], "MISTRAL_API_KEY", "MISTRAL_BASE_URL", ["MISTRAL_API_KEY"], ["MISTRAL_BASE_URL"], "mistral:mistral-large-latest", "https://api.mistral.ai/v1", "https://console.mistral.ai/", false, true),
    CliModelProviderDescriptor("moonshot", "Moonshot AI (Kimi K2.5)", "domestic", "moonshot", ["moonshot", "kimi"], "MOONSHOT_API_KEY", "MOONSHOT_BASE_URL", ["MOONSHOT_API_KEY"], ["MOONSHOT_BASE_URL"], "moonshot:kimi-k2.5", "https://api.kimi.com/coding/v1", "https://platform.moonshot.cn/", true, true),
    CliModelProviderDescriptor("ollama", "Ollama", "local", "ollama", ["ollama"], "", "OLLAMA_BASE_URL", Array<String>(), ["OLLAMA_BASE_URL"], "ollama:qwen3:latest", "http://127.0.0.1:11434/v1", "https://ollama.com/", false, true),
    CliModelProviderDescriptor("openai", "OpenAI", "global", "openai", ["openai"], "OPENAI_API_KEY", "OPENAI_BASE_URL", ["OPENAI_API_KEY"], ["OPENAI_BASE_URL"], "openai:gpt-5.4", "https://api.openai.com/v1", "https://platform.openai.com/", true, true),
    CliModelProviderDescriptor("openai-codex", "OpenAI Codex", "global", "openai", ["openai-codex", "codex"], "OPENAI_API_KEY", "OPENAI_BASE_URL", ["OPENAI_API_KEY"], ["OPENAI_BASE_URL"], "openai-codex:gpt-5.4", "https://api.openai.com/v1", "https://platform.openai.com/", false, true),
    CliModelProviderDescriptor("opencode", "OpenCode", "global", "opencode", ["opencode"], "OPENCODE_API_KEY", "OPENCODE_BASE_URL", ["OPENCODE_API_KEY"], ["OPENCODE_BASE_URL"], "opencode:claude-opus-4-6", "", "https://docs.metis.ai/providers/opencode", false, true),
    CliModelProviderDescriptor("openrouter", "OpenRouter", "global", "openrouter", ["openrouter"], "OPENROUTER_API_KEY", "OPENROUTER_BASE_URL", ["OPENROUTER_API_KEY"], ["OPENROUTER_BASE_URL"], "openrouter:openai/gpt-5.4", "https://openrouter.ai/api/v1", "https://openrouter.ai/", false, true),
    CliModelProviderDescriptor("qianfan", "Qianfan", "domestic", "openai", ["qianfan"], "QIANFAN_API_KEY", "QIANFAN_BASE_URL", ["QIANFAN_API_KEY"], ["QIANFAN_BASE_URL"], "qianfan:deepseek-v3.2", "https://qianfan.baidubce.com/v2", "https://cloud.baidu.com/product/wenxinworkshop", false, true),
    CliModelProviderDescriptor("qwen", "Qwen Cloud", "domestic", "dashscope", ["qwen", "bailian", "modelstudio", "qwencloud", "dashscope"], "QWEN_API_KEY", "QWEN_BASE_URL", ["QWEN_API_KEY", "BAILIAN_API_KEY", "MODELSTUDIO_API_KEY", "QWENCLOUD_API_KEY", "DASHSCOPE_API_KEY"], ["QWEN_BASE_URL", "BAILIAN_BASE_URL", "MODELSTUDIO_BASE_URL", "QWENCLOUD_BASE_URL", "DASHSCOPE_BASE_URL"], "qwen:qwen3.5-plus", "https://dashscope.aliyuncs.com/compatible-mode/v1", "https://help.aliyun.com/zh/model-studio/", true, true),
    CliModelProviderDescriptor("sglang", "SGLang", "local", "sglang", ["sglang"], "", "SGLANG_BASE_URL", Array<String>(), ["SGLANG_BASE_URL"], "sglang:LocalModel", "http://127.0.0.1:30000/v1", "https://docs.metis.ai/providers/sglang", false, true),
    CliModelProviderDescriptor("stepfun", "StepFun", "domestic", "stepfun", ["stepfun"], "STEPFUN_API_KEY", "STEPFUN_BASE_URL", ["STEPFUN_API_KEY"], ["STEPFUN_BASE_URL"], "stepfun:step-2-16k", "https://api.stepfun.com/v1", "https://platform.stepfun.com/", false, true),
    CliModelProviderDescriptor("synthetic", "Synthetic", "global", "synthetic", ["synthetic"], "SYNTHETIC_API_KEY", "SYNTHETIC_BASE_URL", ["SYNTHETIC_API_KEY"], ["SYNTHETIC_BASE_URL"], "synthetic:hf:MiniMaxAI/MiniMax-M2.5", "", "https://docs.metis.ai/providers/synthetic", false, true),
    CliModelProviderDescriptor("together", "Together AI", "global", "together", ["together"], "TOGETHER_API_KEY", "TOGETHER_BASE_URL", ["TOGETHER_API_KEY"], ["TOGETHER_BASE_URL"], "together:moonshotai/Kimi-K2.5", "https://api.together.xyz/v1", "https://www.together.ai/", false, true),
    CliModelProviderDescriptor("venice", "Venice AI", "global", "venice", ["venice"], "VENICE_API_KEY", "VENICE_BASE_URL", ["VENICE_API_KEY"], ["VENICE_BASE_URL"], "venice:venice-uncensored", "https://api.venice.ai/api/v1", "https://venice.ai/", false, true),
    CliModelProviderDescriptor("vercel-ai-gateway", "Vercel AI Gateway", "global", "vercel-ai-gateway", ["vercel-ai-gateway"], "AI_GATEWAY_API_KEY", "AI_GATEWAY_BASE_URL", ["AI_GATEWAY_API_KEY"], ["AI_GATEWAY_BASE_URL"], "vercel-ai-gateway:anthropic/claude-opus-4.6", "https://ai-gateway.vercel.sh/v1", "https://vercel.com/ai-gateway", false, true),
    CliModelProviderDescriptor("vllm", "vLLM", "local", "vllm", ["vllm"], "", "VLLM_BASE_URL", Array<String>(), ["VLLM_BASE_URL"], "vllm:LocalModel", "http://127.0.0.1:8000/v1", "https://docs.metis.ai/providers/vllm", false, true),
    CliModelProviderDescriptor("volcengine", "Volcano Engine", "domestic", "ark", ["volcengine", "volcano-engine"], "VOLCENGINE_API_KEY", "VOLCENGINE_BASE_URL", ["VOLCENGINE_API_KEY", "ARK_API_KEY"], ["VOLCENGINE_BASE_URL", "ARK_BASE_URL"], "volcengine:ark-code-latest", "https://ark.cn-beijing.volces.com/api/coding/v3", "https://www.volcengine.com/product/ark", true, true),
    CliModelProviderDescriptor("xai", "xAI (Grok)", "global", "xai", ["xai", "grok"], "XAI_API_KEY", "XAI_BASE_URL", ["XAI_API_KEY"], ["XAI_BASE_URL"], "xai:grok-4", "https://api.x.ai/v1", "https://x.ai/", false, true),
    CliModelProviderDescriptor("xiaomi", "Xiaomi", "domestic", "xiaomi", ["xiaomi"], "XIAOMI_API_KEY", "XIAOMI_BASE_URL", ["XIAOMI_API_KEY"], ["XIAOMI_BASE_URL"], "xiaomi:mi-32k", "", "https://platform.xiaomi.com/", false, true),
    CliModelProviderDescriptor("zai", "Z.AI", "domestic", "zhipuai", ["zai", "zhipuai", "glm"], "ZAI_API_KEY", "ZAI_BASE_URL", ["ZAI_API_KEY", "ZHIPU_API_KEY"], ["ZAI_BASE_URL", "ZHIPU_BASE_URL"], "zai:glm-4.5", "https://open.bigmodel.cn/api/coding/paas/v4", "https://open.bigmodel.cn/", true, true),
    CliModelProviderDescriptor("maas", "ModelArts MaaS", "domestic", "maas", ["maas"], "MAAS_API_KEY", "MAAS_BASE_URL", ["MAAS_API_KEY"], ["MAAS_BASE_URL"], "maas:qwen2.5-vl-72b", "https://api.modelarts-maas.com/v1", "https://www.huaweicloud.com/product/modelarts.html", false, true)
]

public func cliModelProviderCatalogDescriptors(): Array<CliModelProviderDescriptor> {
    CLI_MODEL_PROVIDER_DESCRIPTORS
}

public func cliFindModelProviderDescriptor(providerId: String): Option<CliModelProviderDescriptor> {
    let normalized = providerId.trimAscii().toAsciiLower()
    if (normalized.isEmpty()) {
        return None
    }
    for (descriptor in CLI_MODEL_PROVIDER_DESCRIPTORS) {
        for (alias in descriptor.aliases) {
            if (alias == normalized) {
                return Some(descriptor)
            }
        }
    }
    None
}

public func cliCanonicalModelProviderId(providerId: String): String {
    match (cliFindModelProviderDescriptor(providerId)) {
        case Some(descriptor) => descriptor.providerId
        case None => providerId.trimAscii().toAsciiLower()
    }
}

public func cliRuntimeModelProviderId(providerId: String): String {
    match (cliFindModelProviderDescriptor(providerId)) {
        case Some(descriptor) => descriptor.runtimeProviderId
        case None => providerId.trimAscii().toAsciiLower()
    }
}

public func cliProviderPrimaryEnvNames(providerId: String): (String, String) {
    match (cliFindModelProviderDescriptor(providerId)) {
        case Some(descriptor) => (descriptor.apiKeyEnv, descriptor.baseUrlEnv)
        case None => ("", "")
    }
}

public func cliProviderApiKeyEnvAliases(providerId: String): Array<String> {
    match (cliFindModelProviderDescriptor(providerId)) {
        case Some(descriptor) => descriptor.apiKeyEnvAliases
        case None => Array<String>()
    }
}

public func cliProviderBaseUrlEnvAliases(providerId: String): Array<String> {
    match (cliFindModelProviderDescriptor(providerId)) {
        case Some(descriptor) => descriptor.baseUrlEnvAliases
        case None => Array<String>()
    }
}

public func cliProviderApiKeyConfigPath(providerId: String): String {
    match (cliFindModelProviderDescriptor(providerId)) {
        case Some(descriptor) => "models.providers.${descriptor.providerId}.apiKey"
        case None => ""
    }
}

public func cliProviderBaseUrlConfigPath(providerId: String): String {
    match (cliFindModelProviderDescriptor(providerId)) {
        case Some(descriptor) => "models.providers.${descriptor.providerId}.baseUrl"
        case None => ""
    }
}

public func cliSetupVisibleModelProviders(): Array<CliModelProviderDescriptor> {
    let rows = ArrayList<CliModelProviderDescriptor>()
    for (descriptor in CLI_MODEL_PROVIDER_DESCRIPTORS) {
        if (descriptor.setupVisible) {
            rows.add(descriptor)
        }
    }
    rows.toArray()
}
