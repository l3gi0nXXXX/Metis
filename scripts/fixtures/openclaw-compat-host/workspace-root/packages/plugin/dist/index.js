import { sharedValue } from "@fixture/shared";

export default async function register(api) {
  api.registerTool({ name: "workspace.fixture.tool", sharedValue }, async () => ({ ok: true, sharedValue }));
}
