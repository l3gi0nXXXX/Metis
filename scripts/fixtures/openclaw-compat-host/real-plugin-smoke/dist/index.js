export default async function register(api) {
  api.registerTool({ name: "real.fixture.tool" }, async () => ({ ok: true }));
}
