package metis.core.support_surface_tests

import metis.core.model.*

import std.unittest.testmacro.*

@Test
public class OpenClawProviderBridgeTest {
    @TestCase
    public func registerProviderBindsOpenClawMocksToMetisModelRegistryContract(): Unit {
        let registry = OpenClawProviderBridgeRegistry()
        let providers = [
            ("openai", "gpt-4o-mini", "OPENAI_API_KEY"),
            ("anthropic", "claude-3-5-sonnet-latest", "ANTHROPIC_API_KEY"),
            ("google", "gemini-1.5-pro", "GOOGLE_API_KEY"),
            ("ollama", "llama3.2", ""),
            ("openrouter", "openai/gpt-4o-mini", "OPENROUTER_API_KEY")
        ]

        for (provider in providers) {
            let registered = registry.registerProvider(OpenClawProviderRegistration(
                provider[0],
                authKind: "api-key",
                configKeys: [provider[2], "${provider[0].toAsciiUpper()}_BASE_URL"],
                models: [provider[1]],
                supportsStreaming: true,
                supportsToolCalls: true,
                supportsModelList: true
            ))
            @Expect(registered.contract, "metis.model-provider-registry.v1")
            @Expect(registered.modelRefs[0], "${registered.providerId}:${provider[1]}")
            @Expect(registered.supportsStreaming, true)
            @Expect(registered.supportsToolCalls, true)
            if (!provider[2].isEmpty()) {
                @Expect(registered.apiKeyEnvAliases.contains(provider[2]), true)
                @Expect(registered.apiKeyConfigPath.contains("models.providers.${registered.providerId}.apiKey"), true)
            }
        }

        @Expect(registry.listProviderIds().contains("openai"), true)
        @Expect(registry.listProviderIds().contains("anthropic"), true)
        @Expect(registry.listProviderIds().contains("google"), true)
        @Expect(registry.listProviderIds().contains("ollama"), true)
        @Expect(registry.listProviderIds().contains("openrouter"), true)
    }

    @TestCase
    public func providerBridgeCreatesExecutableStreamAndToolCallRequests(): Unit {
        let registry = OpenClawProviderBridgeRegistry()
        let binding = registry.registerProvider(OpenClawProviderRegistration(
            "openai",
            authKind: "api-key",
            configKeys: ["OPENAI_API_KEY", "OPENAI_BASE_URL"],
            models: ["gpt-4o-mini"],
            supportsStreaming: true,
            supportsToolCalls: true,
            supportsModelList: true
        ))

        let stream = registry.stream("openai", "gpt-4o-mini", "hello")
        let toolCall = registry.toolCall("openai", "search", "{\"query\":\"metis\"}")

        @Expect(binding.runtimeProviderId, "openai")
        @Expect(registry.listModels("openai")[0], "openai:gpt-4o-mini")
        @Expect(stream.ok, true)
        @Expect(stream.method, "openclaw.provider.stream")
        @Expect(stream.modelRef, "openai:gpt-4o-mini")
        @Expect(stream.authConfigPath, "models.providers.openai.apiKey")
        @Expect(toolCall.ok, true)
        @Expect(toolCall.method, "openclaw.provider.toolCall")
        @Expect(toolCall.name, "search")
    }

    @TestCase
    public func providerBridgeReturnsStructuredNotSupportedAndNotConfiguredEvidence(): Unit {
        let registry = OpenClawProviderBridgeRegistry()
        registry.registerProvider(OpenClawProviderRegistration(
            "local-embed",
            authKind: "none",
            configKeys: [],
            models: ["embed-small"],
            supportsStreaming: false,
            supportsToolCalls: false,
            supportsModelList: true
        ))

        let unsupportedStream = registry.stream("local-embed", "embed-small", "hello")
        let unsupportedToolCall = registry.toolCall("local-embed", "search", "{\"query\":\"metis\"}")
        let missingProvider = registry.stream("missing-provider", "model", "hello")

        @Expect(unsupportedStream.ok, false)
        @Expect(unsupportedStream.status, "not_supported")
        @Expect(unsupportedStream.evidenceJson.contains("\"capability\":\"stream\""), true)
        @Expect(unsupportedToolCall.status, "not_supported")
        @Expect(unsupportedToolCall.evidenceJson.contains("\"capability\":\"toolCall\""), true)
        @Expect(missingProvider.status, "not_configured")
        @Expect(missingProvider.evidenceJson.contains("missing-provider"), true)
    }
}
