package metis.gateway.runtime

import metis.core.config.{CliSettingManager, GatewayUserSettings, MetisConfigManager}
import metis.gateway.core.{gatewayFindSessionCatalogViewForUser, gatewayBuildSessionConversationView, gatewaySessionStoreForUserWithAgentId}

import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
import std.unittest.testmacro.*

private func withGatewayControlUiHelpersTestHome<T>(block: () -> T): T {
    let testHome = "/tmp/metis-gateway-control-ui-helpers-test-home"
    try {
        remove(Path(testHome), recursive: true)
    } catch (_: Exception) {
        ()
    }
    Directory.create(testHome, recursive: true)
    let oldHome = getVariable("METIS_HOME")
    setVariable("METIS_HOME", testHome)
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
    try {
        return block()
    } finally {
        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }
}

@Test
public class GatewayControlUiHelpersTest {
    @TestCase
    public func summarizeSessionReadsUnifiedAgentStore(): Unit {
        withGatewayControlUiHelpersTestHome {
            let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "general")
            let sessionKey = "agent:general:main"
            store.deleteSession(sessionKey)
            store.appendUser(sessionKey, "hello")
            store.appendAssistant(sessionKey, "world")

            let (count, approx, _updatedTs, lastRole) = gatewayControlUiSummarizeSession(sessionKey)
            @Expect(count, 2)
            @Expect(approx > 0, true)
            @Expect(lastRole, "assistant")

            store.deleteSession(sessionKey)
        }
    }

    @TestCase
    public func recentMessagesResolveUnifiedAgentStore(): Unit {
        withGatewayControlUiHelpersTestHome {
            let user = GatewayUserSettings()
            let store = gatewaySessionStoreForUserWithAgentId(user, "main")
            let sessionKey = "cli:main"
            store.deleteSession(sessionKey)
            store.appendUser(sessionKey, "hello")
            store.appendAssistant(sessionKey, "world")

            let lines = gatewayControlUiBuildRecentMessagesResolved(user, [sessionKey], 10)
            @Expect(lines.size, 2)
            @Expect(lines[0].contains("CLI [user] hello"), true)
            @Expect(lines[1].contains("CLI [assistant] world"), true)

            store.deleteSession(sessionKey)
        }
    }

    @TestCase
    public func recentMessagesForConversationsUseDisplayName(): Unit {
        withGatewayControlUiHelpersTestHome {
            let user = GatewayUserSettings()
            let store = gatewaySessionStoreForUserWithAgentId(user, "main")
            let sessionKey = "cli:main"
            store.deleteSession(sessionKey)
            store.appendUser(sessionKey, "hello")
            store.appendAssistant(sessionKey, "world")

            let view = gatewayFindSessionCatalogViewForUser(user, sessionKey).getOrThrow()
            let lines = gatewayControlUiBuildRecentMessagesForConversations(
                user,
                [gatewayBuildSessionConversationView(view)],
                10
            )
            @Expect(lines.size, 2)
            @Expect(lines[0].contains("CLI [user] hello"), true)
            @Expect(lines[1].contains("CLI [assistant] world"), true)

            store.deleteSession(sessionKey)
        }
    }
}
