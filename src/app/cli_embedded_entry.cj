package metis.app

public func runEmbeddedPrompt(prompt: String): Unit {
    let app = CliApp()
    app.startNonInteractive(prompt)
}
