package metis.gateway.channels.qq

import metis.gateway.model.QQConfig

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

@Test
public class QQAdapterTest {
    @TestCase
    public func qqResolverKeepsTopLevelCompatibility(): Unit {
        let config = QQConfig(
            enabled: true,
            appId: "102012345",
            appSecret: "top-secret-never-visible"
        )

        let resolved = gatewayQqResolveAccount(config, "")
        let described = gatewayQqDescribeAccounts(config)

        @Expect(resolved.accountId, "default")
        @Expect(resolved.config.appId, "102012345")
        @Expect(resolved.config.appSecret, "top-secret-never-visible")
        @Expect(resolved.credentialSource, "top-level")
        @Expect(described.toJsonString().contains("top-secret-never-visible"), false)
        @Expect(described.toJsonString().contains("102***345"), true)
        @Expect(described.toJsonString().contains("102012345"), false)
    }

    @TestCase
    public func qqResolverPrefersConfiguredAccountOverride(): Unit {
        let accounts = JsonObject()
        let work = JsonObject()
        work.put("appId", JsonString("998877665"))
        work.put("appSecret", JsonString("account-secret-never-visible"))
        accounts.put("work", work)
        let config = QQConfig(
            accountId: "work",
            defaultAccount: "default",
            enabled: true,
            appId: "102012345",
            appSecret: "top-secret-never-visible",
            accounts: Some(accounts)
        )

        let resolved = gatewayQqResolveAccount(config, "work")

        @Expect(resolved.accountId, "work")
        @Expect(resolved.explicitAccount, true)
        @Expect(resolved.config.appId, "998877665")
        @Expect(resolved.config.appSecret, "account-secret-never-visible")
        @Expect(resolved.credentialSource, "account")
    }

    @TestCase
    public func qqResolverReportsMissingNonDefaultAccountWhenAccountsExist(): Unit {
        let accounts = JsonObject()
        accounts.put("work", JsonObject())
        let config = QQConfig(
            accountId: "missing",
            defaultAccount: "default",
            enabled: true,
            appId: "102012345",
            appSecret: "top-secret-never-visible",
            accounts: Some(accounts)
        )

        let resolved = gatewayQqResolveAccount(config, "missing")

        @Expect(resolved.missingAccount, true)
        @Expect(resolved.missingDiagnostic.contains("unknown QQ accountId"), true)
        @Expect(resolved.config.appId, "")
        @Expect(resolved.config.appSecret, "")
        @Expect(resolved.credentialSource, "missing-account")
    }
}
