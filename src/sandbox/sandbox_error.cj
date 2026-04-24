package metis.sandbox

class SandboxError <: Exception {
    public init(message: String) {
        super(message)
    }
}

class FatalSandboxError <: Exception {
    public init(message: String) {
        super(message)
    }
}