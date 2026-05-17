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
        @Expect(resolved.configured, true)
        @Expect(resolved.credentialSource, "top-level-inherited")
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
        @Expect(resolved.configured, true)
        @Expect(resolved.credentialSource, "account-local")
        @Expect(resolved.appIdCredentialSource, "account-local")
        @Expect(resolved.appSecretCredentialSource, "account-local")
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
        @Expect(resolved.missingDiagnostic.contains("missing"), true)
    }

    @TestCase
    public func qqResolverDoesNotFallbackTopLevelForNamedAccountMissingCredentials(): Unit {
        let accounts = JsonObject()
        accounts.put("qqWriter", JsonObject())
        let config = QQConfig(
            enabled: true,
            appId: "top",
            appSecret: "top-secret-never-visible",
            accounts: Some(accounts)
        )

        let resolved = gatewayQqResolveAccount(config, "qqWriter")
        let described = gatewayQqDescribeAccounts(config)

        @Expect(resolved.accountId, "qqWriter")
        @Expect(resolved.explicitAccount, true)
        @Expect(resolved.missingAccount, false)
        @Expect(resolved.missingCredential, true)
        @Expect(resolved.configured, false)
        @Expect(resolved.config.appId, "")
        @Expect(resolved.config.appSecret, "")
        @Expect(resolved.credentialSource, "missing-account-credential")
        @Expect(resolved.appIdCredentialSource, "missing-account-credential")
        @Expect(resolved.appSecretCredentialSource, "missing-account-credential")
        @Expect(resolved.missingDiagnostic.contains("account-local credential"), true)
        @Expect(described.toJsonString().contains("top-secret-never-visible"), false)
        let rows = described.get("accounts").getOrThrow().asArray()
        let writerRow = rows[1].asObject()
        @Expect(writerRow.get("accountId").getOrThrow().asString().getValue(), "qqWriter")
        @Expect(writerRow.get("configured").getOrThrow().asBool().getValue(), false)
        @Expect(writerRow.get("missingCredential").getOrThrow().asBool().getValue(), true)
        @Expect(writerRow.get("credentialSource").getOrThrow().asString().getValue(), "missing-account-credential")
    }

    @TestCase
    public func qqResolverConfiguresNamedAccountWithAccountLocalCredentials(): Unit {
        let accounts = JsonObject()
        let writer = JsonObject()
        writer.put("appId", JsonString("writer"))
        writer.put("appSecret", JsonString("writer-secret-never-visible"))
        accounts.put("qqWriter", writer)
        let config = QQConfig(
            enabled: true,
            appId: "top",
            appSecret: "top-secret-never-visible",
            accounts: Some(accounts)
        )

        let resolved = gatewayQqResolveAccount(config, "qqWriter")

        @Expect(resolved.accountId, "qqWriter")
        @Expect(resolved.configured, true)
        @Expect(resolved.missingCredential, false)
        @Expect(resolved.config.appId, "writer")
        @Expect(resolved.config.appSecret, "writer-secret-never-visible")
        @Expect(resolved.credentialSource, "account-local")
        @Expect(resolved.appIdCredentialSource, "account-local")
        @Expect(resolved.appSecretCredentialSource, "account-local")
    }

    @TestCase
    public func qqAdapterStartReportsMissingAccountLocalCredential(): Unit {
        let accounts = JsonObject()
        accounts.put("qqWriter", JsonObject())
        let adapter = QQAdapter(
            config: QQConfig(
                enabled: true,
                appId: "top",
                appSecret: "top-secret-never-visible",
                accounts: Some(accounts)
            ),
            accountId: "qqWriter"
        )

        adapter.start()

        @Expect(adapter.debugLastSendErrorForTest().contains("account-local credential"), true)
        @Expect(adapter.debugLastSendErrorForTest().contains("qqWriter"), true)
    }
}
