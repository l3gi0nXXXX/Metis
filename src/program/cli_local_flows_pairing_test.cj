package metis.program

import metis.gateway.channels.telegram.telegramPairingAccountStore
import metis.gateway.security.gatewayPairingAccountStore

import std.fs.Path
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.JsonObject

@Test
public class CliLocalFlowsPairingTest {
    private func tempRoot(name: String): Path {
        Path("/tmp/${name}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
    }

    private func jsonString(obj: JsonObject, key: String): String {
        obj.get(key).getOrThrow().asString().getValue()
    }

    private func jsonBool(obj: JsonObject, key: String): Bool {
        obj.get(key).getOrThrow().asBool().getValue()
    }

    @TestCase
    public func feishuPairingListResultRendersHumanSummaryWithoutRawJsonOrCode(): Unit {
        let root = this.tempRoot("metis-cli-feishu-pairing-list")
        let store = gatewayPairingAccountStore(channel: "feishu", accountId: "tenant-a", rootDir: root)
        let code = store.ensurePending("ou_a")

        let obj = cliBuildPairingListResult("feishu", accountId: "tenant-a", rootDir: root).getOrThrow()
        @Expect(this.jsonString(obj, "channel"), "feishu")
        @Expect(this.jsonString(obj, "accountId"), "tenant-a")

        let rendered = cliRenderLocalCommandSummary(obj)
        @Expect(rendered.startsWith("{"), false)
        @Expect(rendered.contains("\"pending\""), false)
        @Expect(rendered.contains("\"approvedSenders\""), false)
        @Expect(rendered.contains(code), false)
        @Expect(rendered.contains("Account: tenant-a"), true)
        @Expect(rendered.contains("Pending: 1"), true)
    }

    @TestCase
    public func feishuPairingApproveResultIsAccountScopedAndHumanReadable(): Unit {
        let root = this.tempRoot("metis-cli-feishu-pairing-approve")
        let store = gatewayPairingAccountStore(channel: "feishu", accountId: "tenant-a", rootDir: root)
        let code = store.ensurePending("ou_a")

        let bad = cliBuildPairingApproveResult("feishu", "BADCODE", accountId: "tenant-a", rootDir: root).getOrThrow()
        @Expect(this.jsonBool(bad, "approved"), false)
        let badRendered = cliRenderLocalCommandSummary(bad)
        @Expect(badRendered.startsWith("{"), false)
        @Expect(badRendered.contains("Approved: false"), true)

        let approved = cliBuildPairingApproveResult("feishu", code, accountId: "tenant-a", rootDir: root).getOrThrow()
        @Expect(this.jsonBool(approved, "approved"), true)
        @Expect(store.isApproved("ou_a"), true)
        @Expect(gatewayPairingAccountStore(channel: "feishu", accountId: "tenant-b", rootDir: root).isApproved("ou_a"), false)

        let rendered = cliRenderLocalCommandSummary(approved)
        @Expect(rendered.startsWith("{"), false)
        @Expect(rendered.contains("Approved: true"), true)
        @Expect(rendered.contains("Account: tenant-a"), true)
        @Expect(rendered.contains("\"ok\""), false)
    }

    @TestCase
    public func telegramPairingApproveResultRemainsSupported(): Unit {
        let root = this.tempRoot("metis-cli-telegram-pairing-approve")
        let store = telegramPairingAccountStore(rootDir: root, accountId: "default")
        let code = store.ensurePending("745123456")

        let approved = cliBuildPairingApproveResult("telegram", code, rootDir: root).getOrThrow()
        @Expect(this.jsonString(approved, "channel"), "telegram")
        @Expect(this.jsonBool(approved, "approved"), true)
        @Expect(store.isApproved("745123456"), true)
    }
}
