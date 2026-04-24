package metis.gateway.runtime

import metis.cron.{CronJob, CronSchedule}
import metis.gateway.session.{GatewayIngressSource, gatewayIngressSourceLabel}

import std.unittest.testmacro.*

@Test
public class CronRunnerTest {
    @TestCase
    public func cronBuildSessionRequestPreservesUnifiedIngressSemantics(): Unit {
        let job = CronJob(
            "job-1",
            "hello cron",
            CronSchedule.every(60000),
            sessionTarget: "main",
            agentId: "general"
        )
        let request = cronBuildSessionRequest(job, 12345)
        @Expect(gatewayIngressSourceLabel(request.source), "cron")
        @Expect(request.channelName, "cron")
        @Expect(request.agentId, "general")
        @Expect(request.text, "hello cron")
        @Expect(request.sessionHint.contains("cron"), true)
    }
}
