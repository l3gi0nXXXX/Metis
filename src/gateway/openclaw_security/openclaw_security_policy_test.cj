package metis.gateway.openclaw_security

import std.unittest.testmacro.*
import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonObject}

private func str(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func boolValue(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func arr(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

@Test
public class OpenClawSecurityPolicyTest {
    @TestCase
    public func installRequiresAllowlistedSourceRefAndHash(): Unit {
        let policy = OpenClawSecurityPolicy("demo")
        policy.allowSource("https://github.com/openclaw/demo.git", ref: "refs/tags/v1.0.0", hash: "sha256:good")

        let denied = policy.enforceInstallSource("https://github.com/openclaw/demo.git", "refs/heads/main", "sha256:bad")
        @Expect(boolValue(denied, "allowed"), false)
        @Expect(str(denied, "stage"), "install")
        @Expect(str(denied, "code"), "source_ref_mismatch")

        let allowed = policy.enforceInstallSource("https://github.com/openclaw/demo.git", "refs/tags/v1.0.0", "sha256:good")
        @Expect(boolValue(allowed, "allowed"), true)
        @Expect(str(allowed, "code"), "allowed")
    }

    @TestCase
    public func startGateDeniesUngrantedPermissions(): Unit {
        let policy = OpenClawSecurityPolicy("demo")
        policy.grant("network", "use", "api.example.com")

        let requirements = ArrayList<OpenClawPermissionRequirement>()
        requirements.add(OpenClawPermissionRequirement("network", "use", "api.example.com", "manifest", "needed"))
        requirements.add(OpenClawPermissionRequirement("secret", "read", "TELEGRAM_BOT_TOKEN", "manifest", "needed"))

        let decision = policy.enforceStart(requirements)
        @Expect(boolValue(decision, "allowed"), false)
        @Expect(str(decision, "stage"), "start")
        @Expect(arr(decision, "denied").size(), 1)
        @Expect(str(arr(decision, "denied")[0].asObject(), "category"), "secret")
        @Expect(decision.toString().contains("TELEGRAM_BOT_TOKEN"), false)
    }

    @TestCase
    public func runtimeGateDeniesMaliciousFileAndNetworkAttempts(): Unit {
        let policy = OpenClawSecurityPolicy("malicious")
        policy.grant("filesystem", "read", "/tmp/metis-plugin-cache")
        policy.grant("network", "use", "api.example.com")

        let fileDenied = policy.enforceRuntimePermission(
            OpenClawPermissionRequirement("filesystem", "read", "/Users/alice/.ssh/id_rsa", "handler", "password=top-secret-password")
        )
        let networkDenied = policy.enforceRuntimePermission(
            OpenClawPermissionRequirement("network", "connect", "https://evil.example.net/steal", "handler", "Authorization: Bearer stolen-token")
        )

        @Expect(boolValue(fileDenied, "allowed"), false)
        @Expect(boolValue(networkDenied, "allowed"), false)
        @Expect(str(fileDenied, "code"), "permission_denied")
        @Expect(str(networkDenied, "code"), "permission_denied")
        @Expect(fileDenied.toString().contains("top-secret-password"), false)
        @Expect(networkDenied.toString().contains("stolen-token"), false)
    }

    @TestCase
    public func crashAndTimeoutDecisionsAreDeniedAndRedacted(): Unit {
        let crashed = openClawHandlerCrashDecision("demo", "handler", "boom password=hunter2 Authorization: Bearer crash-secret")
        let timedOut = openClawHandlerTimeoutDecision("demo", "handler", 2500)

        @Expect(boolValue(crashed, "allowed"), false)
        @Expect(str(crashed, "code"), "handler_crash")
        @Expect(crashed.toString().contains("hunter2"), false)
        @Expect(crashed.toString().contains("crash-secret"), false)
        @Expect(boolValue(timedOut, "allowed"), false)
        @Expect(str(timedOut, "code"), "handler_timeout")
    }
}
