import { describe, expect, it } from "vitest";
import { parseLogLine } from "./logs.ts";

describe("parseLogLine", () => {
  it("prefers the human-readable message field when structured data is stored in slot 1", () => {
    const line = JSON.stringify({
      0: '{"subsystem":"gateway/ws"}',
      1: {
        cause: "unauthorized",
        authReason: "password_missing",
      },
      2: "closed before connect conn=abc code=4008 reason=connect failed",
      _meta: {
        date: "2026-03-13T19:07:12.128Z",
        logLevelName: "WARN",
      },
      time: "2026-03-13T14:07:12.138-05:00",
    });

    expect(parseLogLine(line)).toEqual(
      expect.objectContaining({
        level: "warn",
        subsystem: "gateway/ws",
        message: "closed before connect conn=abc code=4008 reason=connect failed",
      }),
    );
  });

  it("parses Metis JSONL fields directly", () => {
    const line = JSON.stringify({
      ts: "2026-05-18T10:00:00.000Z",
      level: "info",
      subsystem: "gateway/channel/telegram",
      event: "message.inbound",
      message: "inbound accepted",
      accountId: "default",
    });

    expect(parseLogLine(line)).toEqual(
      expect.objectContaining({
        time: "2026-05-18T10:00:00.000Z",
        level: "info",
        subsystem: "gateway/channel/telegram",
        event: "message.inbound",
        message: "inbound accepted",
      }),
    );
  });
});
