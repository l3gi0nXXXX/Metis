package metis.telemetry.otel

import std.deriving.Derive

@Derive[ToString]
public enum LogSeverity {
    | Trace
    | Debug
    | Info
    | Warn
    | Error
    | Fatal
}
