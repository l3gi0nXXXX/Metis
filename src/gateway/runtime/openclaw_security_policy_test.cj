package metis.gateway.runtime

import metis.gateway.openclaw_security.*
import std.unittest.testmacro.*
import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonObject}

private func openClawSecurityStr(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func openClawSecurityBoolValue(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func openClawSecurityArr(obj: JsonObject, key: String): JsonArray {
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
        @Expect(openClawSecurityBoolValue(denied, "allowed"), false)
        @Expect(openClawSecurityStr(denied, "stage"), "install")
        @Expect(openClawSecurityStr(denied, "code"), "source_ref_mismatch")

        let allowed = policy.enforceInstallSource("https://github.com/openclaw/demo.git", "refs/tags/v1.0.0", "sha256:good")
        @Expect(openClawSecurityBoolValue(allowed, "allowed"), true)
        @Expect(openClawSecurityStr(allowed, "code"), "allowed")
    }

    @TestCase
    public func startGateDeniesUngrantedPermissions(): Unit {
        let policy = OpenClawSecurityPolicy("demo")
        policy.grant("network", "use", "api.example.com")

        let requirements = ArrayList<OpenClawPermissionRequirement>()
        requirements.add(OpenClawPermissionRequirement("network", "use", "api.example.com", "manifest", "needed"))
        requirements.add(OpenClawPermissionRequirement("secret", "read", "TELEGRAM_BOT_TOKEN", "manifest", "needed"))

        let decision = policy.enforceStart(requirements)
        @Expect(openClawSecurityBoolValue(decision, "allowed"), false)
        @Expect(openClawSecurityStr(decision, "stage"), "start")
        @Expect(openClawSecurityArr(decision, "denied").size(), 1)
        @Expect(openClawSecurityStr(openClawSecurityArr(decision, "denied")[0].asObject(), "category"), "secret")
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

        @Expect(openClawSecurityBoolValue(fileDenied, "allowed"), false)
        @Expect(openClawSecurityBoolValue(networkDenied, "allowed"), false)
        @Expect(openClawSecurityStr(fileDenied, "code"), "permission_denied")
        @Expect(openClawSecurityStr(networkDenied, "code"), "permission_denied")
        @Expect(fileDenied.toString().contains("top-secret-password"), false)
        @Expect(networkDenied.toString().contains("stolen-token"), false)
    }

    @TestCase
    public func handlerDispatchGateDeniesUnauthorizedDeclaredRuntimePermissions(): Unit {
        let policy = OpenClawSecurityPolicy("malicious")
        policy.grant("filesystem", "read", "/tmp/metis-plugin-cache")
        policy.grant("network", "use", "api.example.com")
        let requirements = ArrayList<OpenClawPermissionRequirement>()
        requirements.add(OpenClawPermissionRequirement("filesystem", "read", "/Users/alice/.ssh/id_rsa", "handler", "password=top-secret-password"))
        requirements.add(OpenClawPermissionRequirement("network", "connect", "https://evil.example.net/steal", "handler", "Authorization: Bearer stolen-token"))

        let decision = policy.enforceHandlerDispatch(requirements)
        @Expect(openClawSecurityBoolValue(decision, "allowed"), false)
        @Expect(openClawSecurityStr(decision, "stage"), "handler-dispatch")
        @Expect(openClawSecurityStr(decision, "code"), "permission_denied")
        @Expect(openClawSecurityArr(decision, "denied").size(), 2)
        @Expect(decision.toString().contains("top-secret-password"), false)
        @Expect(decision.toString().contains("stolen-token"), false)
    }

    @TestCase
    public func crashAndTimeoutDecisionsAreDeniedAndRedacted(): Unit {
        let crashed = openClawHandlerCrashDecision("demo", "handler", "boom password=hunter2 Authorization: Bearer crash-secret")
        let timedOut = openClawHandlerTimeoutDecision("demo", "handler", 2500)

        @Expect(openClawSecurityBoolValue(crashed, "allowed"), false)
        @Expect(openClawSecurityStr(crashed, "code"), "handler_crash")
        @Expect(crashed.toString().contains("hunter2"), false)
        @Expect(crashed.toString().contains("crash-secret"), false)
        @Expect(openClawSecurityBoolValue(timedOut, "allowed"), false)
        @Expect(openClawSecurityStr(timedOut, "code"), "handler_timeout")
    }
}
