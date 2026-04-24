package metis.lsp

import std.sync.*
import std.collection.*

public enum PromiseState<T> {
    | Pending
    | Fulfilled(T)
    | Rejected(String)
}

public class Promise<T> {
    private let state: Mutex
    private let condition: Condition
    private var currentState: PromiseState<T>

    public init() {
        this.state = Mutex()
        synchronized(this.state) {
            this.condition = this.state.condition()
        }
        this.currentState = PromiseState.Pending
    }

    public func resolve(value: T): Unit {
        synchronized(this.state) {
            match (this.currentState) {
                case Pending =>
                    this.currentState = PromiseState.Fulfilled(value)
                    this.condition.notifyAll()
                case _ => ()
            }
        }
    }

    public func reject(error: String): Unit {
        synchronized(this.state) {
            match (this.currentState) {
                case Pending =>
                    this.currentState = PromiseState.Rejected(error)
                    this.condition.notifyAll()
                case _ => ()
            }
        }
    }

    public func get(): T {
        synchronized(this.state) {
            this.condition.waitUntil({ =>
                match (this.currentState) {
                    case Pending => false
                    case _ => true
                }
            })

            match (this.currentState) {
                case Fulfilled(value) => value
                case Rejected(error) => throw Exception(error)
                case _ => throw Exception("Unexpected state")
            }
        }
    }

    public func tryGet(): Option<T> {
        synchronized(this.state) {
            match (this.currentState) {
                case Fulfilled(value) => Some(value)
                case _ => None
            }
        }
    }

    public func isPending(): Bool {
        synchronized(this.state) {
            match (this.currentState) {
                case Pending => true
                case _ => false
            }
        }
    }

    public func isFulfilled(): Bool {
        synchronized(this.state) {
            match (this.currentState) {
                case Fulfilled(_) => true
                case _ => false
            }
        }
    }

    public func isRejected(): Bool {
        synchronized(this.state) {
            match (this.currentState) {
                case Rejected(_) => true
                case _ => false
            }
        }
    }
}