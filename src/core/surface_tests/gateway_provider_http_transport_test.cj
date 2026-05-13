package metis.core.surface_tests

import metis.core.*

import std.env.{getVariable, setVariable}
import std.unittest.*
import stdx.encoding.json.{JsonBool, JsonInt, JsonObject, JsonString}

private func providerTransportConfig(proxy!: String = "", envProxyEnabled!: Bool = false, noProxy!: String = "", insecure!: Bool = false): JsonObject {
    let obj = JsonObject()
    obj.put("proxy", JsonString(proxy))
    obj.put("envProxyEnabled", JsonBool(envProxyEnabled))
    obj.put("noProxy", JsonString(noProxy))
    obj.put("insecureSkipTlsVerify", JsonBool(insecure))
    obj.put("timeoutMs", JsonInt(120000))
    obj
}

private func providerTransportRestoreEnv(key: String, oldValue: Option<String>): Unit {
    match (oldValue) {
        case Some(value) => setVariable(key, value)
        case None => setVariable(key, "")
    }
}

@Test
public class GatewayProviderHttpTransportTest {
    @TestCase
    public func httpsTargetUsesConnectTunnelForHttpProxy(): Unit {
        let cfg = resolveGatewayProviderHttpTransportConfig(providerTransportConfig(proxy: "http://127.0.0.1:7897"))
        let route = resolveGatewayProviderHttpRoute("https://dashscope.aliyuncs.com/api/v1/tasks/task-1", cfg)

        @Expect(route.mode, "httpConnectTunnel")
        @Expect(route.proxySource, "explicit")
        @Expect(route.redactedProxy, "http://127.0.0.1:7897")
        @Expect(route.targetHost, "dashscope.aliyuncs.com")
    }

    @TestCase
    public func bareHostPortProxyUsesConnectTunnelForHttpsTarget(): Unit {
        let cfg = resolveGatewayProviderHttpTransportConfig(providerTransportConfig(proxy: "127.0.0.1:7897"))
        let route = resolveGatewayProviderHttpRoute("https://dashscope.aliyuncs.com/api/v1/tasks/task-1", cfg)

        @Expect(route.mode, "httpConnectTunnel")
        @Expect(route.proxySource, "explicit")
        @Expect(route.redactedProxy, "127.0.0.1:7897")
    }

    @TestCase
    public func httpsProxyIsDiagnosedInsteadOfSilentlyDowngraded(): Unit {
        let cfg = resolveGatewayProviderHttpTransportConfig(providerTransportConfig(proxy: "https://127.0.0.1:7897"))
        let route = resolveGatewayProviderHttpRoute("https://dashscope.aliyuncs.com/api/v1/tasks/task-1", cfg)

        @Expect(route.mode, "unsupportedHttpsProxy")
        @Expect(route.proxySource, "explicit")
        @Expect(route.error.contains("true HTTPS proxy is not implemented"), true)
    }

    @TestCase
    public func noProxyBypassesEnvironmentProxy(): Unit {
        let oldHttps = getVariable("HTTPS_PROXY")
        let oldHttp = getVariable("HTTP_PROXY")
        let oldNoProxy = getVariable("NO_PROXY")
        setVariable("HTTPS_PROXY", "http://127.0.0.1:7897")
        setVariable("HTTP_PROXY", "")
        setVariable("NO_PROXY", "dashscope.aliyuncs.com")
        try {
            let cfg = resolveGatewayProviderHttpTransportConfig(providerTransportConfig(envProxyEnabled: true))
            let route = resolveGatewayProviderHttpRoute("https://dashscope.aliyuncs.com/api/v1/tasks/task-1", cfg)

            @Expect(route.mode, "direct")
            @Expect(route.proxySource, "none")
            @Expect(route.redactedProxy, "")
        } finally {
            providerTransportRestoreEnv("HTTPS_PROXY", oldHttps)
            providerTransportRestoreEnv("HTTP_PROXY", oldHttp)
            providerTransportRestoreEnv("NO_PROXY", oldNoProxy)
        }
    }

    @TestCase
    public func proxyCredentialsAreRedacted(): Unit {
        let redacted = redactGatewayProviderProxy("http://user:secret@127.0.0.1:7897")

        @Expect(redacted, "http://[redacted]@127.0.0.1:7897")
        @Expect(redacted.contains("secret"), false)
    }

    @TestCase
    public func connectRequestIncludesTargetAndOptionalProxyAuth(): Unit {
        let endpoint = parseGatewayProviderHttpProxyEndpoint("http://user:secret@127.0.0.1:7897")
        let request = buildGatewayProviderHttpConnectRequest("dashscope.aliyuncs.com", 443u16, endpoint)

        @Expect(endpoint.host, "127.0.0.1")
        @Expect(endpoint.port, 7897u16)
        @Expect(request.contains("CONNECT dashscope.aliyuncs.com:443 HTTP/1.1\r\n"), true)
        @Expect(request.contains("Host: dashscope.aliyuncs.com:443\r\n"), true)
        @Expect(request.contains("Proxy-Authorization: Basic "), true)
        @Expect(request.contains("user:secret"), false)
    }
}
