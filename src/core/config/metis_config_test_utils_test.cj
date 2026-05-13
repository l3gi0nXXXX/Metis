package metis.core.config

import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
import std.time.DateTime

public func metisConfigTestResetCaches(): Unit {
    CliConfig.invalidatePathCache()
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
}

public func metisConfigTestTempHome(label: String): Path {
    Path("/tmp").join("metis-core-config-${label}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}")
}

private func metisConfigRestoreVariable(name: String, value: Option<String>): Unit {
    match (value) {
        case Some(v) => setVariable(name, v)
        case None => setVariable(name, "")
    }
}

public func withMetisConfigTestHome<T>(label: String, block: (Path) -> T): T {
    synchronized(MetisProcessEnvironmentLock) {
        let home = metisConfigTestTempHome(label)
        try { remove(home, recursive: true) } catch (_: Exception) { () }
        Directory.create(home, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", home.toString())
        metisConfigTestResetCaches()
        try {
            return block(home)
        } finally {
            metisConfigRestoreVariable("METIS_HOME", oldHome)
            metisConfigTestResetCaches()
            try { remove(home, recursive: true) } catch (_: Exception) { () }
        }
    }
}

public func withMetisConfigTestUserHome<T>(label: String, block: (Path) -> T): T {
    synchronized(MetisProcessEnvironmentLock) {
        let home = metisConfigTestTempHome(label)
        try { remove(home, recursive: true) } catch (_: Exception) { () }
        Directory.create(home, recursive: true)
        let oldHome = getVariable("HOME")
        let oldUserProfile = getVariable("USERPROFILE")
        let oldStateHome = getVariable("METIS_HOME")
        setVariable("HOME", home.toString())
        setVariable("USERPROFILE", home.toString())
        setVariable("METIS_HOME", "")
        metisConfigTestResetCaches()
        try {
            return block(home)
        } finally {
            metisConfigRestoreVariable("HOME", oldHome)
            metisConfigRestoreVariable("USERPROFILE", oldUserProfile)
            metisConfigRestoreVariable("METIS_HOME", oldStateHome)
            metisConfigTestResetCaches()
            try { remove(home, recursive: true) } catch (_: Exception) { () }
        }
    }
}
