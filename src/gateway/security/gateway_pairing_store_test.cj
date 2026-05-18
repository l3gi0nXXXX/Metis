package metis.gateway.security

import std.fs.Path
import std.time.DateTime
import std.unittest.testmacro.*

@Test
public class GatewayPairingStoreTest {
    private func tempRoot(name: String): Path {
        Path("/tmp/${name}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
    }

    @TestCase
    public func feishuStoreCreatesReusablePendingCodeAndApprovesSender(): Unit {
        let root = this.tempRoot("metis-feishu-pairing-store")
        let store = gatewayPairingAccountStore(channel: "feishu", accountId: "tenant-a", rootDir: root)

        let code = store.ensurePending("ou_a")
        @Expect(!code.isEmpty(), true)
        @Expect(store.ensurePending("ou_a"), code)
        @Expect(store.pendingCodeForSender("feishu:ou_a"), code)
        @Expect(store.pendingRows().size, 1)

        @Expect(store.approve(code.toAsciiLower()), true)
        @Expect(store.isApproved("ou_a"), true)
        @Expect(store.pendingRows().isEmpty(), true)
        @Expect(store.approve(code), false)
    }

    @TestCase
    public func feishuStoreIsolatesApprovedSendersByAccount(): Unit {
        let root = this.tempRoot("metis-feishu-pairing-account-isolation")
        let accountA = gatewayPairingAccountStore(channel: "feishu", accountId: "tenant-a", rootDir: root)
        let accountB = gatewayPairingAccountStore(channel: "feishu", accountId: "tenant-b", rootDir: root)
        let code = accountA.ensurePending("ou_a")

        @Expect(accountA.approve(code), true)
        @Expect(accountA.isApproved("ou_a"), true)
        @Expect(accountB.isApproved("ou_a"), false)
        @Expect(accountB.pendingRows().isEmpty(), true)
    }

    @TestCase
    public func feishuStoreUsesChannelAndAccountScopedPaths(): Unit {
        let root = this.tempRoot("metis-feishu-pairing-path")
        let store = gatewayPairingAccountStore(channel: "feishu", accountId: "feishu:tenant/a", rootDir: root)

        @Expect(store.rootPath().toString().contains("gateway-feishu/accounts/tenant_a"), true)
    }
}
