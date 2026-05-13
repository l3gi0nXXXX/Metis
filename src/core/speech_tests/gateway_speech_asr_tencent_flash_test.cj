package metis.core.speech_tests

import metis.core.*

import std.unittest.*
import stdx.encoding.json.{JsonBool, JsonInt, JsonObject, JsonString}

private func tencentFlashTestConfig(): JsonObject {
    let cfg = JsonObject()
    cfg.put("appId", JsonString("123456"))
    cfg.put("secretId", JsonString("test-secret-id"))
    cfg.put("secretKey", JsonString("test-secret-key"))
    cfg.put("engineType", JsonString("16k_zh"))
    cfg.put("timeoutMs", JsonInt(30000))
    cfg.put("maxBytes", JsonInt(1024))
    cfg.put("endpoint", JsonString("https://asr.cloud.tencent.com/asr/flash/v1"))
    return cfg
}

private func tencentFlashTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func tencentFlashTestBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

@Test
public class GatewaySpeechAsrTencentFlashTest {
    @TestCase
    public func buildRequestSortsQueryAndSignsLikeOpenClawChina(): Unit {
        let request = gatewaySpeechAsrTencentFlashBuildRequest(tencentFlashTestConfig(), 1700000000)

        @Expect(tencentFlashTestString(request, "query"), "engine_type=16k_zh&secretid=test-secret-id&timestamp=1700000000&voice_format=silk")
        @Expect(tencentFlashTestString(request, "signText"), "POSTasr.cloud.tencent.com/asr/flash/v1/123456?engine_type=16k_zh&secretid=test-secret-id&timestamp=1700000000&voice_format=silk")
        @Expect(tencentFlashTestString(request, "authorization"), "fZuCfIk6EwNaS8em4Cw4DDNZGUw=")
        @Expect(tencentFlashTestString(request, "url"), "https://asr.cloud.tencent.com/asr/flash/v1/123456?engine_type=16k_zh&secretid=test-secret-id&timestamp=1700000000&voice_format=silk")
    }

    @TestCase
    public func parseFlashResultTextJoinsNonEmptyItems(): Unit {
        let result = gatewaySpeechAsrTencentFlashParseResponse(200, "{\"code\":0,\"message\":\"ok\",\"flash_result\":[{\"text\":\" hello \"},{\"text\":\"world\"}]}")

        @Expect(tencentFlashTestBool(result, "ok"), true)
        @Expect(tencentFlashTestString(result, "status"), "ok")
        @Expect(tencentFlashTestString(result, "transcript"), "hello\nworld")
    }

    @TestCase
    public func parseSentenceListFallbackWhenItemTextMissing(): Unit {
        let raw = "{\"code\":0,\"flash_result\":[{\"sentence_list\":[{\"text\":\"first\"},{\"text\":\" second \"}]}]}"
        let result = gatewaySpeechAsrTencentFlashParseResponse(200, raw)

        @Expect(tencentFlashTestBool(result, "ok"), true)
        @Expect(tencentFlashTestString(result, "transcript"), "first\nsecond")
    }

    @TestCase
    public func providerCodeFailureMapsToProviderErrorWithoutSecrets(): Unit {
        let result = gatewaySpeechAsrTencentFlashParseResponse(200, "{\"code\":100,\"message\":\"bad test-secret-key\"}")

        @Expect(tencentFlashTestBool(result, "ok"), false)
        @Expect(tencentFlashTestString(result, "status"), "provider_error")
        @Expect(tencentFlashTestString(result, "message").contains("test-secret-key"), false)
    }

    @TestCase
    public func authHttpFailureMapsToAuthError(): Unit {
        let result = gatewaySpeechAsrTencentFlashParseResponse(403, "{\"code\":403,\"message\":\"Forbidden\"}")

        @Expect(tencentFlashTestBool(result, "ok"), false)
        @Expect(tencentFlashTestString(result, "status"), "auth_error")
    }

    @TestCase
    public func transcribeRejectsOversizedAudioBeforeRunner(): Unit {
        let cfg = tencentFlashTestConfig()
        cfg.put("maxBytes", JsonInt(1))
        setGatewaySpeechAsrTencentFlashRunnerForTest(Some({ request: JsonObject, audio: Array<Byte> =>
            if (request.toJsonString().isEmpty() && audio.size == 0) {
                return GatewaySpeechAsrTencentFlashHttpResult(500, body: "{\"code\":500}")
            }
            GatewaySpeechAsrTencentFlashHttpResult(200, body: "{\"code\":0,\"flash_result\":[{\"text\":\"should not run\"}]}")
        }))
        let result = gatewaySpeechAsrTencentFlashTranscribeAudio(cfg, "too-large".toArray(), timestamp: 1700000000)
        setGatewaySpeechAsrTencentFlashRunnerForTest(None<(JsonObject, Array<Byte>) -> GatewaySpeechAsrTencentFlashHttpResult>)

        @Expect(tencentFlashTestBool(result, "ok"), false)
        @Expect(tencentFlashTestString(result, "status"), "too_large")
        @Expect(tencentFlashTestString(result, "transcript"), "")
    }

    @TestCase
    public func envReferenceMissingIsNotConfiguredAndDoesNotLeakPlaceholder(): Unit {
        let cfg = tencentFlashTestConfig()
        cfg.put("secretKey", JsonString("$" + "{METIS_TEST_TENCENT_FLASH_SECRET_KEY_SHOULD_NOT_EXIST}"))
        let result = gatewaySpeechAsrTencentFlashTranscribeAudio(cfg, "audio".toArray(), timestamp: 1700000000)

        @Expect(tencentFlashTestBool(result, "ok"), false)
        @Expect(tencentFlashTestString(result, "status"), "not_configured")
        @Expect(result.toJsonString().contains("METIS_TEST_TENCENT_FLASH_SECRET_KEY_SHOULD_NOT_EXIST"), false)
    }
}
