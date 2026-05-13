package metis.core.support_surface_tests

import metis.program_support.*

import metis.core.config.MetisConfigManager

import std.fs.File
import std.unittest.testmacro.*

@Test
public class CommandRegistryConfigTest {
    @TestCase
    public func registeredRootDispatchDoesNotMigrateLegacyMetaNamespace(): Unit {
        withProgramSupportConfigTestHome("command-registry", { _home =>
            let config = "{\n" +
                "  \"agents\": {\"defaults\": {\"workspace\": \"/tmp/project\"}},\n" +
                "  \"gateway\": {\"auth\": {\"mode\": \"token\", \"token\": \"existing-token\"}},\n" +
                "  \"session\": {},\n" +
                "  \"meta\": {\"cangjieclaw\": {\"wizard\": {\"lastWorkspace\": \"/tmp/legacy-project\"}}}\n" +
                "}\n"
            let path = MetisConfigManager.configPath()
            File.writeTo(path, config.toArray())

            MetisConfigManager.initializeIfMissing()
            MetisConfigManager.applyPersistedFieldsToCliConfig()
            @Expect(String.fromUtf8(File.readFrom(path)), config)
        })
    }
}
