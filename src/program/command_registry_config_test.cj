package metis.program

import metis.core.config.{CliSettingManager, MetisConfigManager}

import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, remove}
import std.unittest.testmacro.*

@Test
public class CommandRegistryConfigTest {
    @TestCase
    public func registeredRootDispatchDoesNotMigrateLegacyMetaNamespace(): Unit {
        let testHome = "/tmp/metis-phase1-command-registry-no-legacy-meta-migration"
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

        let config = "{\n" +
            "  \"agents\": {\"defaults\": {\"workspace\": \"/tmp/project\"}},\n" +
            "  \"gateway\": {\"auth\": {\"mode\": \"token\", \"token\": \"existing-token\"}},\n" +
            "  \"session\": {},\n" +
            "  \"meta\": {\"cangjieclaw\": {\"wizard\": {\"lastWorkspace\": \"/tmp/legacy-project\"}}}\n" +
            "}\n"
        let path = MetisConfigManager.configPath()
        File.writeTo(path, config.toArray())

        let result = cliDispatchRegisteredRootCommand(["unknown-root-command"])
        @Expect(result.isNone(), true)
        @Expect(String.fromUtf8(File.readFrom(path)), config)

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }
}
