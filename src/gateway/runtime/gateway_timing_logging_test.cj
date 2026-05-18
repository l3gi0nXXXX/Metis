package metis.gateway.runtime

import std.env.{getVariable, setVariable}
import std.unittest.testmacro.*

@Test
public class GatewayTimingLoggingTest {
    @TestCase
    public func gatewayCliTimingMessageFormatsElapsedMs(): Unit {
        @Expect(
            gatewayCliTimingMessage("restart", "launch-done", 1000, nowMs: 1123),
            "[gateway.timing] flow=restart step=launch-done elapsedMs=123"
        )
    }

    @TestCase
    public func gatewayLaunchTimingMessageFormatsElapsedMs(): Unit {
        @Expect(
            gatewayLaunchTimingMessage("nohup-launch-done", 2000, nowMs: 2150),
            "[gateway.timing] flow=launch step=nohup-launch-done elapsedMs=150"
        )
    }

    @TestCase
    public func gatewayRunVerboseRaisesConsoleLevelToDebugWithoutLoweringTrace(): Unit {
        let oldConsoleLevel = getVariable("METIS_CONSOLE_LEVEL")
        try {
            setVariable("METIS_CONSOLE_LEVEL", "warn")
            gatewayCliApplyVerboseRuntimeLogging(true)
            @Expect(getVariable("METIS_CONSOLE_LEVEL").getOrThrow(), "debug")

            setVariable("METIS_CONSOLE_LEVEL", "trace")
            gatewayCliApplyVerboseRuntimeLogging(true)
            @Expect(getVariable("METIS_CONSOLE_LEVEL").getOrThrow(), "trace")
        } finally {
            match (oldConsoleLevel) {
                case Some(value) => setVariable("METIS_CONSOLE_LEVEL", value)
                case None => setVariable("METIS_CONSOLE_LEVEL", "")
            }
        }
    }
}
