package metis.core.surface_tests

import metis.core.*

import std.unittest.testmacro.*

@Test
public class GatewayActionSecurityProfilesTest {
    @TestCase
    public func gatewayActionClassesCoverCurrentSurface(): Unit {
        @Expect(gatewayActionClass("status"), "read_only")
        @Expect(gatewayActionClass("health"), "read_only")
        @Expect(gatewayActionClass("discover"), "read_only")
        @Expect(gatewayActionClass("discover.detail"), "read_only")
        @Expect(gatewayActionClass("config.get"), "read_only")
        @Expect(gatewayActionClass("config.schema.lookup"), "read_only")
        @Expect(gatewayActionClass("start"), "mutating_runtime")
        @Expect(gatewayActionClass("restart"), "mutating_runtime")
        @Expect(gatewayActionClass("config.patch"), "mutating_config")
        @Expect(gatewayActionClass("config.apply"), "mutating_config")
        @Expect(gatewayActionClass("update.run"), "control_plane")
        @Expect(gatewayActionClass("unknown.action"), "unsupported")
    }

    @TestCase
    public func gatewayActionSecurityFlagsStayConsistent(): Unit {
        @Expect(gatewayActionIsReadOnly("status"), true)
        @Expect(gatewayActionIsControlPlane("status"), false)
        @Expect(gatewayActionIsMutating("status"), false)
        @Expect(gatewayActionRequiresOwner("status"), false)
        @Expect(gatewayActionRequiresExplicitUserRequest("status"), false)
        @Expect(gatewayActionIsApprovalSensitive("status"), false)
        @Expect(gatewayActionIsProtectedPathSensitive("status"), false)

        @Expect(gatewayActionIsReadOnly("restart"), false)
        @Expect(gatewayActionIsControlPlane("restart"), true)
        @Expect(gatewayActionIsMutating("restart"), true)
        @Expect(gatewayActionRequiresOwner("restart"), true)
        @Expect(gatewayActionRequiresExplicitUserRequest("restart"), false)
        @Expect(gatewayActionIsApprovalSensitive("restart"), true)
        @Expect(gatewayActionIsProtectedPathSensitive("restart"), false)

        @Expect(gatewayActionIsReadOnly("config.apply"), false)
        @Expect(gatewayActionIsControlPlane("config.apply"), true)
        @Expect(gatewayActionIsMutating("config.apply"), true)
        @Expect(gatewayActionRequiresOwner("config.apply"), true)
        @Expect(gatewayActionRequiresExplicitUserRequest("config.apply"), true)
        @Expect(gatewayActionIsApprovalSensitive("config.apply"), true)
        @Expect(gatewayActionIsProtectedPathSensitive("config.apply"), true)

        @Expect(gatewayActionIsReadOnly("update.run"), false)
        @Expect(gatewayActionIsControlPlane("update.run"), true)
        @Expect(gatewayActionIsMutating("update.run"), false)
        @Expect(gatewayActionRequiresOwner("update.run"), true)
        @Expect(gatewayActionRequiresExplicitUserRequest("update.run"), true)
        @Expect(gatewayActionIsApprovalSensitive("update.run"), true)
        @Expect(gatewayActionIsProtectedPathSensitive("update.run"), false)
    }

    @TestCase
    public func gatewayProtectedConfigPathsStayBlocked(): Unit {
        @Expect(gatewayConfigPathIsProtected("gateway.controlUi.allowInsecureAuth"), true)
        @Expect(gatewayConfigPathIsProtected("controlUi.dangerouslyDisableDeviceAuth"), true)
        @Expect(gatewayConfigPathIsProtected("gateway.auth.mode"), true)
        @Expect(gatewayConfigPathIsProtected("auth.allowTailscale"), true)
        @Expect(gatewayConfigPathIsProtected("gateway.feishu.appId"), false)
        @Expect(gatewayConfigPathIsProtected("gateway.session.dmScope"), false)
    }
}
