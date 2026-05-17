package metis.core.config

import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

private class ConfigWriteNotificationCapture {
    public var seen: Bool = false
    public var path: String = ""
    public var hash: String = ""

    public init() {}
}

@Test
public class MetisConfigWriteNotificationTest {
    @TestCase
    public func writeRootEmitsInProcessNotificationWithoutReadingRealHome(): Unit {
        let testHome = Path("/tmp/metis-config-write-notification-${DateTime.now().toUnixTimeStamp().toMilliseconds()}").toString()
        try { remove(Path(testHome), recursive: true) } catch (_e: Exception) { () }
        Directory.create(testHome, recursive: true)

        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let capture = ConfigWriteNotificationCapture()
        MetisConfigManager.setWriteRootNotificationHook(Some<(MetisConfigWriteNotification) -> Unit>(
            { event: MetisConfigWriteNotification =>
                capture.seen = true
                capture.path = event.configPath
                capture.hash = event.persistedHash
            }
        ))

        let root = JsonObject()
        let gateway = JsonObject()
        gateway.put("mode", JsonString("local"))
        root.put("gateway", gateway)
        MetisConfigManager.writeRoot(root)

        @Expect(capture.seen, true)
        @Expect(capture.path, MetisConfigManager.configPath().toString())
        @Expect(capture.hash.isEmpty(), false)

        MetisConfigManager.setWriteRootNotificationHook(None<(MetisConfigWriteNotification) -> Unit>)
        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        try { remove(Path(testHome), recursive: true) } catch (_e: Exception) { () }
    }
}
