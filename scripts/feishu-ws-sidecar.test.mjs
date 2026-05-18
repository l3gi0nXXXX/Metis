import assert from "node:assert/strict";
import test from "node:test";

import { buildEventFrame, parseArgs } from "./feishu-ws-sidecar.mjs";

test("parseArgs accepts explicit Feishu account id", () => {
  const args = parseArgs([
    "--account-id",
    "feishu-writer",
    "--app-id",
    "cli_writer_app",
    "positional",
  ]);

  assert.equal(args["account-id"], "feishu-writer");
  assert.equal(args["app-id"], "cli_writer_app");
  assert.deepEqual(args._, ["positional"]);
});

test("buildEventFrame injects Metis account id and preserves SDK event fields", () => {
  const sdkEvent = {
    tenant_key: "2d310bf3d74f575e",
    app_id: "cli_writer_app",
    message: { message_id: "om_1" },
  };

  const frame = buildEventFrame("im.message.receive_v1", sdkEvent, "feishu-writer");

  assert.equal(frame.type, "event");
  assert.equal(frame.payload.header.event_type, "im.message.receive_v1");
  assert.equal(frame.payload.header.account_id, "feishu-writer");
  assert.equal(frame.payload.event.tenant_key, "2d310bf3d74f575e");
  assert.equal(frame.payload.event.app_id, "cli_writer_app");
});

test("buildEventFrame keeps legacy envelope shape when account id is absent", () => {
  const frame = buildEventFrame("im.message.receive_v1", { app_id: "cli_app" }, "");

  assert.equal(Object.hasOwn(frame.payload.header, "account_id"), false);
  assert.equal(frame.payload.event.app_id, "cli_app");
});
