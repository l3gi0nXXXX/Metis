package metis.gateway.core

import metis.core.config.GatewayUserSettings

import std.fs.{File, Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

@Test
public class TelegramApprovalResolverTest {
    private func tempPath(label: String): Path {
        Path("/tmp/metis-telegram-approval-${label}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}.json")
    }

    private func approvalText(id: String, decision: String, sender: String): String {
        "[telegram-approval]\nid=cb-1\nmessageId=101\napprovalId=${id}\ndecision=${decision}\nby=${sender}"
    }

    @TestCase
    public func resolvesPendingApprovalInTemporaryStore(): Unit {
        let path = this.tempPath("resolve")
        try {
            let row = JsonObject()
            row.put("id", JsonString("appr-1"))
            row.put("status", JsonString("pending"))
            let arr = JsonArray([])
            arr.add(row)
            let root = JsonObject()
            root.put("approvals", arr)
            File.writeTo(path, root.toJsonString().toArray())

            var user = GatewayUserSettings()
            user.telegram.allowFrom = ["8734062810"]
            let resolved = gatewayResolveTelegramApprovalCallback(
                this.approvalText("appr-1", "allow-once", "8734062810"),
                user,
                approvalsPath: path
            )
            @Expect(resolved.get("ok").getOrThrow().asBool().getValue(), true)
            let saved = String.fromUtf8(File.readFrom(path))
            @Expect(saved.contains("approved"), true)
            @Expect(saved.contains("allow-once"), true)
            @Expect(saved.contains("8734062810"), true)
        } finally {
            try { remove(path) } catch (_: Exception) { () }
        }
    }

    @TestCase
    public func rejectsUnauthorizedSenderBeforeStoreMutation(): Unit {
        let path = this.tempPath("reject")
        try {
            let root = JsonObject()
            root.put("id", JsonString("appr-2"))
            root.put("status", JsonString("pending"))
            File.writeTo(path, root.toJsonString().toArray())

            let user = GatewayUserSettings()
            let rejected = gatewayResolveTelegramApprovalCallback(
                this.approvalText("appr-2", "deny", "8734062810"),
                user,
                approvalsPath: path
            )
            @Expect(rejected.get("ok").getOrThrow().asBool().getValue(), false)
            @Expect(rejected.get("error").getOrThrow().asString().getValue(), "sender_not_authorized")
            let saved = String.fromUtf8(File.readFrom(path))
            @Expect(saved.contains("pending"), true)
        } finally {
            try { remove(path) } catch (_: Exception) { () }
        }
    }

    @TestCase
    public func execApprovalApproversOverrideGeneralTelegramAllowlist(): Unit {
        let path = this.tempPath("approvers")
        try {
            let row = JsonObject()
            row.put("id", JsonString("appr-3"))
            row.put("status", JsonString("pending"))
            let arr = JsonArray([])
            arr.add(row)
            let root = JsonObject()
            root.put("approvals", arr)
            File.writeTo(path, root.toJsonString().toArray())

            var user = GatewayUserSettings()
            user.telegram.allowFrom = ["111"]
            user.telegram.execApprovals.approvers = ["tg:8734062810"]
            let resolved = gatewayResolveTelegramApprovalCallback(
                this.approvalText("appr-3", "allow-once", "8734062810"),
                user,
                approvalsPath: path
            )
            @Expect(resolved.get("ok").getOrThrow().asBool().getValue(), true)
        } finally {
            try { remove(path) } catch (_: Exception) { () }
        }
    }

    @TestCase
    public func disabledExecApprovalConfigRejectsBeforeStoreMutation(): Unit {
        let path = this.tempPath("disabled")
        try {
            let row = JsonObject()
            row.put("id", JsonString("appr-4"))
            row.put("status", JsonString("pending"))
            File.writeTo(path, row.toJsonString().toArray())

            var user = GatewayUserSettings()
            user.telegram.allowFrom = ["*"]
            user.telegram.execApprovals.enabled = "off"
            let rejected = gatewayResolveTelegramApprovalCallback(
                this.approvalText("appr-4", "deny", "8734062810"),
                user,
                approvalsPath: path
            )
            @Expect(rejected.get("ok").getOrThrow().asBool().getValue(), false)
            @Expect(rejected.get("error").getOrThrow().asString().getValue(), "sender_not_authorized")
            let saved = String.fromUtf8(File.readFrom(path))
            @Expect(saved.contains("pending"), true)
        } finally {
            try { remove(path) } catch (_: Exception) { () }
        }
    }
}
