package metis.gateway.core

import metis.core.config.GatewayUserSettings

import std.unittest.testmacro.*

@Test
public class GatewayTelegramAutoTopicLabelTest {
    @TestCase
    public func autoTopicLabelCanBeDisabledByFlagOrStrategy(): Unit {
        var user = GatewayUserSettings()
        user.telegram.autoTopicLabel.enabled = false
        @Expect(gatewayTelegramAutoTopicLabelEnabled(user), false)

        user.telegram.autoTopicLabel.enabled = true
        user.telegram.autoTopicLabel.strategy = "off"
        @Expect(gatewayTelegramAutoTopicLabelEnabled(user), false)
        @Expect(gatewayTelegramAutoTopicLabelStrategy(user), "off")
    }

    @TestCase
    public func modelStrategyFallsBackToConfiguredModeWithoutBlockingDeterministicTitle(): Unit {
        var user = GatewayUserSettings()
        user.telegram.autoTopicLabel.strategy = "model"
        @Expect(gatewayTelegramAutoTopicLabelEnabled(user), true)
        @Expect(gatewayTelegramAutoTopicLabelStrategy(user), "model")
        @Expect(gatewayTelegramDeterministicAutoTopicLabel("review current code and architecture"), "review current code and")
    }

    @TestCase
    public func deterministicLabelStripsMediaMarkersAndBoundsLength(): Unit {
        @Expect(gatewayTelegramDeterministicAutoTopicLabel("[photo]\ncaption"), "Metis topic")
        @Expect(gatewayTelegramDeterministicAutoTopicLabel("one two three four five six"), "one two three four")
        @Expect(gatewayTelegramDeterministicAutoTopicLabel("abcdefghijklmnopqrstuvwxyz0123456789"), "abcdefghijklmnopqrstuvwxyz012345")
    }
}
