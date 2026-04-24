package metis.app

import magic.core.agent.AsyncAgentResponse
import magic.log.LogUtils
import metis.io.InputUtils

import std.sync.AtomicBool

class CancelChecker {
    private let escPressed = AtomicBool(false)
    private var future: Option<Future<Unit>> = None
    private let app: CliApp
    private let response: AsyncAgentResponse

    init(app: CliApp, response: AsyncAgentResponse) {
        this.app = app
        this.response = response
    }

    func hasCancel(): Bool {
        return this.escPressed.load()
    }

    func start(): Unit {
        // Spawn a thread to check for ESC cancellation
        this.future = spawn {
            while (!Thread.currentThread.hasPendingCancellation) {
                // Skip ESC polling while terminal input is in use.
                if (!InputUtils.isRequestingInput() && !InputUtils.isTerminalInputLocked() && InputUtils.checkEsc()) {
                    // ESC was pressed, cancel the agent response
                    if (this.escPressed.compareAndSwap(false, true)) {  // Ensure only one cancellation
                        LogUtils.info("ESC pressed, cancelling")
                        // Cancel the response asynchronously
                        this.response.cancel(blocking: false)
                    }
                    return
                }
                sleep(Duration.millisecond * 20) // Poll every 20ms
            }
        }
    }

    /**
     * Stop the cancellation checker thread.
     */
    func stop(): Unit {
        this.future.getOrThrow().cancel()
    }

    /**
     * Wait until the cancellation checker thread stops.
     */
    func waitUntilStop(): Unit {
        try {
            this.future.getOrThrow().get()
        } catch (ex: Exception) {
            LogUtils.error("ESC checker thread ended with exception: ${ex}")
        }
    }
}