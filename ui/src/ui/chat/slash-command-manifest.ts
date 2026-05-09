import type { IconName } from "../icons.ts";
import type { SlashCommandCategory } from "./slash-commands.ts";

export type SlashCommandManifestEntry = {
  key: string;
  category?: SlashCommandCategory;
  description?: string;
  args?: string;
  icon?: IconName;
  executeLocal?: boolean;
};

export const CONTROL_UI_SLASH_MANIFEST: SlashCommandManifestEntry[] = [
  { key: "help", icon: "book", category: "tools", executeLocal: true },
  {
    key: "commands",
    icon: "book",
    category: "tools",
    description: "Show the same Control UI slash command help as /help.",
    executeLocal: true,
  },
  { key: "tools", icon: "terminal", category: "tools" },
  { key: "skill", icon: "zap", category: "tools" },
  { key: "status", icon: "barChart", category: "tools" },
  { key: "usage", icon: "barChart", category: "tools", executeLocal: true },
  { key: "export-session", icon: "download", category: "tools", executeLocal: true },
  { key: "tts", icon: "volume2", category: "tools" },
  { key: "new", icon: "plus", category: "session", executeLocal: true },
  { key: "reset", icon: "refresh", category: "session", executeLocal: true },
  {
    key: "stop",
    icon: "stop",
    category: "session",
    description: "Abort the current Control UI chat turn only; does not kill subagents.",
    executeLocal: true,
  },
  { key: "compact", icon: "loader", category: "session", executeLocal: true },
  { key: "focus", icon: "eye", category: "session", executeLocal: true },
  { key: "unfocus", icon: "eye", category: "session" },
  { key: "session", category: "session" },
  { key: "model", icon: "brain", category: "model", executeLocal: true },
  { key: "models", icon: "brain", category: "model" },
  { key: "think", icon: "brain", category: "model", executeLocal: true },
  { key: "verbose", icon: "terminal", category: "model", executeLocal: true },
  { key: "fast", icon: "zap", category: "model", executeLocal: true },
  { key: "reasoning", category: "model" },
  { key: "elevated", category: "model" },
  { key: "queue", category: "model" },
  { key: "agents", icon: "monitor", category: "agents", executeLocal: true },
  { key: "subagents", icon: "folder", category: "agents" },
  {
    key: "kill",
    icon: "x",
    category: "agents",
    description:
      "Abort matching sub-agent sessions in the current Control UI session subtree; use all for every active subagent.",
    args: "<id|all>",
    executeLocal: true,
  },
  {
    key: "steer",
    icon: "send",
    category: "agents",
    description:
      "Soft-inject a message into the current active run or one named subagent; does not restart the run.",
    args: "[id] <message>",
    executeLocal: true,
  },
  {
    key: "redirect",
    icon: "refresh",
    category: "agents",
    description: "Abort and restart the current run or one named subagent with a new message.",
    args: "[id] <message>",
    executeLocal: true,
  },
];

export const CONTROL_UI_ONLY_SLASH_COMMANDS: SlashCommandManifestEntry[] = [
  {
    key: "clear",
    category: "session",
    description: "Clear chat history.",
    icon: "trash",
    executeLocal: true,
  },
  CONTROL_UI_SLASH_MANIFEST.find((entry) => entry.key === "redirect")!,
];

export const LOCAL_SLASH_COMMAND_KEYS = new Set(
  [...CONTROL_UI_SLASH_MANIFEST, ...CONTROL_UI_ONLY_SLASH_COMMANDS]
    .filter((entry) => entry.executeLocal)
    .map((entry) => entry.key),
);

export const CONTROL_UI_SLASH_MANIFEST_BY_KEY = new Map(
  CONTROL_UI_SLASH_MANIFEST.map((entry) => [entry.key, entry]),
);
