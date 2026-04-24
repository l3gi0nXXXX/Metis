package metis.gateway.runtime

import metis.gateway.core.GatewayService

import std.sync.Mutex

private let gatewayRuntimeStateLock = Mutex()
private var activeGatewayService: Option<GatewayService> = None

public func gatewayRegisterActiveService(service: GatewayService): Unit {
    synchronized(gatewayRuntimeStateLock) {
        activeGatewayService = Some(service)
    }
}

public func gatewayClearActiveService(): Unit {
    synchronized(gatewayRuntimeStateLock) {
        activeGatewayService = None
    }
}

public func gatewayActiveService(): Option<GatewayService> {
    synchronized(gatewayRuntimeStateLock) {
        activeGatewayService
    }
}
