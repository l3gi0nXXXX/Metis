package metis.core.support_surface_tests

import metis.program_support.*

import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager, MetisProcessEnvironmentLock}

import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
import std.time.DateTime

private func programSupportRestoreVariable(name: String, value: Option<String>): Unit {
    match (value) {
        case Some(v) => setVariable(name, v)
        case None => setVariable(name, "")
    }
}

private func programSupportResetConfigCaches(): Unit {
    CliConfig.invalidatePathCache()
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
}

public func withProgramSupportConfigTestHome<T>(label: String, block: (Path) -> T): T {
    synchronized(MetisProcessEnvironmentLock) {
        let home = Path("/tmp").join("metis-program-support-${label}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}")
        try { remove(home, recursive: true) } catch (_: Exception) { () }
        Directory.create(home, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", home.toString())
        programSupportResetConfigCaches()
        try {
            return block(home)
        } finally {
            programSupportRestoreVariable("METIS_HOME", oldHome)
            programSupportResetConfigCaches()
            try { remove(home, recursive: true) } catch (_: Exception) { () }
        }
    }
}
