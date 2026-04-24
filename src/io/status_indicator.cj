package metis.io

import std.time.DateTime
import std.convert.Formattable

/**
 * Formats a duration to a string with units (ms, s, m)
 */
private func formatDuration(dur: Duration): String {
    let ms = dur.toMilliseconds()
    if (ms < 60000) {
        let s = Float64(ms) / 1000.0
        return "${s.format(".1")}s"
    } else {
        let m = Float64(ms) / 60000.0
        return "${m.format(".1")}m"
    }
}

/**
 * The status indicator is printed by another thread
 * We need a data structure to hold the thread future and stop the thread
 */
protected class StatusIndicator {
    private var future: Option<Future<Unit>> = None
    private let message: String
    private var startTime: Option<DateTime> = None

    init(message: String) {
        this.message = message
    }

    protected func start(): Unit {
        this.future = spawn {
            this.startTime = DateTime.now()
            this.work()
        }
    }

    static let INDICATORS = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    static let INITIAL_PREFIX = "${INDICATORS[0]} (0.0ms) "

    private func work(): Unit {
        // During the working indicator, we hide the cursor
        hideCursor()
        // Print message once (with space for spinner) - now includes ESC hint
        PrintUtils.printString(
            "${INITIAL_PREFIX} ${message}... (ESC to interrupt)".withColor(Theme.MUTED), withIndent: true
        )

        var idx = 0
        var prevPrefixSize = INITIAL_PREFIX.size
        while (!Thread.currentThread.hasPendingCancellation) {
            let spinner = INDICATORS[idx % INDICATORS.size]

            let timeElapsed = if (let Some(start) <- this.startTime) {
                formatDuration(DateTime.now() - start)
            } else {
                ""
            }
            let prefix = "${spinner} (${timeElapsed})"

            // If the prefix size has changed, we need to print the whole line
            if (prefix.size != prevPrefixSize) {
                clearScreen(mode: ClearMode.EntireLine)
                PrintUtils.printString(
                    "${prefix} ${message}... (ESC to interrupt)".withColor(Theme.MUTED), withIndent: true
                )
            } else {
                // Overwrite just the prefix
                PrintUtils.printString("\r") // Move cursor to the start of the line
                PrintUtils.printString("", withIndent: true)
                PrintUtils.printString("${prefix}".withColor(Theme.MUTED))
            }
            prevPrefixSize = prefix.size

            sleep(Duration.millisecond * 100)
            idx = (idx + 1) % INDICATORS.size
        }
        clearScreen(mode: ClearMode.EntireLine)
        showCursor()
    }

    protected func stop(): Unit {
        this.future?.cancel()
        this.future?.get()
    }
}