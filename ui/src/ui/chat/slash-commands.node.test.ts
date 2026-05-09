import { describe, expect, it } from "vitest";
import { parseSlashCommand, SLASH_COMMANDS } from "./slash-commands.ts";

describe("parseSlashCommand", () => {
  it("parses commands with an optional colon separator", () => {
    expect(parseSlashCommand("/think: high")).toMatchObject({
      command: { name: "think" },
      args: "high",
    });
    expect(parseSlashCommand("/think:high")).toMatchObject({
      command: { name: "think" },
      args: "high",
    });
    expect(parseSlashCommand("/help:")).toMatchObject({
      command: { name: "help" },
      args: "",
    });
  });

  it("still parses space-delimited commands", () => {
    expect(parseSlashCommand("/verbose full")).toMatchObject({
      command: { name: "verbose" },
      args: "full",
    });
  });

  it("parses fast commands", () => {
    expect(parseSlashCommand("/fast:on")).toMatchObject({
      command: { name: "fast" },
      args: "on",
    });
  });

  it("keeps /status on the agent path", () => {
    const status = SLASH_COMMANDS.find((entry) => entry.name === "status");
    expect(status?.executeLocal).not.toBe(true);
    expect(parseSlashCommand("/status")).toMatchObject({
      command: { name: "status" },
      args: "",
    });
  });

  it("executes /commands locally as the Control UI help alias", () => {
    expect(SLASH_COMMANDS.find((entry) => entry.key === "commands")).toMatchObject({
      name: "commands",
      executeLocal: true,
      description: "Show the same Control UI slash command help as /help.",
    });
    expect(parseSlashCommand("/commands")).toMatchObject({
      command: { key: "commands", executeLocal: true },
      args: "",
    });
  });

  it("includes shared /tools with shared arg hints", () => {
    const tools = SLASH_COMMANDS.find((entry) => entry.name === "tools");
    expect(tools).toMatchObject({
      key: "tools",
      description: "List available runtime tools.",
      argOptions: ["compact", "verbose"],
      executeLocal: false,
    });
    expect(parseSlashCommand("/tools verbose")).toMatchObject({
      command: { name: "tools" },
      args: "verbose",
    });
  });

  it("parses slash aliases through the shared registry", () => {
    const exportCommand = SLASH_COMMANDS.find((entry) => entry.key === "export-session");
    expect(exportCommand).toMatchObject({
      name: "export-session",
      aliases: ["export"],
      executeLocal: true,
    });
    expect(parseSlashCommand("/export")).toMatchObject({
      command: { key: "export-session" },
      args: "",
    });
    expect(parseSlashCommand("/export-session")).toMatchObject({
      command: { key: "export-session" },
      args: "",
    });
  });

  it("keeps canonical long-form slash names as the primary menu command", () => {
    expect(SLASH_COMMANDS.find((entry) => entry.key === "verbose")).toMatchObject({
      name: "verbose",
      aliases: ["v"],
    });
    expect(SLASH_COMMANDS.find((entry) => entry.key === "think")).toMatchObject({
      name: "think",
      aliases: expect.arrayContaining(["thinking", "t"]),
    });
  });

  it("keeps a single local /steer entry with the control-ui metadata", () => {
    const steerEntries = SLASH_COMMANDS.filter((entry) => entry.name === "steer");
    expect(steerEntries).toHaveLength(1);
    expect(steerEntries[0]).toMatchObject({
      key: "steer",
      description:
        "Soft-inject a message into the current active run or one named subagent; does not restart the run.",
      args: "[id] <message>",
      aliases: expect.arrayContaining(["tell"]),
      executeLocal: true,
    });
  });

  it("documents /stop and /kill with Control UI-specific semantics", () => {
    expect(SLASH_COMMANDS.find((entry) => entry.key === "stop")).toMatchObject({
      description: "Abort the current Control UI chat turn only; does not kill subagents.",
      executeLocal: true,
    });
    expect(SLASH_COMMANDS.find((entry) => entry.key === "kill")).toMatchObject({
      args: "<id|all>",
      description:
        "Abort matching sub-agent sessions in the current Control UI session subtree; use all for every active subagent.",
      executeLocal: true,
    });
  });

  it("keeps focus as a local slash command", () => {
    expect(parseSlashCommand("/focus")).toMatchObject({
      command: { key: "focus", executeLocal: true },
      args: "",
    });
  });
});
